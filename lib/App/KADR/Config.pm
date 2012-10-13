package App::KADR::Config;
use Class::Load qw(load_optional_class);
use File::HomeDir;
use List::MoreUtils qw(all);
use Moose;
use Moose::Util::TypeConstraints;

use App::KADR::Path 'dir';

with qw(MooseX::Getopt MooseX::SimpleConfig);

my $appdir = dir(File::HomeDir->my_home)->subdir('.kadr');

subtype 'Collator', as 'CodeRef';
coerce 'Collator', from 'Str', via {
	if ($_ eq 'auto') {
		$_ = load_optional_class('Unicode::Collate') ? 'unicode' : 'ascii';
	}

	return sub { ref $_[0] eq 'CODE' ? @_[1..$#_] : @_ }
		if $_ eq 'none';

	if ($_ eq 'ascii') {
		return sub {
			return sort { lc($a) cmp lc($b) } @_
				unless ref $_[0] eq 'CODE';

			my $keygen = shift;
			map { $_->[1] }
				sort { $a->[0] cmp $b->[0] }
				map { [lc $keygen->($_), $_] }
				@_;
		};
	}

	if ($_ eq 'unicode') {
		require Unicode::Collate;
		my $collator = Unicode::Collate->new(level => 1, normalize => undef);
		return sub {
			return $collator->sort(@_)
				unless ref $_[0] eq 'CODE';

			my $keygen = shift;
			map { $_->[1] }
				sort { $a->[0] cmp $b->[0] }
				map { [$collator->getSortKey($keygen->($_)), $_] }
				@_;
		};
	}
};
MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
	'Collator' => '=s'
);

subtype 'ExistingDir' => as class_type('App::KADR::Path::Dir') => where { -d $_ };
coerce 'ExistingDir' => from 'Str' => via { dir($_)->absolute };

subtype 'ExistingDirs', as 'ArrayRef[ExistingDir]' => where { all { -d $_ } @$_ };
coerce 'ExistingDirs', from 'ArrayRef', via { [map { dir($_)->absolute } @$_] };

my @default_config_files
	= map { $_->stringify } grep { $_->is_file_exists }
		$appdir->file('config.yml'), $appdir->file('login.yml');

has '+configfile',
	default => sub{ [@default_config_files] },
	documentation => 'Default: ~/.kadr/config.yml';

has 'avdump' => (is => 'rw', isa => 'Str', predicate => 'has_avdump', documentation => "Commandline to run avdump.");
has 'avdump_timeout' => (is => 'rw', isa => 'Int', default => 30, documentation => "How many seconds to wait for avdump to contact AniDB before retrying.");
has [qw(anidb_username anidb_password)] => (is => 'rw', isa => 'Str', required => 1);
has 'cache_timeout_mylist_unwatched' => (is => 'rw', isa => 'Int', required => 1, default => 2*60*60);
has [qw(cache_timeout_file cache_timeout_mylist_watched)] => (is => 'rw', isa => 'Int', required => 1, default => 12*24*60*60);

has 'collator',
	coerce => 1,
	default => 'auto',
	is => 'rw',
	isa => 'Collator';

has 'database',
	default => 'dbi:SQLite:' . $appdir->file('db'),
	is => 'rw',
	isa => 'Str',
	required => 1;

has 'delete_empty_dirs_in_scanned' => (is => 'rw', isa => 'Str', required => 1, default => 1);

has [qw(dir_to_put_unwatched_eps dir_to_put_watched_eps)],
	coerce => 1,
	is => 'rw',
	isa => 'ExistingDir',
	required => 1;

has [qw(dirs_to_scan valid_dirs_for_unwatched_eps valid_dirs_for_watched_eps)],
	coerce => 1,
	is => 'rw',
	isa => 'ExistingDirs',
	required => 1;

has 'expire_cache',
	default => 1,
	documentation => "DEBUG OPTION. Negate to prevent deleting old cached records.",
	is => 'rw',
	isa => 'Bool';

has 'file_naming_scheme',
	default => <<'EOF',
: if not $only_episode_in_folder {
<: $anime_romaji_name :>/
: }
<: $anime_romaji_name :>
: if $is_primary_episode {
:   if $file_version > 1 { print ' v' ~ $file_version }
: }
: else {
 - <: $episode_number :>
:   if $file_version > 1 { print 'v' ~ $file_version }
 - <: $episode_english_name :>
: }
: if $group_short_name != 'raw' { print ' [' ~ $group_short_name ~ ']' }
.<: $file_type :>
EOF
	is => 'rw',
	isa => 'Str',
	required => 1;

has 'load_local_cache_into_memory' => (is => 'rw', isa => 'Bool', default => 1, documentation => "Disable to reduce memory usage when doing a longer run. About 15 times faster when kadr doesn't have to talk to anidb.");

has 'query_attempts',
	default => -1,
	documentation => 'Number of times to retry a query after a timeout. Default: Unlimited',
	is => 'rw',
	isa => 'Int';

has 'query_timeout',
	default => 15.0,
	documentation => 'Minimum time to wait for a response to a query. Default: 15.0 seconds',
	is => 'rw',
	isa => 'Num';

has 'test',
	default => 0,
	documentation => 'Test mode, make no changes.',
	is => 'rw',
	isa => 'Bool';

has 'time_to_sleep_when_busy' => (is => 'rw', isa => 'Int', required => 1, default => 10*60, documentation => "How long (in seconds) to sleep if AniDB informs us it's too busy to talk to us.");
has 'update_anidb_records_for_deleted_files' => (is => 'rw', isa => 'Bool', required => 1, default => 0);
has 'windows_compatible_filenames' => (is => 'rw', isa => 'Bool', required => 1, default => 0, documentation => 'Default: false. Set to true to make Windows not shit bricks.');

__PACKAGE__->meta->make_immutable;
1;
