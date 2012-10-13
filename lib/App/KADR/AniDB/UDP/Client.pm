package App::KADR::AniDB::UDP::Client;
use common::sense;
use Encode;
use IO::Socket;
use IO::Uncompress::Inflate qw(inflate $InflateError);
use List::MoreUtils qw(mesh);
use List::Util qw(min max);
use Time::HiRes;

use App::KADR::AniDB::EpisodeNumber;

use constant CLIENT_NAME => "kadr";
use constant CLIENT_VER => 1;

use constant SESSION_TIMEOUT => 35 * 60;
use constant MAX_DELAY => 45 * 60;

use constant SHORTTERM_FLOODCONTROL_DELAY => 2;
use constant LONGTERM_FLOODCONTROL_DELAY => 4;
use constant QUERIES_FOR_SHORTTERM_FLOODCONTROL => 5;
use constant QUERIES_FOR_LONGTERM_FLOODCONTROL => 100;

use constant FILE_STATUS_CRCOK  => 0x01;
use constant FILE_STATUS_CRCERR => 0x02;
use constant FILE_STATUS_ISV2   => 0x04;
use constant FILE_STATUS_ISV3   => 0x08;
use constant FILE_STATUS_ISV4   => 0x10;
use constant FILE_STATUS_ISV5   => 0x20;
use constant FILE_STATUS_UNC    => 0x40;
use constant FILE_STATUS_CEN    => 0x80;

use constant FILE_FMASK => "7ff8fff8";
use constant FILE_AMASK => "000000c0";

use constant ANIME_MASK => "f0e0d8fd0000f8";
use constant ANIME_FIELDS =>
qw(aid
	dateflags year type
	romaji_name kanji_name english_name
	total_episodes highest_episode_number air_date
	end_date
	rating rating_votes temp_rating temp_rating_votes
	review_rating review_count is_r18
	special_episode_count credits_episode_count other_episode_count trailer_episode_count
	parody_episode_count
);

use constant EPISODE_FIELDS =>
qw/eid aid length rating vote_count number english_name romaji_name kanji_name air_date/;

use constant FILE_FIELDS => 
qw/fid
   aid eid gid lid other_episodes is_deprecated status
   size ed2k md5 sha1 crc32
   quality source audio_codec audio_bitrate video_codec video_bitrate video_resolution file_type
   dub_language sub_language length description air_date
   group_name group_short_name/;

use constant MYLIST_SINGLE_FIELDS => qw/lid fid eid aid gid date state viewdate storage source other filestate/;

use constant MYLIST_MULTI_FIELDS => qw/anime_title episodes eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd eps_with_state_deleted watched_eps/;

use enum qw(:MYLIST_STATE_=0 UNKNOWN HDD CD DELETED);

my %MYLIST_STATE_NAMES = (
	MYLIST_STATE_UNKNOWN, 'unknown',
	MYLIST_STATE_HDD, 'on HDD',
	MYLIST_STATE_CD, 'on removable media',
	MYLIST_STATE_DELETED, 'deleted',
);

sub new {
	my($class, $opts) = @_;
	my $self = bless {}, $class;
	$self->{username} = $opts->{username} or die 'AniDB error: Need a username';
	$self->{password} = $opts->{password} or die 'AniDB error: Need a password';
	$self->{time_to_sleep_when_busy} = $opts->{time_to_sleep_when_busy};
	$self->{max_attempts} = $opts->{max_attempts} || -1;
	$self->{timeout} = $opts->{timeout} || 15.0;
	$self->{starttime} = time - 1;
	$self->{queries} = 0;
	$self->{last_command} = 0;
	$self->{port} = $opts->{port} || 9000;
	$self->{handle} = IO::Socket::INET->new(Proto => 'udp', LocalPort => $self->{port}) or die($!);
	my $host = gethostbyname('api.anidb.info') or die($!);
	$self->{sockaddr} = sockaddr_in(9000, $host);
	$self;
}

sub anime {
	my ($self, %params) = @_;

	$params{amask} = ANIME_MASK;
	my $res = $self->_sendrecv('ANIME', \%params);
	return if !$res || $res->{code} == 330;

	die 'Unexpected return code for anime query: ' . $res->{code} unless $res->{code} == 230;

	my @keys = ANIME_FIELDS;
	my @fields = (split /\|/, $res->{contents}[0])[0 .. @keys - 1];
	my $r = { mesh @keys, @fields };

	for my $k (qw{rating temp_rating review_rating}) {
		$r->{$k} = $r->{$k} / 100.0 if $r->{$k};
	}
	$r
}

sub episode {
	my ($self, %params) = @_;

	$params{epno} = delete $params{number} if exists $params{number};
	my $res = $self->_sendrecv('EPISODE', \%params);
	return if !$res || $res->{code} == 340;

	die 'Unexpected return code for file query: ' . $res->{code} unless $res->{code} == 240;

	my @keys = EPISODE_FIELDS;
	my @fields = (split /\|/, $res->{contents}[0])[0 .. @keys - 1];
	my $ret = { mesh @keys, @fields };

	if ($ret->{number} !~ /^[PCOST]/) {
		$ret->{number} = int($ret->{number});
	}
	$ret
}

sub file {
	my($self, %params) = @_;

	$params{fmask} = FILE_FMASK;
	$params{amask} = FILE_AMASK;

	my $res = $self->_sendrecv('FILE', \%params);
	return if !$res || $res->{code} == 320;

	die 'Unexpected return code for file query: ' . $res->{code} unless $res->{code} == 220;

	# Parse
	my @keys = FILE_FIELDS;
	my @fields = (split /\|/, $res->{contents}[0])[0 .. @keys - 1];
	+{ mesh @keys, @fields }
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

sub login {
	my($self) = @_;
	return $self if $self->has_session;

	my $res = $self->_sendrecv('AUTH', {user => lc($self->{username}), pass => $self->{password}, protover => 3, client => CLIENT_NAME, clientver => CLIENT_VER, nat => 1, enc => 'UTF8', comp => 1});
	if ($res && ($res->{code} == 200 || $res->{code} == 201) && $res->{header} =~ /^(\w+) ([0-9\.\:]+)/) {
		$self->{skey} = $1;
		$self->{myaddr} = $2;
		return $self;
	}

	die sprintf 'Login failed: %d %s', $res->{code}, $res->{header};
}

sub logout {
	my($self) = @_;
	$self->_sendrecv('LOGOUT') if $self->has_session;
	delete $self->{skey};
	$self;
}

sub mylistedit {
	my ($self, $params) = @_;
	$params->{edit} = 1;
	return $self->mylist_add(%$params);
}

sub mylist_add_query {
	my ($self, $params) = @_;
	my ($type, $value) = $self->mylist_add(%$params);

	if ($type eq 'existing_entry' && !$params->{edit}) {
		$params->{edit} = 1;
		return $self->mylist_add_query($params);
	}

	$value;
}

sub mylist {
	my ($self, %params) = @_;

	my $res = $self->_sendrecv('MYLIST', \%params);

	# No such entry
	return if !$res || $res->{code} == 321;

	my ($type, $info);
	if ($res->{code} == 221) {
		my @keys = MYLIST_SINGLE_FIELDS;
		my @values = (split /\|/, $res->{contents}[0])[0 .. @keys - 1];
		
		$type = 'single';
		$info = { mesh @keys, @values };
	}
	elsif ($res->{code} == 312) {
		my @keys = MYLIST_MULTI_FIELDS;
		my %base_info = ($params{aid} ? (aid => $params{aid}) : ());
		
		$type = 'multiple';
		$info = [ map {
			my @values = (split /\|/, $_)[0 .. @keys - 1];
			+{ %base_info, mesh @keys, @values }
		} @{$res->{contents}} ];
	}

	wantarray ? ($type, $info) : $info;
}

sub mylist_add {
	my ($self, %params) = @_;
	$params{edit} //= 0;

	my $res = $self->_sendrecv('MYLISTADD', \%params);

	# No such entry(s)
	return if !$res || $res->{code} == 320 || $res->{code} == 330 || $res->{code} == 350 || $res->{code} == 411;

	my ($type, $value);
	if ($params{edit}) {
		# Edited
		if ($res->{code} == 311) {
			$type = 'edited';
			$value = int($res->{contents}[0]) || 1;
		}
	}
	else {
		# Added
		if ($res->{code} == 210) {
			$type = $params{fid} || $params{ed2k} ? 'added' : 'added_count';
			$value = int $res->{contents}[0];
		}
		# Entry already exists
		elsif ($res->{code} == 310) {
			my @keys = MYLIST_SINGLE_FIELDS;
			my @values = (split /\|/, $res->{contents}[0])[0 .. @keys - 1];
			
			$type = 'existing_entry';
			$value = { mesh @keys, @values };
		}
		# Multiple entries
		elsif ($res->{code} == 322) {
			$type = 'multiple_entries';
			$value = [ split /\|/, $res->{contents}[0] ];
		}
	}

	wantarray ? ($type => $value) : $value;
}

sub mylist_anime {
	my ($self, %params) = @_;

	my ($type, $mylist) = $self->mylist(%params);

	# Not found
	return unless $mylist;

	# Response was in expected format
	if ($type eq 'multiple') {
		die 'Got response for multiple anime' if @$mylist > 1;
		return $mylist->[0];
	}

	# Mylist data for this anime consists of one episode.

	# File info is needed to emulate the expected output.
	my $file = $self->file(fid => $mylist->{fid});

	# Mylist episode numbers are not zero padded as they are in file info.
	my $epno = EpisodeNumber($file->{episode_number});

	{
		aid => $params{aid},
		anime_title => $file->{anime_romaji_name},
		episodes => $file->{anime_total_episodes},
		eps_with_state_unknown => ($mylist->{state} == MYLIST_STATE_UNKNOWN ? $epno : ''),
		eps_with_state_on_hdd => ($mylist->{state} == MYLIST_STATE_HDD ? $epno : ''),
		eps_with_state_on_cd => ($mylist->{state} == MYLIST_STATE_CD ? $epno : ''),
		eps_with_state_deleted => ($mylist->{state} == MYLIST_STATE_DELETED ? $epno : ''),
		watched_eps => ($mylist->{viewdate} > 0 ? $epno : ''),
	}
}

sub mylist_anime_query {
	my($self, $query) = @_;
	$self->mylist_anime(%$query);
}

sub mylist_file {
	my ($self, %params) = @_;
	my ($type, $info) = $self->mylist(%params);

	# Not found
	return unless $info;

	die 'Got multiple mylist entries response' unless $type eq 'single';

	$info;
}

sub mylist_file_query {
	my ($self, $query) = @_;
	$self->mylist_file(%$query);
}

sub mylist_state_name_for {
	my ($self, $state_id) = @_;
	$MYLIST_STATE_NAMES{$state_id};
}

sub _delay {
	my ($self, $attempts) = @_;
	my $base_delay =
		$self->{queries} > QUERIES_FOR_LONGTERM_FLOODCONTROL ? LONGTERM_FLOODCONTROL_DELAY :
		$self->{queries} > QUERIES_FOR_SHORTTERM_FLOODCONTROL ? SHORTTERM_FLOODCONTROL_DELAY :
		0;
	$self->{last_command} - Time::HiRes::time + min $base_delay * 1.5 ** $attempts, MAX_DELAY;
}

sub _next_tag {
	(
		$_[0]->{_next_tag_generator} ||= do {
			my $i;
			sub { sprintf 'T%x', ++$i };
		}
	)->();
}

sub _response_parse_skeleton {
	my ($self, $bytes) = @_;

	# Inflate compressed responses.
	if (substr($bytes, 0, 2) eq "\x00\x00") {
		# Remove "compressed" flag
		my $data = substr($bytes, 2);

		inflate(\$data, \$bytes)
			or die 'Error inflating response: ' . $InflateError;
	}

	my $string = decode_utf8 $bytes;

	# Contents are newline-terminated.
	my ($header, @contents) = split("\n", $string);

	# Parse header.
	$header =~ s/^(?:(T[0-9a-f]+) )?(\d+) //;
	{tag => $1, code => int $2, header => $header, contents => \@contents}
}

sub _sendrecv {
	my ($self, $command, $params) = @_;
	my $attempts = 0;

	# Auto-login
	unless ($self->has_session || $command eq 'AUTH') {
		$self->login;
	}

	# Prepare request
	$params->{s} = $self->{skey} if $self->{skey};
	$params->{tag} = $self->_next_tag;

	my $req_str
		= $command . ' '
		. join('&', map { $_ . '=' . $params->{$_} } keys %$params) . "\n";
	$req_str = encode_utf8 $req_str;

	while (1) {
		die 'Timeout while waiting for reply'
			if $self->{max_attempts} > 0 && $attempts == $self->{max_attempts};

		# Floodcontrol
		my $delay = $self->_delay($attempts++);
		Time::HiRes::sleep($delay) if $delay > 0;

		# Accounting
		$self->{last_command} = Time::HiRes::time;
		$self->{queries}++;

		# Send
		send($self->{handle}, $req_str, 0, $self->{sockaddr})
			or die 'Send error: ' . $!;

		# Receive
		my $buf;
		my $rin = '';
		my $rout;
		my $timeout = max $self->{timeout}, $self->_delay($attempts);
		vec($rin, fileno($self->{handle}), 1) = 1;
		if (select($rout = $rin, undef, undef, $timeout)) {
			recv($self->{handle}, $buf, 1500, 0)
				or die 'Recv error: ' . $!;
		}

		next unless $buf;

		# Parse
		my $res = $self->_response_parse_skeleton($buf);

		# Temporary IP ban
		die 'Banned' if $res->{code} == 555;

		# Server busy
		if ($res->{code} == 602) {
			Time::HiRes::sleep($self->{time_to_sleep_when_busy});
			$attempts = 0;
			next;
		}

		# Server-side timeout
		next if $res->{code} == 604;

		# Tag mismatch
		next unless $res->{tag} && $res->{tag} eq $params->{tag};

		# Server error
		die sprintf 'AniDB error: %d %s', $res->{code}, $res->{header}
			if $res->{code} > 599 && $res->{code} < 700;

		# Login first / Invalid session
		if ($res->{code} == 501 || $res->{code} == 506) {
			delete $self->{skey};
			return if $command eq 'LOGOUT';
			return $self->_sendrecv($command, $params);
		}

		return $res;
	}
}

sub DESTROY {
	shift->logout;
}

0x6B63;
