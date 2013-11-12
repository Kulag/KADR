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
has 'max_attempts',              isa => Int,       predicate => 1, clearer => 1;
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

method login($user = $self->username, $pass = $self->password) {
	return $self if $self->has_session;

	my $tx = $self->build_tx('AUTH', {
		client => CLIENT_NAME,
		clientver => CLIENT_VER,
		comp => 1,
		enc => 'UTF8',
		nat => 1,
		pass => $pass,
		protover => 3,
		user => $user,
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
			$type = 'multiple_files';
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

sub mylist_edit {
	shift->mylist_add(edit => 1, @_);
}

sub mylist_file {
	my ($self, %params) = @_;
	my $info = $self->mylist(%params);

	# Not found
	return unless $info;

	die 'Got multiple mylist entries response' unless $info->isa(MylistEntry);

	$info;
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
	if (!($self->has_session || $command eq 'AUTH') && $self->username) {
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

=head1 SYNOPSIS

	use App::KADR::AniDB::UDP::Client;
	my $client = App::KADR::AniDB::UDP::Client->new;

	# Enable opportunistic login
	$client->username('user')->password('pass');

	# Manual login
	$client->login('user', 'pass');
	$client->logout;

	# Get the name of an anime (logs in automatically)
	say $client->anime(aid => 1)->romaji_name;

	# Get the size of a file
	say $client->file(fid => 1)->size;

	# Check if a file is in mylist
	say $client->mylist(fid => 1) ? "In mylist" : "Not in mylist";

=head1 DESCRIPTION

L<App::KADR::AniDB::UDP::Client> is a client with partial support for AniDB's
UDP API.
Caching support has been split out into
L<App::KADR::AniDB::UDP::Client::Caching>. The split was made under the
assumption that a client without caching would be feasible and useful, and is
likely to be merged back.

Most queries require login. L<App::KADR::AniDB::UDP::Client> will perform a
login when a query requiring login is made and the username attribute is set.

Many queries have many different sets of parameters that can be used. Method
examples with arguments like %anime_spec are explained in the C<SPECIFICATIONS>
section below.

=head1 ATTRIBUTES

=head2 C<is_banned>

	my $bool = $client->is_banned;

Check if the client has received a temporary IP ban.

=head2 C<max_attempts>

	my $max = $client->max_attempts;
	$client = $client->max_attempts(5);
	my $set = $client->has_max_attempts;
	$client->clear_max_attempts;

Number of times to retry timed out queries before dying. Will keep retrying
queries indefinitely if undefined.

=head2 C<port>

	my $port = $client->port;
	$client  = $client->port(9000);

Local UDP port to use. Defaults to 9000.

=head2 C<password>

	my $password = $client->password;
	$client      = $client->password('password');

Password to use for opportunistic login.

=head2 C<timeout>

	my $timeout = $client->timeout;
	$client     = $client->timeout(15.0);

Minimum amount of time in seconds to wait for a reply to a query. Defaults to
15.0.

=head2 C<time_to_sleep_when_busy>

	my $time = $client->time_to_sleep_when_busy;
	$client  = $client->time_to_sleep_when_busy(900);

Time in seconds to sleep when the server informs the client it's too busy to
process queries at this time. Defaults to 15 minutes.

=head2 C<tx_class>

	my $class = $client->tx_class;
	$client   = $client->tx_class('App::KADR::AniDB::UDP::Transaction');

Transaction class to use. Defaults to L<App::KADR::AniDB::UDP::Transaction>

=head2 C<username>

Username to use for opportunistic login.

=head1 EVENTS

=head2 C<start>

	$client->on(start => sub {
		my ($client, $tx) = @_;
		...
	});

Emitted when a new transaction is about to start.

=head1 METHODS

=head2 C<anime>

	my $anime = $client->anime(%anime_spec);

Get anime information.
WARNING: Currently, using C<aname> with the caching subclass will crash.

=head2 C<build_tx>

	my $tx = $client->build_tx('ANIME', { aid => 1, amask => ANIME_MASK });

Generate a new transaction object.

=head2 C<file>

	my $file = $client->file(%file_spec);

Get file information.
WARNING: Currently, using C<aname> or C<gname> with the caching subclass will crash.

=head2 C<has_session>

	my $bool = $client->has_session;

Check if the client has an active session with the server.

=head2 C<login>

	$client = $client->login; # username and password attributes must be set
	$client = $client->login('username', 'password');

Log in to the server unless there is an active session. Required by AniDB for
most queries. Will be done automatically when needed if the username attribute
has been set.

=head2 C<logout>

Log out from the server if there is an active session. Done automatically when
the client object is destroyed.

=head2 C<mylist>

	my $mylist_entry = $client->mylist(%mylist_file_spec);
	my $mylist_entry = $client->mylist(%mylist_set_spec); # Only one match
	my $mylist_set   = $client->mylist(%mylist_set_spec);

Get information about a mylist entry or a set of entries. This may be removed
or have its functionality replaced with that of mylist_file soon due to the
unpredictability of the return value.

=head2 C<mylist_add>

	# Mylist attributes are all optional.
	# You should set state => MylistEntry->ON_HDD when adding a file from HDD.
	my %mylist_attrs = (
		edit => 0,
		state => 1,
		viewed => 0,
		viewdate => 0, # unix epoch, ignored unless viewed is set
		source => '', # custom user string
		storage => '', # custom user string
		other => '', # custom user string
	);

	my ($type, $value) = $client->mylist_add(%mylist_spec, %mylist_attrs);
	my $value = $client->mylist_add(%mylist_spec, %mylist_attrs);

	# While this is valid, if the anime has more than one episode, this will
	# fail, and return multiple_files instead of adding.
	my ($type, $value) = $client->mylist_add(%anime_spec, %mylist_attrs);
	my $value = $client->mylist_add(%anime_spec, %mylist_attrs);

	# epno can be set to a negative value, meaning all episodes up to the epno.
	# generic => 1 may be set instead of a group spec.
	my ($type, $value) = $client->mylist_add(%episodes_spec, %mylist_attrs);
	my $value = $client->mylist_add(%episodes_spec, %mylist_attrs);

Add one or more files to the mylist, or edit one mylist entry. The edit
parameter is likely to become an error soon.

The return values are likely to become objects at some point in the future,
at which point the type will be dropped.

=head3 C<return values by type>

=head4 C<edited>

Number of entries edited.

=head4 C<added>

lid of added entry.

=head4 C<added_count>

Number of entries added.

=head4 C<existing_entry>

The MylistEntry object for the existing entry.

=head4 C<multiple_files>

An arrayref of C<fids>.

=head2 C<mylist_anime>

	my $mylist = $client->mylist_anime(%mylist_set_spec);

Get information about a set of mylist entries. This may be renamed to
C<mylist_set> soon.

In order to get mylist entries for each item in the set you will need to use
the (not yet supported) multiple file query since differentiating information
like the file version is missing from the mylist set data.

=head2 C<mylist_edit>

	my $count = $client->mylist_edit(...);
	# Shortcut for $client->mylist_add(edit => 1, ...);

Edit one or more mylist entries. See C<mylist_add> for parameters.

=head2 C<mylist_file>

	my $mylist = $client->mylist_file(%mylist_spec);

Get information about a mylist entry. This may be renamed to C<mylist> or
C<mylist_entry> soon.

=head2 C<start>

	$tx = $client->start($tx);

Perform a query.

=head1 SPECIFICATIONS

=head2 C<anime>

	(aid => 1)
	(aname => "seikai no monshou")

=head2 C<episode>

	(%anime_spec, epno => 1)
	(%anime_spec, epno => EpisodeNumber->parse(1))

=head2 C<episodes>

	(%episode_spec)
	(%anime_spec, epno => '1-2')
	(%anime_spec, epno => EpisodeNumber->parse('1-2'))

=head2 C<file>

	(fid => 1)
	(ed2k => 'a62c68d5961e4c601fcf73624b003e9e', size => 169_142_272)
	(%anime_spec, %group_spec, epno => 1)

=head2 C<group>

	(gid => 1)
	(gname => 'Animehaven')

=head2 C<mylist_entry>

	(lid => 1)
	(%file_spec)

=head2 C<mylist_set>

	# Nothing but aid is currently supported.
	(%anime_spec)
	(%episodes_spec)
	(%mylist_spec)

=head1 SEE ALSO

L<App::KADR::AniDB::UDP::Client::Caching>
L<http://wiki.anidb.info/w/UDP_API_Definition>
