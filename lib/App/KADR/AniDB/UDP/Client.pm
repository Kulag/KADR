package App::KADR::AniDB::UDP::Client;
# ABSTRACT: Client for AniDB's UDP API

use App::KADR::AniDB::Types qw(UserName);
use App::KADR::Moose;
use Carp qw(croak);
use Encode;
use IO::Socket;
use IO::Uncompress::Inflate qw(inflate $InflateError);
use List::Util qw(min max);
use MooseX::Types::LoadableClass qw(LoadableClass);
use MooseX::Types::Moose qw(Bool Int Num Str);
use MooseX::NonMoose;
use Time::HiRes;

use aliased 'App::KADR::AniDB::Content::Anime';
use aliased 'App::KADR::AniDB::Content::File';
use aliased 'App::KADR::AniDB::Content::MylistSet';
use aliased 'App::KADR::AniDB::Content::MylistEntry';
use aliased 'App::KADR::AniDB::Role::Content::Referencer';

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

use constant FILE_FMASK => "7ff8fff8";
use constant FILE_AMASK => "0000fcc0";
use constant ANIME_MASK => "f0e0d8fd0000f8";

has 'is_banned',                 isa => Bool;
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

	$self->_parse_content(Anime, $res->{contents}[0]);
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

	$self->_parse_content(File, $res->{contents}[0]);
}

sub has_session {
	$_[0]->_session_key
	&& !$_[0]->is_banned
	&& (time - $_[0]->_last_query_time) < SESSION_TIMEOUT
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

	if ($res->{code} == 221) {
		$self->_parse_content(MylistEntry, $res->{contents}[0]);
	}
	elsif ($res->{code} == 312) {
		my $ml = $self->_parse_content(MylistSet, $res->{contents}[0]);

		# XXX: Make work with $params{aname} too.
		$ml->aid($params{aid}) if $params{aid};
		$ml;
	}
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
			$value = $self->_parse_content(MylistEntry, $res->{contents}[0]);
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

	my $mylist = $self->mylist(%params);

	# Not found
	return unless $mylist;
	
	return $mylist if $mylist->isa(MylistSet);

	# Mylist data for this anime consists of one episode.
	# File and anime info is needed to emulate the expected output.
	my $anime = $self->anime(aid => $mylist->aid);
	my $epno  = $self->file(fid => $mylist->fid)->episode_number;
	my $state = $mylist->state;

	MylistSet->new(
		aid => $mylist->aid,
		anime_title => $anime->romaji_name,
		episodes => $anime->episode_count,
		eps_with_state_unknown => ($state == $mylist->STATE_UNKNOWN ? $epno : ''),
		eps_with_state_on_hdd => ($state == $mylist->STATE_HDD ? $epno : ''),
		eps_with_state_on_cd => ($state == $mylist->STATE_CD ? $epno : ''),
		eps_with_state_deleted => ($state == $mylist->STATE_DELETED ? $epno : ''),
		watched_eps => ($mylist->viewdate > 0 ? $epno : ''),
	);
}

sub mylist_anime_query {
	my($self, $query) = @_;
	$self->mylist_anime(%$query);
}

sub mylist_file {
	my ($self, %params) = @_;
	my $info = $self->mylist(%params);

	# Not found
	return unless $info;

	die 'Got multiple mylist entries response' unless $info->isa(MylistEntry);

	$info;
}

sub mylist_file_query {
	my ($self, $query) = @_;
	$self->mylist_file(%$query);
}

sub start {
	my ($self, $tx) = @_;

	die 'Banned' if $self->is_banned;

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

sub _parse_content {
	my ($self, $class, $str) = @_;
	my $c = $class->parse($str);
	$c->client($self) if $c->does(Referencer);
	$c;
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

		RECEIVE:
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
		if ($res->{code} == 555) {
			$self->is_banned(1);
			die 'Banned';
		}

		# Server busy
		if ($res->{code} == 602) {
			Time::HiRes::sleep $self->time_to_sleep_when_busy;
			$attempts = 0;
			next;
		}

		# Server-side timeout
		next if $res->{code} == 604;

		# Tag mismatch
		goto RECEIVE unless $res->{tag} && $res->{tag} eq $params->{tag};

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
