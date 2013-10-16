package App::KADR::AniDB::UDP::Client::Caching;
# ABSTRACT: Caching layer atop the AniDB UDP Client

use App::KADR::Moose;
use Carp qw(croak);
use List::AllUtils qw(first min);
use Method::Signatures;

use aliased 'App::KADR::AniDB::Content::Anime';
use aliased 'App::KADR::AniDB::Content::File';
use aliased 'App::KADR::AniDB::Content::MylistSet';
use aliased 'App::KADR::AniDB::Content::MylistEntry';
use aliased 'App::KADR::AniDB::EpisodeNumber';
use aliased 'App::KADR::AniDB::Role::Content::Referencer';

extends 'App::KADR::AniDB::UDP::Client';

use constant SCHEMA_ANIME => q{
CREATE TABLE IF NOT EXISTS anidb_anime (
	`aid` INTEGER PRIMARY KEY,
	`dateflags` INT,
	`year` VARCHAR(10),
	`type` VARCHAR(20),
	`romaji_name` TEXT,
	`kanji_name` TEXT,
	`english_name` TEXT,
	`episode_count` INT,
	`highest_episode_number` INT,
	`air_date` INT,
	`end_date` INT,
	`rating` VARCHAR(4),
	`vote_count` INT,
	`temp_rating` VARCHAR(4),
	`temp_vote_count` INT,
	`review_rating` VARCHAR(4),
	`review_count` INT,
	`is_r18` INT,
	`special_episode_count` INT,
	`credits_episode_count` INT,
	`other_episode_count` INT,
	`trailer_episode_count` INT,
	`parody_episode_count` INT,
	`updated` INT)
};

use constant SCHEMA_FILE => q{
CREATE TABLE IF NOT EXISTS adbcache_file (
	`fid` INTEGER PRIMARY KEY,
	`aid` INT,
	`eid` INT,
	`gid` INT,
	`lid` INT,
	`other_episodes` TEXT,
	`is_deprecated` INT,
	`status` INT,
	`size` INT,
	`ed2k` TEXT,
	`md5` TEXT,
	`sha1` TEXT,
	`crc32` TEXT,
	`quality` TEXT,
	`source` TEXT,
	`audio_codec` TEXT,
	`audio_bitrate` INT,
	`video_codec` TEXT,
	`video_bitrate` INT,
	`video_resolution` TEXT,
	`file_type` TEXT,
	`dub_language` TEXT,
	`sub_language` TEXT,
	`length` INT,
	`description` TEXT,
	`air_date` INT,
	`episode_number` TEXT,
	`episode_english_name` TEXT,
	`episode_romaji_name` TEXT,
	`episode_kanji_name` TEXT,
	`episode_rating` TEXT,
	`episode_vote_count` TEXT,
	`group_name` TEXT,
	`group_short_name` TEXT,
	`updated` INT)
};

use constant SCHEMA_MYLIST => q{
CREATE TABLE IF NOT EXISTS anidb_mylist_file (
	`lid` INT,
	`fid` INTEGER PRIMARY KEY,
	`eid` INT,
	`aid` INT,
	`gid` INT,
	`date` INT,
	`state` INT,
	`viewdate` INT,
	`storage` TEXT,
	`source` TEXT,
	`other` TEXT,
	`filestate` TEXT,
	`updated` INT)
};

use constant SCHEMA_MYLIST_ANIME => q{
CREATE TABLE IF NOT EXISTS anidb_mylist_anime (
	`aid` INTEGER PRIMARY KEY,
	`anime_title` TEXT,
	`episodes` INT,
	`eps_with_state_unknown` TEXT,
	`eps_with_state_on_hdd` TEXT,
	`eps_with_state_on_cd` TEXT,
	`eps_with_state_deleted` TEXT,
	`watched_eps` TEXT,
	`updated` INT)
};

my %TYPE_CLASSES = (
	anime        => Anime,
	file         => File,
	mylist_anime => MylistSet,
	mylist_file  => MylistEntry,
);

has 'cache_ignore_max_age', is => 'ro', isa => 'Bool';
has 'cache_max_ages', is => 'ro', isa => 'HashRef', default => sub { {} };
has 'db', is => 'ro', isa => 'App::KADR::DBI', required => 1;

for my $type (qw(anime file mylist_anime)) {
	__PACKAGE__->meta->add_method(
		$type => method(@_) {
			my $opts = ref $_[-1] eq 'HASH' ? pop : {};

			# Cached
			if (my $obj = $self->cached($type, @_, $opts)) {
				return $obj;
			}
			return if $opts->{no_update};

			# Update
			return unless my $obj = $self->${ \"SUPER::$type" }(@_);

			# Cache
			$self->db->remove($TYPE_CLASSES{$type}, {@_});
			$self->db->insert($TYPE_CLASSES{$type}, $obj);

			$obj;
		});
}

method BUILD(@_) {
	my $db  = $self->db;
	my $dbh = $db->{dbh};

	$dbh->do(SCHEMA_ANIME)        or die 'Error initializing anime table';
	$dbh->do(SCHEMA_FILE)         or die 'Error initializing file';
	$dbh->do(SCHEMA_MYLIST)       or die 'Error initializing mylist_file';
	$dbh->do(SCHEMA_MYLIST_ANIME) or die 'Error initializing mylist_anime';

	unless ($self->cache_ignore_max_age) {
		for my $type (keys %TYPE_CLASSES) {
			my $class  = $TYPE_CLASSES{$type};
			my $oldest = time - $self->max_age_for($class);

			$dbh->do("DELETE FROM $db->{rclass_map}{$TYPE_CLASSES{$type}} WHERE updated < $oldest");
		}
	}
}

method cached(@_) {
	my $opts = ref $_[-1] eq 'HASH' ? pop : {};
	my ($type, %params) = @_;

	# Cached
	my $type_class = $TYPE_CLASSES{$type} or croak "Invalid type: $type";
	return unless my $obj = $self->db->fetch($type_class, ['*'], \%params, 1);

	# Expiry
	my $max_age = $self->max_age_for($obj, $opts->{max_age});
	return if $obj->updated < time - $max_age && !$self->cache_ignore_max_age;

	$obj->client($self) if $obj->does(Referencer) && !$obj->has_client;
	$obj;
}

sub get_cached_lid {
	my ($self, %params) = @_;
	return unless exists $params{fid} || exists $params{ed2k};

	if (my $file = $self->db->fetch(File, ['*'], \%params, 1)) {
		return $file->lid;
	}
	();
}

method max_age_for($obj, $override?) {
	if ($obj->max_age_is_dynamic) {
		if (my $defaults = $self->cache_max_ages->{ ref $obj || $obj }) {
			if (defined $override) {
				if (ref $override eq 'HASH') {
					return $obj->max_age({ %$defaults, %$override });
				}
				return $obj->max_age($override);
			}
			return $obj->max_age($defaults);
		}
		return $obj->max_age($override);
	}

	$self->{max_age_for}{ ref $obj || $obj }{$override}
		//= $obj->max_age($override
			// $self->cache_max_ages->{ ref $obj || $obj });
}

sub mylist_add {
	my ($self, %params) = @_;
	my ($type, $info) = $self->SUPER::mylist_add(%params);

	if ($type eq 'added') {
		my $db = $self->db;
		my %fparams = map { $params{$_} ? ($_, $params{$_}) : () } qw(fid ed2k size);
		if (my $file = $db->fetch(File, ['*'], \%fparams, 1)) {
			$db->update(File, { lid => $info }, \%fparams);
		}
	}

	wantarray ? ($type, $info) : $info;
}

method mylist_file(@_) {
	my $opts   = ref $_[-1] eq 'HASH' ? pop : {};
	my %params = @_;

	if (my $lid = $self->get_cached_lid(%params)) {
		%params = (lid => $lid);
	}

	# Cached
	my $key = $params{lid} ? 'lid' : $params{fid} ? 'fid' : undef;
	if ($key) {
		if (my $mylist = $self->cached('mylist_file', $key => $params{$key}, $opts)) {
			return $mylist;
		}
	}
	return if $opts->{no_update};

	# Update
	return unless my $ml = $self->SUPER::mylist_file(%params);

	# Cache
	$self->db->remove(MylistEntry, { lid => $ml->lid });
	$self->db->insert(MylistEntry, $ml);

	$ml;
}

=head1 SYNOPSIS

	use aliased 'App::KADR::AniDB::UDP::Client::Caching', 'Client';

	my $db = App::KADR::DBI->new("dbd:SQLite:dbname=foo");
	my $client = Client->new(db => $db);

	# Transparently cached
	my $anime = $client->anime(aid => 1);

	# Try to get a lid from fid/ed2k/size
	my $lid = $client->get_cached_lid(fid => 1);

=head1 DESCRIPTION

L<App::KADR::AniDB::UDP::Client::Caching> is a transparent caching layer around
L<App::KADR:AniDB::UDP::Client>.

=head1 ATTRIBUTES

L<App::KADR::AniDB::UDP::Client::Caching> inherits all attributes from
L<App::KADR:AniDB::UDP::Client> and implements the following new ones.

=head2 C<db>

	my $db = $client->db;

A L<App::KADR::DBI> instance. Required at creation.

=head1 METHODS

L<App::KADR::AniDB::UDP::Client::Caching> inherits all methods from
L<App::KADR:AniDB::UDP::Client> and implements the following new ones.

=head2 C<get_cached_lid>

	my $lid = $client->get_cached_lid(%file_spec);
	my $lid = $client->get_cached_lid(
		ed2k => 'a62c68d5961e4c601fcf73624b003e9e',
		size => 169_142_272,
	);

	# Always returns nothing.
	my $lid = $client->get_cached_lid(aid => 1, epno => 1, gid => 1);

Get a cached lid given a file specification. Undef does not mean no mylist
entry exists for the file, just that none is cached.

=head1 SEE ALSO

L<App::KADR::AniDB::UDP::Client>
