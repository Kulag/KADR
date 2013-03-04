package App::KADR::AniDB::UDP::Client;
# ABSTRACT: Client for AniDB's UDP API

use App::KADR::AniDB::EpisodeNumber;
use App::KADR::AniDB::Types qw(UserName);
use App::KADR::Moose -noclean => 1;
use Carp qw(croak);
use Const::Fast;
use Encode;
use IO::Socket;
use IO::Uncompress::Inflate qw(inflate $InflateError);
use List::MoreUtils qw(mesh);
use List::Util qw(min max);
use MooseX::Types::LoadableClass qw(LoadableClass);
use MooseX::Types::Moose qw(Int Num Str);
use MooseX::NonMoose;
use Time::HiRes;

extends 'Mojo::EventEmitter';

use constant API_HOST => 'api.anidb.net';
use constant API_PORT => 9000;

use constant CLIENT_NAME => "kadr";
use constant CLIENT_VER => 1;

use constant SESSION_TIMEOUT => 35 * 60;
use constant MAX_DELAY => 45 * 60;

use constant LONGTERM_RATELIMIT_DELAY      => 4;
use constant LONGTERM_RATELIMIT_THRESHOLD  => 100;
use constant SHORTTERM_RATELIMIT_DELAY     => 2;
use constant SHORTTERM_RATELIMIT_THRESHOLD => 5;

use constant FILE_STATUS_CRCOK  => 0x01;
use constant FILE_STATUS_CRCERR => 0x02;
use constant FILE_STATUS_ISV2   => 0x04;
use constant FILE_STATUS_ISV3   => 0x08;
use constant FILE_STATUS_ISV4   => 0x10;
use constant FILE_STATUS_ISV5   => 0x20;
use constant FILE_STATUS_UNC    => 0x40;
use constant FILE_STATUS_CEN    => 0x80;

use constant FILE_FMASK => "7ff8fff8";
use constant FILE_AMASK => "0000fcc0";

use constant ANIME_MASK => "f0e0d8fd0000f8";

const my @ANIME_FIELDS => qw(
	aid dateflags year type
	romaji_name kanji_name english_name
	episode_count highest_episode_number air_date end_date
	rating vote_count temp_rating temp_vote_count review_rating review_count is_r18
	special_episode_count credits_episode_count other_episode_count trailer_episode_count parody_episode_count
);

const my @FILE_FIELDS => qw(
	fid
	aid eid gid lid other_episodes is_deprecated status
	size ed2k md5 sha1 crc32
	quality source audio_codec audio_bitrate video_codec video_bitrate video_resolution file_type
	dub_language sub_language length description air_date
	episode_number episode_english_name episode_romaji_name episode_kanji_name episode_rating episode_vote_count
	group_name group_short_name
);

const my @MYLIST_MULTI_FIELDS => qw(
	anime_title episodes eps_with_state_unknown eps_with_state_on_hdd
	eps_with_state_on_cd eps_with_state_deleted watched_eps
);

const my @MYLIST_FILE_FIELDS => qw(
	lid fid eid aid gid date state viewdate storage source other filestate
);

const my @MYLIST_MULTI_EPISODE_FIELDS => qw(
	eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd
	eps_with_state_deleted watched_eps
);

use enum qw(:MYLIST_STATE_=0 UNKNOWN HDD CD DELETED);

const my %MYLIST_STATE_NAMES => (
	MYLIST_STATE_UNKNOWN, 'unknown',
	MYLIST_STATE_HDD, 'on HDD',
	MYLIST_STATE_CD, 'on removable media',
	MYLIST_STATE_DELETED, 'deleted',
);

has 'max_attempts',              isa => Int,       predicate => 1;
has 'port',     default => 9000, isa => Int;
has 'password',                  isa => Str,       required => 1;
has 'timeout',  default => 15.0, isa => Num;
has 'time_to_sleep_when_busy',   default => 15*60, isa => Int;

has 'tx_class',
	default => 'App::KADR::AniDB::UDP::Transaction',
	isa     => LoadableClass;

has 'username', isa => UserName, required => 1;

has '_handle',      builder => 1, lazy => 1;
has '_last_query_time', default => 0;
has '_query_count', default => 0;
has '_session_key', clearer => 1;
has '_sockaddr',    builder => 1, lazy => 1;
has '_start_time',  is => 'ro',   default => time - 1;

sub anime {
	my ($self, %params) = @_;

	my $tx  = $self->build_tx('anime', {amask => ANIME_MASK, %params});
	my $res = $self->start($tx)->success;

	return if !$res || $res->{code} == 330;

	die 'Unexpected return code for anime query: ' . $res->{code}
		unless $res->{code} == 230;

	my @values = (split /\|/, $res->{contents}[0])[0 .. @ANIME_FIELDS - 1];
	my $anime = { mesh @ANIME_FIELDS, @values };

	for my $field (qw{rating temp_rating review_rating}) {
		$anime->{$field} = $anime->{$field} / 100.0 if $anime->{$field};
	}

	$anime;
}

sub build_tx {
	my ($self, $command, $params) = @_;
	$self->tx_class->new(req => { name => $command, params => $params });
}

sub file {
	my ($self, %params) = @_;

	my $tx = $self->build_tx('file',
		{ fmask => FILE_FMASK, amask => FILE_AMASK, %params });

	my $res = $self->start($tx)->success;
	return if !$res || $res->{code} == 320;

	die 'Unexpected return code for file query: ' . $res->{code} unless $res->{code} == 220;

	# Parse
	my @fields = (split /\|/, $res->{contents}[0])[ 0 .. @FILE_FIELDS - 1 ];
	my $file = { mesh @FILE_FIELDS, @fields };

	$file->{episode_number} = EpisodeNumber($file->{episode_number});

	$file;
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
	$_[0]->_session_key && (time - $_[0]->_last_query_time) < SESSION_TIMEOUT
}

sub login {
	my $self = shift;
	return $self if $self->has_session;

	my $tx = $self->build_tx('AUTH', {
		client => CLIENT_NAME,
		clientver => CLIENT_VER,
		comp => 1,
		enc => 'UTF8',
		nat => 1,
		pass => $self->password,
		protover => 3,
		user => $self->username,
	});

	my $res = $self->start($tx)->success;

	if ($res && ($res->{code} == 200 || $res->{code} == 201) && $res->{header} =~ /^(\w+) ([0-9\.\:]+)/) {
		$self->_session_key($1);
		return $self;
	}

	die sprintf 'Login failed: %d %s', $res->{code}, $res->{header};
}

sub logout {
	my($self) = @_;
	$self->_sendrecv('LOGOUT') if $self->has_session;
	$self->_clear_session_key;
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

	my $tx = $self->build_tx('mylist', \%params);
	my $res = $self->start($tx)->success;

	# No such entry
	return if !$res || $res->{code} == 321;

	my ($type, $info);
	if ($res->{code} == 221) {
		$type = 'single';
		$info = $self->_mylist_file_contents_parse($res->{contents});
	}
	elsif ($res->{code} == 312) {
		my %base_info = ($params{aid} ? (aid => $params{aid}) : ());

		$type = 'multiple';
		$info = [ map {
			my @values = (split /\|/, $_)[ 0 .. @MYLIST_MULTI_FIELDS - 1 ];
			my $info = { %base_info, mesh @MYLIST_MULTI_FIELDS, @values };
			$self->mylist_multi_parse_episodes($info);

			$info;
		} @{$res->{contents}} ];
	}

	wantarray ? ($type, $info) : $info;
}

sub mylist_multi_parse_episodes {
	my ($self, $info) = @_;
	$info->{$_} = EpisodeNumber($info->{$_}) for @MYLIST_MULTI_EPISODE_FIELDS;
	return;
}

sub mylist_add {
	my ($self, %params) = @_;
	$params{edit} //= 0;

	my $tx = $self->build_tx('mylistadd', \%params);
	my $res = $self->start($tx)->success;

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
			$type = 'existing_entry';
			$value = $self->_mylist_file_contents_parse($res->{contents});
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

	# File and anime info is needed to emulate the expected output.
	my $anime = $self->anime(aid => $mylist->{aid});
	my $epno  = $self->file(fid => $mylist->{fid})->{episode_number};
	my $none  = EpisodeNumber();

	{
		aid => $mylist->{aid},
		anime_title => $anime->{romaji_name},
		episodes => $anime->{episode_count},
		eps_with_state_unknown => ($mylist->{state} == MYLIST_STATE_UNKNOWN ? $epno : $none),
		eps_with_state_on_hdd => ($mylist->{state} == MYLIST_STATE_HDD ? $epno : $none),
		eps_with_state_on_cd => ($mylist->{state} == MYLIST_STATE_CD ? $epno : $none),
		eps_with_state_deleted => ($mylist->{state} == MYLIST_STATE_DELETED ? $epno : $none),
		watched_eps => ($mylist->{viewdate} > 0 ? $epno : $none),
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
	$MYLIST_STATE_NAMES{$state_id} or croak 'No such mylist state: ' . $state_id;
}

sub start {
	my ($self, $tx) = @_;

	$self->emit(start => $tx);
	$tx->{res} = $self->_sendrecv(@{ $tx->{req} }{qw(name params)});
	$tx->emit('finish');

	$tx;
}

sub _build__handle {
	IO::Socket::INET->new(Proto => 'udp', LocalPort => $_[0]->port) or die $!;
}

sub _build__sockaddr {
	my $host = gethostbyname(API_HOST) or die $!;
	sockaddr_in(API_PORT, $host);
}

sub _delay {
	my ($self, $attempts) = @_;
	my $count = $self->_query_count;
	my $base_delay
		= $count > LONGTERM_RATELIMIT_THRESHOLD  ? LONGTERM_RATELIMIT_DELAY
		: $count > SHORTTERM_RATELIMIT_THRESHOLD ? SHORTTERM_RATELIMIT_DELAY
		: 0;
	$self->_last_query_time - Time::HiRes::time + min $base_delay * 1.5 ** $attempts, MAX_DELAY;
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

sub _mylist_file_contents_parse {
	my ($self, $contents) = @_;
	my @values = (split /\|/, $contents->[0])[ 0 .. @MYLIST_FILE_FIELDS - 1 ];
	+{ mesh @MYLIST_FILE_FIELDS, @values }
}

sub _sendrecv {
	my ($self, $command, $params) = @_;
	my $attempts = 0;

	# Auto-login
	unless ($self->has_session || $command eq 'AUTH') {
		$self->login;
	}

	# Prepare request
	if (my $s = $self->_session_key) { $params->{s} = $s }
	$params->{tag} = $self->_next_tag;

	my $req_str = uc($command) . ' '
		. join('&', map { $_ . '=' . $params->{$_} } keys %$params) . "\n";
	$req_str = encode_utf8 $req_str;

	my $handle = $self->_handle;
	while (1) {
		die 'Timeout while waiting for reply'
			if $self->has_max_attempts && $attempts == $self->max_attempts;

		# Floodcontrol
		my $delay = $self->_delay($attempts++);
		Time::HiRes::sleep($delay) if $delay > 0;

		# Accounting
		$self->_last_query_time(Time::HiRes::time);
		$self->_query_count($self->_query_count + 1);

		# Send
		$handle->send($req_str, 0, $self->_sockaddr)
			or die 'Send error: ' . $!;

		# Receive
		my $buf;
		my $rin = '';
		my $rout;
		my $timeout = max $self->timeout, $self->_delay($attempts);
		vec($rin, fileno($handle), 1) = 1;
		if (select($rout = $rin, undef, undef, $timeout)) {
			$handle->recv($buf, 1500, 0) or die 'Recv error: ' . $!;
		}

		next unless $buf;

		# Parse
		my $res = $self->_response_parse_skeleton($buf);

		# Temporary IP ban
		die 'Banned' if $res->{code} == 555;

		# Server busy
		if ($res->{code} == 602) {
			Time::HiRes::sleep $self->time_to_sleep_when_busy;
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
			$self->_clear_session_key;
			return if $command eq 'LOGOUT';
			return $self->_sendrecv($command, $params);
		}

		return $res;
	}
}

sub DEMOLISH {
	shift->logout;
}

0x6B63;
