package kadr::conf;
use Moose;
use Moose::Util::TypeConstraints;
use Readonly;
with qw(MooseX::Getopt MooseX::SimpleConfig);

Readonly my $appdir => File::HomeDir->my_home . '/.kadr';
subtype 'ExistingDir' => as 'Str' => where { -d $_ };

has '+configfile' => (default => "$appdir/config.yml", documentation => 'Default: ~/.kadr/config.yml');

has 'avdump' => (is => 'rw', isa => 'Str', predicate => 'has_avdump', documentation => "Commandline to run avdump.");
has 'avdump_timeout' => (is => 'rw', isa => 'Int', default => 30, documentation => "How many seconds to wait for avdump to contact AniDB before retrying.");
has [qw(anidb_username anidb_password)] => (is => 'rw', isa => 'Str', required => 1);
has 'cache_timeout_mylist_unwatched' => (is => 'rw', isa => 'Int', required => 1, default => 2*60*60);
has [qw(cache_timeout_file cache_timeout_mylist_watched)] => (is => 'rw', isa => 'Int', required => 1, default => 12*24*60*60);
has 'database' => (is => 'rw', isa => 'Str', required => 1, default => "dbi:SQLite:$appdir/db");
has 'delete_empty_dirs_in_scanned' => (is => 'rw', isa => 'Str', required => 1, default => 1);
has 'dont_move' => (is => 'rw', isa => 'Bool', required => 1, default => 0, documentation => "Doesn't move or rename files. Useful for testing new file_naming_scheme settings.");
has 'dont_expire_cache' => (is => 'rw', isa => 'Bool', required => 1, default => 0, documentation => "DEBUG OPTION. Doesn't delete old cached information.");
has [qw(dir_to_put_unwatched_eps dir_to_put_watched_eps)] => (is => 'rw', isa => 'ExistingDir', required => 1);
has [qw(dirs_to_scan valid_dirs_for_unwatched_eps valid_dirs_for_unwatched_eps)] => (is => 'rw', isa => 'ArrayRef[ExistingDir]', required => 1);
has 'file_naming_scheme' => (is => 'rw', isa => 'Str', required => 1, default => <<'EOF');
$if(%only_episode_in_folder%,,%anime_romaji_name%/)%anime_romaji_name%
$if($rematch(%episode_english_name%,'^(Complete Movie|OVA|Special|TV Special)$'),,
 - %episode_number%$ifgreater(%file_version%,1,v%file_version%,) - %episode_english_name%)
$if($not($strcmp(%group_short_name%,raw)), '['%group_short_name%']').%file_type%
EOF
has 'load_local_cache_into_memory' => (is => 'rw', isa => 'Bool', default => 1, documentation => "Disable to reduce memory usage when doing a longer run. About 15 times faster when kadr doesn't have to talk to anidb.");
has 'show_hashing_progress' => (is => 'rw', isa => 'Bool', default => 1, documentation => "Only disable if you think that printing the hashing progess is taking up a significant amount of CPU time when hashing a file.");
has 'time_to_sleep_when_busy' => (is => 'rw', isa => 'Int', required => 1, default => 10*60, documentation => "How long (in seconds) to sleep if AniDB informs us it's too busy to talk to us.");
has 'update_anidb_records_for_deleted_files' => (is => 'rw', isa => 'Bool', required => 1, default => 0);
has 'use_windows_compatible_filenames'  => (is => 'rw', isa => 'Bool', required => 1, default => 0, documentation => "Off by default since not having to do this produces nicer filenames.");

1;