package App::KADR::AniDB::UDP::Client::Caching;
# ABSTRACT: Caching layer atop the AniDB UDP Client

use App::KADR::Moose;
use List::AllUtils qw(first);
use aliased 'App::KADR::AniDB::EpisodeNumber';

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

has 'db', is => 'ro', isa => 'App::KADR::DBI', required => 1;

sub anime {
	my ($self, %params) = @_;
	my $db = $self->db;

	# Cached
	if (my $anime = $db->fetch('anidb_anime', ['*'], \%params, 1)) {
		$anime->client($self);
		return $anime;
	}

	# Update
	return unless my $anime = $self->SUPER::anime(%params);

	# Temporary fix to make strings look nice because AniDB::UDP::Client doesn't understand types.
	$anime->{$_} =~ tr/`/'/ for keys %$anime;

	# Cache
	$db->set('anidb_anime', $anime, { aid => $anime->aid });

	$anime;
}

sub BUILD {
	my $self = shift;
	my $dbh  = $self->db->{dbh};

	$dbh->do(SCHEMA_ANIME)        or die 'Error initializing anime table';
	$dbh->do(SCHEMA_FILE)         or die 'Error initializing file';
	$dbh->do(SCHEMA_MYLIST)       or die 'Error initializing mylist_file';
	$dbh->do(SCHEMA_MYLIST_ANIME) or die 'Error initializing mylist_anime';
}

sub file {
	my ($self, %params) = @_;
	my $db = $self->db;

	# Cached
	if (my $file = $db->fetch("adbcache_file", ["*"], \%params, 1)) {
		$file->client($self);
		return $file;
	}

	# Update
	return unless my $file = $self->SUPER::file(%params);

	# Temporary fix to make strings look nice because AniDB::UDP::Client doesn't understand types.
	my %obj = (episode_number => 1, client => 1);
	$file->{$_} =~ tr/`/'/ for grep { !$obj{$_} } keys %$file;

	# Cache
	$db->set('adbcache_file', $file, { fid => $file->fid });

	$file;
}

sub get_cached_lid {
	my ($self, %params) = @_;
	return unless exists $params{fid} || exists $params{ed2k};

	if (my $file = $self->db->fetch('adbcache_file', ['*'], \%params, 1)) {
		return $file->lid;
	}
	();
}

sub mylist_add {
	my ($self, %params) = @_;
	my ($type, $info) = $self->SUPER::mylist_add(%params);

	if ($type eq 'added') {
		my $db = $self->db;
		my %fparams = map { $params{$_} ? ($_, $params{$_}) : () } qw(fid ed2k size);
		if (my $file = $db->fetch('adbcache_file', ['*'], \%fparams, 1)) {
			$db->update('adbcache_file', {lid => $info}, \%fparams);
		}
	}

	wantarray ? ($type, $info) : $info;
}

sub mylist_file {
	my ($self, %params) = @_;
	my $db = $self->db;

	if (my $lid = $self->get_cached_lid(%params)) {
		%params = (lid => $lid);
	}

	# Cached
	my $key = $params{lid} ? 'lid' : $params{fid} ? 'fid' : undef;
	if ($key and my $mylist = $db->fetch('anidb_mylist_file', ['*'], { $key => $params{$key} }, 1)) {
		$mylist->client($self);
		return $mylist;
	}

	# Update
	return unless my $mylist = $self->SUPER::mylist_file(%params);

	# Cache
	$db->set('anidb_mylist_file', $mylist, { lid => $mylist->lid });

	$mylist;
}

sub mylist_anime {
	my ($self, %params) = @_;
	my $db = $self->db;

	# Cached
	if (my $mylist = $db->fetch('anidb_mylist_anime', ['*'], \%params, 1)) {
		return $mylist;
	}

	# Update
	return unless my $mylist = $self->SUPER::mylist_anime(%params);

	# Temporary fix to make strings look nice because AniDB::UDP::Client doesn't understand types.
	$mylist->{anime_title} =~ tr/`/'/;

	# Cache
	$db->set('anidb_mylist_anime', $mylist, { aid => $mylist->aid });

	$mylist;
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
