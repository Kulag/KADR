package App::KADR::Config;
use Class::Load qw(load_optional_class);
use File::HomeDir;
use List::MoreUtils qw(all);
use Moose;
use Moose::Util::TypeConstraints;
use Path::Class;
use Parse::TitleSyntax;
use Parse::TitleSyntax::Functions::Regexp;

with qw(MooseX::Getopt MooseX::SimpleConfig);

my $appdir = dir(File::HomeDir->my_home)->subdir('.kadr');

subtype 'Collator', as 'CodeRef';
coerce 'Collator', from 'Str', via {
	if ($_ eq 'auto') {
		$_ = load_optional_class('Unicode::Collate') ? 'unicode-i' : 'ascii-i';
	}

	return sub { $_[0] } if $_ eq 'none';
	return sub { [ sort @{ $_[0] } ] } if $_ eq 'ascii';
	return sub { [ sort { lc($a) cmp lc($b) } @{ $_[0] } ] } if $_ eq 'ascii-i';
	if ($_ eq 'unicode-i') {
		require Unicode::Collate;
		my $collator = Unicode::Collate->new(level => 1, normalize => undef);
		return sub { [ $collator->sort(@{ $_[0] }) ] };
	}
};
MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
	'Collator' => '=s'
);

subtype 'ExistingDir' => as class_type('Path::Class::Dir') => where { -d $_ };
coerce 'ExistingDir' => from 'Str' => via { dir($_) };

subtype 'ExistingDirs', as 'ArrayRef[ExistingDir]' => where { all { -d $_ } @$_ };
coerce 'ExistingDirs', from 'ArrayRef', via { [map { dir($_) } @$_] };

class_type('Parse::TitleSyntax');
coerce 'Parse::TitleSyntax' => from 'Str' => via {
	my $parsets = Parse::TitleSyntax->new($_);
	$parsets->AddFunctions(Parse::TitleSyntax::Functions::Regexp->new($parsets));
	return $parsets;
};

has '+configfile',
	default => $appdir->file('config.yml').'',
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
	coerce => 1,
	default => <<'EOF',
$if(%only_episode_in_folder%,,%anime_romaji_name%/)%anime_romaji_name%
$if($rematch(%episode_english_name%,'^(Complete Movie|OVA|Special|TV Special)$'),,
 - %episode_number%$ifgreater(%file_version%,1,v%file_version%,) - %episode_english_name%)
$if($not($strcmp(%group_short_name%,raw)), '['%group_short_name%']').%file_type%
EOF
	is => 'rw',
	isa => 'Parse::TitleSyntax',
	required => 1;

has 'load_local_cache_into_memory' => (is => 'rw', isa => 'Bool', default => 1, documentation => "Disable to reduce memory usage when doing a longer run. About 15 times faster when kadr doesn't have to talk to anidb.");

has 'query_attempts',
	default => 5,
	documentation => 'Number of times to retry a query after a timeout. Default: 5',
	is => 'rw',
	isa => 'Int';

has 'query_timeout',
	default => 15.0,
	documentation => 'Time to wait for a response to a query. Default: 15.0 seconds',
	is => 'rw',
	isa => 'Num';

has 'show_hashing_progress' => (is => 'rw', isa => 'Bool', default => 1, documentation => "Only disable if you think that printing the hashing progess is taking up a significant amount of CPU time when hashing a file.");

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
