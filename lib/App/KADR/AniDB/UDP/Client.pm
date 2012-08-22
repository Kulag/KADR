package App::KADR::AniDB::UDP::Client;
use common::sense;
use Time::HiRes;
use IO::Socket;
use IO::Uncompress::Inflate qw(inflate $InflateError);
use Encode;

use constant CLIENT_NAME => "kadr";
use constant CLIENT_VER => 1;

use constant SESSION_TIMEOUT => 35 * 60;

# Threshhold values are specified in packets.
use constant SHORT_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD => 5;
use constant LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD => 100;

use constant FILE_STATUS_CRCOK  => 0x01;
use constant FILE_STATUS_CRCERR => 0x02;
use constant FILE_STATUS_ISV2   => 0x04;
use constant FILE_STATUS_ISV3   => 0x08;
use constant FILE_STATUS_ISV4   => 0x10;
use constant FILE_STATUS_ISV5   => 0x20;
use constant FILE_STATUS_UNC    => 0x40;
use constant FILE_STATUS_CEN    => 0x80;

use constant FILE_FMASK => "7ff8fff8";
use constant FILE_AMASK => "fefcfcc0";

use constant CODE_220_ENUM => 
qw/fid
   aid eid gid lid other_episodes is_deprecated status
   size ed2k md5 sha1 crc32
   quality source audio_codec audio_bitrate video_codec video_bitrate video_resolution file_type
   dub_language sub_language length description air_date
   anime_total_episodes anime_highest_episode_number anime_year anime_type anime_related_aids anime_related_aid_types anime_categories
   anime_romaji_name anime_kanji_name anime_english_name anime_other_name anime_short_names anime_synonyms
   episode_number episode_english_name episode_romaji_name episode_kanji_name episode_rating episode_vote_count
   group_name group_short_name/;

use constant MYLIST_FILE_ENUM => qw/lid fid eid aid gid date state viewdate storage source other filestate/;

use constant MYLIST_ANIME_ENUM => qw/anime_title episodes eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd eps_with_state_deleted watched_eps/;

use enum qw(:MYLIST_STATE_=0 UNKNOWN HDD CD DELETED);

sub new {
	my($class, $opts) = @_;
	my $self = bless {}, $class;
	$self->{username} = $opts->{username} or die 'AniDB error: Need a username';
	$self->{password} = $opts->{password} or die 'AniDB error: Need a password';
	$self->{time_to_sleep_when_busy} = $opts->{time_to_sleep_when_busy};
	$self->{max_attempts} = $opts->{max_attempts} || 5;
	$self->{timeout} = $opts->{timeout} || 15.0;
	$self->{starttime} = time - 1;
	$self->{queries} = 0;
	$self->{last_command} = 0;
	$self->setup_iohandle($opts->{port} || 9000);
	my $host = gethostbyname('api.anidb.info') or die($!);
	$self->{sockaddr} = sockaddr_in(9000, $host) or die($!);
	$self;
}

sub setup_iohandle {
	my($self, $port) = @_;
	$self->{port} = $port;
	$self->{handle} = IO::Socket::INET->new(Proto => 'udp', LocalPort => $self->{port}) or die($!);
	$self;
}

sub file_query {
	my($self, $query) = @_;

	$query->{fmask} = FILE_FMASK;
	$query->{amask} = FILE_AMASK;

	my $recvmsg = $self->_sendrecv("FILE", $query);
	return unless defined $recvmsg;
	my($code, $data) = split("\n", $recvmsg);
	
	$code = int((split(" ", $code))[0]);
	if($code == 220) { # Success
		my %fileinfo;
		my @fields = split /\|/, $data;
		map { $fileinfo{(CODE_220_ENUM)[$_]} = $fields[$_] } 0 .. scalar(CODE_220_ENUM) - 1;
		
		return \%fileinfo;
	} elsif($code == 322) { # Multiple files found.
		die "Error: \"322 MULITPLE FILES FOUND\" not supported.";
	} elsif($code == 320) { # No such file.
		return;
	} else {
		die "Error: Unexpected return code for file query recieved. Got $code.\n";
	}
}

sub file_version {
	my($self, $file) = @_;
	
	if($file->{status} & FILE_STATUS_ISV2) {
		return 2;
	} elsif($file->{status} & FILE_STATUS_ISV3) {
		return 3;
	} elsif($file->{status} & FILE_STATUS_ISV4) {
		return 4;
	} elsif($file->{status} & FILE_STATUS_ISV5) {
		return 5;
	} else {
		return 1;
	}
}

sub has_session {
	$_[0]->{skey} && (time - $_[0]->{last_command}) < SESSION_TIMEOUT
}

sub mylistadd {
	my $res = shift->mylist_add_query({state => 1, fid => shift});
	return $res;
}

sub mylistedit {
	my ($self, $params) = @_;
	$params->{edit} = 1;
	return $self->mylist_add_query($params);
}

sub mylist_add_query {
	my ($self, $params) = @_;
	my $res;

	if ((!defined $params->{edit}) or $params->{edit} == 0) {
		# Add

		$res = $self->_sendrecv("MYLISTADD", $params);

		if ($res =~ /^210 MYLIST/) { # OK
			return (split(/\n/, $res))[1];
		} elsif ($res !~ /^310/) { # any errors other than 310
			return 0;
		}
		# If 310 ("FILE ALREADY IN MYLIST"), retry with edit=1
		$params->{edit} = 1;
	}
	# Edit

	$res = $self->_sendrecv("MYLISTADD", $params);

	if ($res =~ /^311/) { # OK
		return (split(/\n/, $res))[1];
	}
	return 0; # everything else
}

sub mylist_file_query {
	my($self, $query) = @_;
	
	(my $msg = $self->_sendrecv("MYLIST", $query)) =~ s/.*\n//im;
	
	my @f = split /\|/, $msg;
	if(scalar @f) {
		my %mylistinfo;
		map { $mylistinfo{(MYLIST_FILE_ENUM)[$_]} = $f[$_] } 0 .. $#f;
		return \%mylistinfo;
	}
	undef;
}

sub mylist_anime_query {
	my($self, $query) = @_;
	my $msg = $self->_sendrecv("MYLIST", $query);
	my $single_episode = ($msg =~ /^221/);
	my $success = ($msg =~ /^312/);
	return if not ($success or $single_episode);
	$msg =~ s/.*\n//im;
	my @f = split /\|/, $msg;
	
	if(scalar @f) {
		my %mylistanimeinfo;
		$mylistanimeinfo{aid} = $query->{aid};
		if($single_episode) {
			my %mylistinfo;
			map { $mylistinfo{(MYLIST_FILE_ENUM)[$_]} = $f[$_] } 0 .. $#f;
			
			my $fileinfo = $self->file_query({fid => $mylistinfo{fid}});
			
			$mylistanimeinfo{anime_title} = $fileinfo->{anime_romaji_name};
			$mylistanimeinfo{episodes} = '';
			$mylistanimeinfo{eps_with_state_unknown} = "";
			
			if($fileinfo->{episode_number} =~ /^(\w*?)[0]*(\d+)$/) {
				$mylistanimeinfo{eps_with_state_on_hdd} = "$1$2";
				$mylistanimeinfo{watched_eps} = ($mylistinfo{viewdate} > 0 ? "$1$2" : "");
			} else {
				$mylistanimeinfo{eps_with_state_on_hdd} = $fileinfo->{episode_number};
				$mylistanimeinfo{watched_eps} = ($mylistinfo{viewdate} > 0 ? $fileinfo->{episode_number} : "");
			}
			$mylistanimeinfo{eps_with_state_on_cd} = "";
			$mylistanimeinfo{eps_with_state_deleted} = "";
		} else {
			map { $mylistanimeinfo{(MYLIST_ANIME_ENUM)[$_]} = $f[$_] } 0 .. scalar(MYLIST_ANIME_ENUM) - 1;
		}
		return \%mylistanimeinfo;
	}
	return;
}

sub login {
	my($self) = @_;
	return $self if $self->has_session;

	my $msg = $self->_sendrecv("AUTH", {user => lc($self->{username}), pass => $self->{password}, protover => 3, client => CLIENT_NAME, clientver => CLIENT_VER, nat => 1, enc => "UTF8", comp => 1});
	if ($msg && $msg =~ /20[01]\ ([a-zA-Z0-9]*)\ ([0-9\.\:]).*/) {
		$self->{skey} = $1;
		$self->{myaddr} = $2;
	} else {
		die "Login Failed: $msg\n";
	}

	$self;
}

sub logout {
	my($self) = @_;
	$self->_sendrecv('LOGOUT') if $self->has_session;
	delete $self->{skey};
	$self;
}

sub _sendrecv {
	my($self, $query, $vars) = @_;
	my $recvmsg;
	my $attempts = 0;

	$self->login if !$self->has_session && $query ne "AUTH";

	$vars->{'s'} = $self->{skey} if $self->{skey};
	$vars->{'tag'} = "T" . $self->{queries};
	$query .= ' ' . join('&', map { "$_=$vars->{$_}" } keys %{$vars}) . "\n";
	$query = encode_utf8($query);

	while(!$recvmsg) {
		if($self->{queries} > LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) {
			while((my $waittime = (30 * ($self->{queries} - LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) + $self->{starttime}) - Time::HiRes::time) > 0) {
				Time::HiRes::sleep($waittime);
			}
		}
		if($self->{queries} > SHORT_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) {
			if($self->{last_command} + 2 > Time::HiRes::time) {
				Time::HiRes::sleep($self->{last_command} + 2 - Time::HiRes::time);
			}
		}
		
		$self->{last_command} = Time::HiRes::time;
		$self->{queries} += 1;

		send($self->{handle}, $query, 0, $self->{sockaddr}) or die( "Send error: " . $! );
		
		my $rin = '';
		my $rout;
		vec($rin, fileno($self->{handle}), 1) = 1;
		recv($self->{handle}, $recvmsg, 1500, 0) or die("Recv error:" . $!) if select($rout = $rin, undef, undef, $self->{timeout});

		die "\nTimeout while waiting for reply.\n" if ++$attempts == $self->{max_attempts};
	}

	# Check if the data is compressed.
	if(substr($recvmsg, 0, 2) eq "\x00\x00") {
		my $data = substr($recvmsg, 2);
		if(!inflate(\$data, \$recvmsg)) {
			warn "\nError inflating packet: $InflateError";
			return;
		}
	}
	
	$recvmsg = decode_utf8($recvmsg);

	if($recvmsg =~ /^555/) {
		print "\nBanned, exiting.";
		exit(1);
	}
	
	if($recvmsg =~ /^602/) {
		print "\nAniDB is too busy, will retry in $self->{time_to_sleep_when_busy} seconds.";
		Time::HiRes::sleep($self->{time_to_sleep_when_busy});
		return $self->_sendrecv($query, $vars);
	}
	
	# Check for a server error.
	if ($recvmsg =~ /^(T\d+ )?6\d+/) {
		die("\nAnidb error:\n$recvmsg");
	}
	
	# Check that the answer we received matches the query we sent.
	$recvmsg =~ s/^(T\d+) (.*)/$2/;
	if(not defined($1) or $1 ne $vars->{tag}) {
		warn "\nPort changing\n";
		$self->logout->setup_iohandle($self->{port} + 1)->_sendrecv($query, $vars);
	}
	
	# Check if our session is invalid.
	if($recvmsg =~ /^501.*|^506.*/) {
		undef $self->{skey};
		$self->login();
		return $self->_sendrecv($query, $vars);
	}
	
	return $recvmsg;
}

sub DESTROY {
	shift->logout;
}

0x6B63;
