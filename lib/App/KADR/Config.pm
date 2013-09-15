package App::KADR::Config;
# ABSTRACT: KADR configuration

use App::KADR::Collate ':all';
use App::KADR::Moose;
use App::KADR::Path 'dir';
use File::HomeDir;
use List::MoreUtils qw(all);
use Moose::Util::TypeConstraints;

with qw(MooseX::Getopt MooseX::SimpleConfig);

MooseX::Getopt::OptionTypeMap->add_option_type_to_map(Collate, '=s');

subtype 'ExistingDir' => as class_type('App::KADR::Path::Dir') => where { -d $_ };
coerce 'ExistingDir' => from 'Str' => via { dir($_)->absolute };

subtype 'ExistingDirs', as 'ArrayRef[ExistingDir]' => where { all { -d $_ } @$_ };
coerce 'ExistingDirs', from 'ArrayRef', via { [map { dir($_)->absolute } @$_] };

my $appdir   = dir(File::HomeDir->my_home)->subdir('.kadr');
my $database = 'dbi:SQLite:' . $appdir->file('db');

my @default_config_files
	= map { $_->stringify } grep { $_->is_file_exists }
		$appdir->file('config.yml'), $appdir->file('login.yml');
has '+configfile',
	default => sub{ [@default_config_files] },
	documentation => 'Default: ~/.kadr/config.yml';

has [qw(anidb_username anidb_password)], isa => 'Str', required => 1;

has 'cache_timeout_anime',            default => 12*24*60*60, isa => 'Int';
has 'cache_timeout_file',             default => 12*24*60*60, isa => 'Int';
has 'cache_timeout_mylist_unwatched', default =>    12*60*60, isa => 'Int';
has 'cache_timeout_mylist_watched',   default => 91*24*60*60, isa => 'Int';
has 'cache_timeout_mylist_watching',  default =>     2*60*60, isa => 'Int';
has 'collator',                       default => 'auto',      isa => Collate;
has 'database',                       default => $database,   isa => 'Str';
has 'delete_empty_dirs_in_scanned',   default => 1,           isa => 'Str';
has 'dirs_to_scan',                   isa => 'ExistingDirs',  required => 1;

has 'expire_cache',
	default => 1,
	documentation => "DEBUG OPTION. Negate to prevent deleting old cached records.",
	isa => 'Bool';

has 'file_naming_scheme',
	default => sub {
		shift->dirs_to_scan->[0] . <<'EOF'
/
<: $file.episode_watched ? 'watched' : $anime_mylist.watched_eps ? 'watching' : 'unwatched' :>/
: if not $file.is_primary_episode {
<: $anime.romaji_name :>/
: }
<: $anime.romaji_name :>
: if $file.is_primary_episode {
:   if $file.version > 1 { print ' v' ~ $file.version }
: }
: else {
 - <: $file.episode_number_padded :>
:   if $file.version > 1 { print 'v' ~ $file.version }
 - <: $file.episode_english_name :>
: }
: if $file.group_short_name != 'raw' { print ' [' ~ $file.group_short_name ~ ']' }
.<: $file.file_type :>
EOF
	},
	isa => 'Str',
	lazy => 1;

has 'hash_only',
	default => 0,
	documentation => q{Enable to skip processing of files and just hash them.},
	isa => 'Bool';

has 'load_local_cache_into_memory',
	default => 1,
	documentation => q{Disable to reduce memory usage when doing a longer run. About 15 times faster when kadr doesn't have to talk to anidb.},
	isa => 'Bool';

has 'query_attempts',
	default => -1,
	documentation => 'Number of times to retry a query after a timeout. Default: Unlimited',
	isa => 'Int';

has 'query_timeout',
	default => 15.0,
	documentation => 'Minimum time to wait for a response to a query. Default: 15.0 seconds',
	isa => 'Num';

has 'test',
	default => 0,
	documentation => 'Test mode, make no changes.',
	isa => 'Bool';

has 'time_to_sleep_when_busy',
	default => 10*60,
	documentation => q{How long (in seconds) to sleep if AniDB informs us it's too busy to talk to us.},
	isa => 'Int';

has 'update_anidb_records_for_deleted_files', default => 0, isa => 'Bool';

has 'windows_compatible_filenames',
	default => 0,
	documentation => 'Default: false. Set to true to make Windows not shit bricks.',
	isa => 'Bool';
