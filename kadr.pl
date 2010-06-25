#!/usr/bin/perl
# Copyright (c) 2009, Kulag <g.kulag@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# KADR was forked from ADBREN v4 Copyright (c) 2008, clip9 <clip9str@gmail.com>

use v5.10;
use common::sense;
use Config::YAML;
use Data::Types qw(:int);
use DBI::SpeedySimple;
use Digest::ED2K;
use Encode;
use Expect;
use File::Copy;
use File::Basename;
use File::HomeDir;
use File::Find;
use Getopt::Long;
use PortIO;
use Parse::TitleSyntax;
use Parse::TitleSyntax::Functions::Regexp;
use Readonly;
use Term::StatusLine::Freeform;
use Term::StatusLine::XofX;

$|++;
$SIG{INT} = "cleanup";
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

# Some debug options
Readonly my $appdir => $ENV{KADR_DIR} // File::HomeDir->my_home . '/.kadr';
Readonly my $dont_move => 0; # Does everything short of moving/renaming the files when true.
Readonly my $dont_expire_cache => 0; # Leaves expired cache entries untouched.

if(!is_file("$appdir/config")) {
	if(!is_dir($appdir)) {
		mkpath($appdir);
	}
	close(file_open('>', "$appdir/config"));
}
my $conf = Config::YAML->new(
	config => "$appdir/config",
	output => "$appdir/config",
	anidb => {
		cache_timeout => {
			mylist_unwatched => 7200,
			mylist_watched => 1036800,
			file => 1036800,
		},
		password => undef,
		time_to_sleep_when_busy => 10*60, # How long (in seconds) to sleep if AniDB informs us it's too busy to talk to us.
		update_records_for_deleted_files => 1,
		username => undef,
	},
	avdump => undef, # Commandline to run avdump.
	avdump_timeout => 30, # How many seconds to wait for avdump to contact AniDB before retrying.
	dirs => {
		delete_empty_dirs_in_scanned => 1,
		to_put_unwatched_eps => undef,
		to_put_watched_eps => undef,
		to_scan => [],
		valid_for_unwatched_eps => [],
		valid_for_watched_eps => [],
	},
	file_naming_scheme => <<'EOF',
$if(%only_episode_in_folder%,,%anime_romaji_name%/)%anime_romaji_name%
$if($rematch(%episode_english_name%,'^(Complete Movie|ova|special|tv special)$'),,
 - %episode_number%$ifgreater(%file_version%,1,v%file_version%,) - %episode_english_name%)
$if($not($strcmp(%group_short_name%,raw)), '['%group_short_name%']').%file_type%
EOF
	load_local_cache_into_memory => 1,
	show_hashing_progress => 1, # Only disable if you think that printing the hashing progess is taking up a significant amount of CPU time when hashing a file.
	use_windows_compatible_filenames => 0, # Off by default since not having to do this produces nicer filenames.
);
$conf->read("$appdir/config");
$conf->write;

my $parsets = Parse::TitleSyntax->new($conf->{file_naming_scheme});
$parsets->AddFunctions(Parse::TitleSyntax::Functions::Regexp->new($parsets));

# A cache to speed up in_list calls.
my $in_list_cache = {};

my $db = DBI::SpeedySimple->new("dbi:SQLite:$appdir/db");
$db->{dbh}->do(q{CREATE TABLE IF NOT EXISTS known_files (`filename` TEXT, `size` INT, `ed2k` TEXT PRIMARY KEY, `avdumped` INT);}) and
$db->{dbh}->do(q{CREATE TABLE IF NOT EXISTS anidb_mylist_file (`lid` INT, `fid` INTEGER PRIMARY KEY, `eid` INT, `aid` INT, `gid` INT,
				 `date` INT, `state` INT, `viewdate` INT, `storage` TEXT, `source` TEXT, `other` TEXT, `filestate` TEXT, `updated` INT);}) and
$db->{dbh}->do(q{CREATE TABLE IF NOT EXISTS anidb_mylist_anime (`aid` INTEGER PRIMARY KEY, `anime_title` TEXT, `episodes` INT,
				 `eps_with_state_unknown` TEXT, `eps_with_state_on_hdd` TEXT, `eps_with_state_on_cd` TEXT, `eps_with_state_deleted` TEXT,
				 `watched_eps` TEXT, `updated` INT);}) and
$db->{dbh}->do(q{CREATE TABLE IF NOT EXISTS adbcache_file (`fid` INTEGER PRIMARY KEY, `aid` INT, `eid` INT, `gid` INT, `lid` INT,
				 `other_episodes` TEXT, `is_deprecated` INT, `status` INT, `size` INT, `ed2k` TEXT, `md5` TEXT, `sha1` TEXT, `crc32` TEXT,
				 `quality` TEXT, `source` TEXT, `audio_codec` TEXT, `audio_bitrate` INT, `video_codec` TEXT, `video_bitrate` INT, `video_resolution` TEXT,
				 `file_type` TEXT, `dub_language` TEXT, `sub_language` TEXT, `length` INT, `description` TEXT, `air_date` INT,
				 `anime_total_episodes` INT, `anime_highest_episode_number` INT, `anime_year` INT, `anime_type` INT, `anime_related_aids` TEXT,
				 `anime_related_aid_types` TEXT, `anime_categories` TEXT, `anime_romaji_name` TEXT, `anime_kanji_name` TEXT, `anime_english_name` TEXT,
				 `anime_other_name` TEXT, `anime_short_names` TEXT, `anime_synonyms` TEXT, `episode_number` TEXT, `episode_english_name` TEXT,
				 `episode_romaji_name` TEXT, `episode_kanji_name` TEXT, `episode_rating` TEXT, `episode_vote_count` TEXT, `group_name` TEXT,
				 `group_short_name` TEXT, `updated` INT)}) or die "Could not initialize the database";

unless($dont_expire_cache) {
	my $timeout = $conf->{anidb}->{cache_timeout};
	$db->{dbh}->do("DELETE FROM adbcache_file WHERE updated < " . (time - $timeout->{file}));
	$db->{dbh}->do("DELETE FROM anidb_mylist_anime WHERE updated < " . (time - $timeout->{mylist_unwatched}) . " AND watched_eps = eps_with_state_on_hdd");
	$db->{dbh}->do("DELETE FROM anidb_mylist_anime WHERE updated < " . (time - $timeout->{mylist_watched}) . " AND watched_eps != eps_with_state_on_hdd");
}

if($conf->{load_local_cache_into_memory}) {
	$db->cache([
		{table => 'known_files', indices => ['filename', 'size']},
		{table => 'adbcache_file', indices => ['ed2k', 'size']},
		{table => 'anidb_mylist_file', indices => ['fid']},
		{table => 'anidb_mylist_anime', indices => ['aid']},
	]);
}

my $a = AniDB::UDPClient->new({
	username => $conf->{anidb}->{username},
	password => $conf->{anidb}->{password},
	db => $db,
	port => 3700,
});

my @files = sort(find_files(@{$conf->{dirs}->{to_scan}}));
my @ed2k_of_processed_files;
my $sl = Term::StatusLine::XofX->new(total_item_count => scalar(@files));
for(@files) {
	$sl->update('++', $_);
	next if !valid_file($_);
	if(my $ed2k = process_file($_)) {
		push @ed2k_of_processed_files, $ed2k;
	}
}
$sl->finalize;

if($conf->{anidb}->{update_records_for_deleted_files}) {
	my @missing_files = @{$db->{dbh}->selectall_arrayref('SELECT ed2k, size, filename FROM known_files WHERE ed2k NOT IN (' . join(',', map { "'$_'" } @ed2k_of_processed_files) . ') ORDER BY filename')};
	$sl = Term::StatusLine::XofX->new(label => 'Missing File', total_item_count => scalar(@missing_files));
	for my $file (@missing_files) {
		$sl->update('++', $$file[2]);
		my $file_status = Term::StatusLine::Freeform->new(parent => $sl, value => 'Checking AniDB record');
		my $mylistinfo = $a->mylist_file_by_ed2k_size(@$file);
		if(defined($mylistinfo)) {
			if($mylistinfo->{state} == 1) {
				$file_status->update('Setting AniDB status to "deleted".');
				$a->mylistedit({lid => $mylistinfo->{lid}, state => 3});
				$file_status->update('Set AniDB status to "deleted".');
			}
			else {
				$file_status->update('AniDB Mylist status already set.');
			}
			$db->remove('anidb_mylist_file', {lid => $mylistinfo->{lid}});
		}
		else {
			$file_status->update('No AniDB Mylist record found.');
		}
		$db->remove('known_files', {ed2k => $$file[0]});
	}
	$sl->finalize;
}

cleanup();

sub valid_file {
	return if /\.part$/;
	return if !is_file($_);
	return 1;
}

sub find_files {
	my(@paths) = @_;
	my(@dirs, @files);
	for(@paths) {
		if(!is_dir($_)) {
			if(is_file($_)) {
				push @files, $_;
			}
			else {
				say "Warning: Not a directory: $_";
			}
		}
		else {
			push @dirs, $_;
		}
	}
	my $sl = Term::StatusLine::XofX->new(label => 'Scanning Directory', total_item_count => sub { scalar(@dirs) });
	for my $dir (@dirs) {
		$sl->update('++', $dir);
		opendir(my $dh, $dir);
		for(readdir($dh)) {
			if(!($_ eq '.' or $_ eq '..')) {
				$_ = "$dir/$_";
				if(is_dir($_)) {
					push @dirs, $_;
				}
				else {
					push @files, decode_utf8($_);
				}
			}
		}
		close($dh);
	}
	$sl->finalize;
	return @files;
}

sub process_file {
	my $file = shift;
	my $ed2k = ed2k_hash($file);
	my $fileinfo = $a->file_query({ed2k => $ed2k, size => -s $file});
	my $proc_sl = Term::StatusLine::Freeform->new(parent => $sl);

	if(!defined $fileinfo) {
		$proc_sl->finalize_and_log('Ignored');
		return $ed2k;
	}

	# Auto-add to mylist.
	my $mylistinfo = $a->mylist_file_by_fid($fileinfo->{fid});
	if(!defined $mylistinfo) {
		$proc_sl->update('Adding to AniDB Mylist');
		if(my $lid = $a->mylistadd($fileinfo->{fid})) {
			$db->remove('anidb_mylist_anime', {aid => $fileinfo->{aid}}); # Force an update of this record, it's out of date.
			$db->update('adbcache_file', {lid => $lid}, {fid => $fileinfo->{fid}});
			$proc_sl->finalize_and_log('Added to AniDB Mylist');
		}
		else {
			$proc_sl->finalize_and_log('Error adding to AniDB Mylist');
		}
	}
	elsif($mylistinfo->{state} != 1) { # State 1 == on disk.
		$proc_sl->update('Setting AniDB Mylist state to "On HDD"');
		if($a->mylistedit({lid => $fileinfo->{lid}, state => 1})) {
			$db->update('anidb_mylist_file', {state => 1}, {fid => $mylistinfo->{fid}});
			$proc_sl->finalize_and_log('Set AniDB Mylist state to "On HDD"');
		}
		else {
			$proc_sl->finalize_and_log('Error setting AniDB Mylist state to "On HDD"');
		}
	}

	my $mylistanimeinfo = $a->mylist_anime_by_aid($fileinfo->{aid});
	if(!in_list($fileinfo->{episode_number}, $mylistanimeinfo->{eps_with_state_on_hdd})) {
		# Our mylistanime record is old. Can happen if the file was not added by kadr.
		$db->remove('anidb_mylist_anime', {aid => $fileinfo->{aid}});
		$mylistanimeinfo = $a->mylist_anime_by_aid($fileinfo->{aid});
	}

	my $dir = array_find(substr($file, 0, rindex($file, '/')), @{$conf->{dirs}->{to_scan}});
	my $file_output_dir = $dir;
	if(in_list($fileinfo->{episode_number}, $mylistanimeinfo->{watched_eps})) {
		if(!($dir ~~ @{$conf->{dirs}->{valid_for_watched_eps}})) {
			$file_output_dir = $conf->{dirs}->{to_put_watched_eps};
		}
	}
	else {
		if(!($dir ~~ @{$conf->{dirs}->{valid_for_unwatched_eps}})) {
			$file_output_dir = $conf->{dirs}->{to_put_unwatched_eps};
		}
	}

	for(keys %$fileinfo) {
		$fileinfo->{$_} =~ s/\//∕/g;
		$fileinfo->{$_} =~ s/\`/'/g;
	}

	# Check if this is the only episode going into the folder.
	if(
		defined $mylistanimeinfo
		# This is the only episode from this anime on HDD.
		&& $mylistanimeinfo->{eps_with_state_on_hdd} =~ /^[a-z]*\d+$/i
		# And this is it.
		&& $fileinfo->{episode_number} eq $mylistanimeinfo->{eps_with_state_on_hdd}
		&& (
			# This episode is the only watched episode from this anime.
			($file_output_dir eq $conf->{dirs}->{to_put_watched_eps} && $fileinfo->{episode_number} eq $mylistanimeinfo->{watched_eps})
			# Or this episode is the only unwatched episode from this anime.
			|| ($file_output_dir eq $conf->{dirs}->{to_put_unwatched_eps} && count_list($mylistanimeinfo->{eps_with_state_on_hdd}) - count_list($mylistanimeinfo->{watched_eps}) == 1)
		)
	) {
		$fileinfo->{only_episode_in_folder} = 1;
	}
	$fileinfo->{file_version} = $a->file_version($fileinfo);

	my($newname, $file_output_dir) = fileparse("$file_output_dir/" . $parsets->Run($fileinfo));
	$file_output_dir =~ s!/$!!;
	mkpath($file_output_dir) if !is_dir($file_output_dir);

	unless($file eq "$file_output_dir/$newname") {
		if(file_exists("$file_output_dir/$newname")) {
			$proc_sl->finalize_and_log("Tried to rename to existing file: $file_output_dir/$newname");
		}
		else {
			if($dont_move) {
				$proc_sl->finalize_and_log("Would have moved to $file_output_dir/$newname");
			}
			else {
				$proc_sl->update("Moving to $file_output_dir/$newname");
				my $size = -s $file;
				if(move($file, "$file_output_dir/$newname")) {
					$db->update('known_files', {filename => $newname}, {ed2k => $ed2k, size => $size});
					$proc_sl->finalize_and_log("Moved to $file_output_dir/$newname");
				}
				else {
					$proc_sl->finalize_and_log("Error moving to $file_output_dir/$newname");
					exit 2;
				}
			}
		}
	}

	$proc_sl->finalize;
	return $fileinfo->{ed2k};
}

sub array_find {
	my($key, @haystack) = @_;
	foreach my $straw (@haystack) {
		return $straw if index($key, $straw) > -1;
	}
	return;
}

sub avdump {
	my($file, $size, $ed2k) = @_;
	my($aved2k, $timedout);
	my $avsl = Term::StatusLine::XofX->new(parent => $sl, label => 'AvHashing', format => 'percent', total_item_count => 100);
	(my $esc_file = $file) =~ s/(["`])/\\\$1/g;
	my $exp = Expect->new("$conf->{avdump} -vas -tout:20:6555 \"$esc_file\" 2>&1");
	$exp->log_stdout(0);
	$exp->expect($conf->{avdump_timeout},
		[qr/H\s+(\d+).(\d{2})/, sub {
			my @m = @{shift->matchlist};
			$avsl->update(int(int($m[0]) + int($m[1]) / 100));
			exp_continue;
		}],
		[qr/P\s+(\d+).(\d{2})/, sub {
			my @m = @{shift->matchlist};
			if($avsl->label eq 'AvHashing') {
				$avsl->label('AvParsing');
			}
			$avsl->update(int(int($m[0]) + int($m[1]) / 100));
			exp_continue;
		}],
		[qr/ed2k: ([0-9a-f]{32})/, sub {
			my @m = @{shift->matchlist};
			$aved2k = $m[0];
			exp_continue;
		}],
		timeout => sub { $timedout = 1; }
	);
	if($timedout) {
		$avsl->finalize;
		return avdump($file, $size, $ed2k);
	}
	if(!$aved2k) {
		$avsl->log('Error avdumping.');
		exit 2;
	}
	$avsl->finalize_and_log('Avdumped');
	if($ed2k) {
		 $db->update('known_files', {avdumped => 1}, {ed2k => $ed2k, size => $size});
	}
	else {
		my $file_sn = substr($file, rindex($file, '/') + 1, length($file));
		$db->set('known_files', {avdumped => 1, ed2k => $aved2k, filename => $file_sn, size => $size}, {filename => $file_sn, size => $size});
		return $aved2k;
	}
}

sub ed2k_hash {
	my($file) = @_;
	my $file_sn = substr($file, rindex($file, '/') + 1, length($file));
	my $size = -s $file;

	if(my $r = $db->fetch('known_files', ['ed2k', 'avdumped'], {filename => $file_sn, size => $size}, 1)) {
		avdump($file, $size, $r->{ed2k}) if $conf->{avdump} and !$r->{avdumped};
		return $r->{ed2k};
	}

	if($conf->{avdump}) {
		return avdump($file, $size);
	}

	my $ctx = Digest::ED2K->new;
	my $fh = file_open('<:mmap:raw', $file);
	my $ed2k_sl;
	if($conf->{show_hashing_progress}) {
		$ed2k_sl = Term::StatusLine::XofX->new(parent => $sl, label => 'Hashing', total_item_count => $size);
		while(my $bytes_read = read $fh, my $buffer, Digest::ED2K::CHUNK_SIZE) {
			$ctx->add($buffer);
			$ed2k_sl->update("+=$bytes_read");
		}
	}
	else {
		$ed2k_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Hashing');
		$ctx->addfile($fh);
	}
	close $fh;
	my $ed2k = $ctx->hexdigest;
	$db->set('known_files', {avdumped => 1, ed2k => $ed2k, filename => $file, size => $size}, {filename => $file, size => $size});
	$ed2k_sl->finalize_and_log('Hashed');
	return $ed2k;
}

# Determines if the specified number is in a AniDB style list of episode numbers.
# Example: in_List(2, "1-3") == true
sub in_list {
	my($needle, $haystack) = @_;
	cache_list($haystack);
	if($needle =~ /^(\w+)-(\w+)$/) {
		return in_list($1, $haystack);
		# This is commented out to work around a bug in the AniDB UDP API.
		# For multi-episode files, the API only includes the first number in the lists that come in MYLIST commands.
		#for ($first..$last) {
		#	return 0 if !in_list($_, $haystack);
		#}
		#return 1;
	}
	return defined $in_list_cache->{$haystack}->{(is_int($needle) ? int($needle) : $needle)};
}

sub count_list {
	my ($list) = @_;
	cache_list($list);
	return scalar(keys(%{$in_list_cache->{$list}}));
}

sub cache_list {
	my($list) = @_;
	if(!defined $in_list_cache->{$list}) {
		for(split /,/, $list) {
			if($_ =~ /^(\w+)-(\w+)$/) {
				for my $a (range($1, $2)) {
					$in_list_cache->{$list}->{$a} = 1;
				}
			} else {
				$in_list_cache->{$list}->{(is_int($_) ? int($_) : $_)} = 1;
			}
		}
	}
}

sub range {
	my($start, $end) = @_;
	$start =~ s/^([a-xA-Z]*)(\d+)$/$2/;
	my $tag = $1;
	$end =~ s/^([a-xA-Z]*)(\d+)$/$2/;
	map { "$tag$_" } $start .. $end;
}

sub cleanup {
	if(defined $a) {
		$a->logout();
	}
	if($conf->{dirs}->{delete_empty_dirs_in_scanned}) {
		print "Deleting empty folders in those scanned... ";
		for(@{$conf->{dirs}->{to_scan}}) {
			finddepth({wanted => sub{rmdir}, follow => 1}, $_) if -e;
		}
		say "done.";
	}
	$db->{dbh}->disconnect();
	exit;
}

package AniDB::UDPClient;
use strict;
use warnings;
use Time::HiRes;
use IO::Socket;
use IO::Uncompress::Inflate qw(inflate $InflateError);
use Encode;

use constant CLIENT_NAME => "kadr";
use constant CLIENT_VER => 1;

# Threshhold values are specified in packets.
use constant SHORT_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD => 5;
use constant LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD => 100;

use constant FILE_STATUS_CRCOK  => 0x01;
use constant FILE_STATUS_CRCERR => 0x02;
use constant FILE_STATUS_ISV2   => 0x04;
use constant FILE_STATUS_ISV3   => 0x08;
use constant FILE_STATUS_ISV4   => 0x10;
use constant FILE_STATUS_ISV5   => 0x20;
use constant FILE_STATUS_UNC    => 0x40;
use constant FILE_STATUS_CEN    => 0x80;

use constant FILE_FMASK => "7ff8fff8";
use constant FILE_AMASK => "fefcfcc0";

use constant CODE_220_ENUM => 
qw/fid
   aid eid gid lid other_episodes is_deprecated status
   size ed2k md5 sha1 crc32
   quality source audio_codec audio_bitrate video_codec video_bitrate video_resolution file_type
   dub_language sub_language length description air_date
   anime_total_episodes anime_highest_episode_number anime_year anime_type anime_related_aids anime_related_aid_types anime_categories
   anime_romaji_name anime_kanji_name anime_english_name anime_other_name anime_short_names anime_synonyms
   episode_number episode_english_name episode_romaji_name episode_kanji_name episode_rating episode_vote_count
   group_name group_short_name/;

use constant MYLIST_FILE_ENUM => qw/lid fid eid aid gid date state viewdate storage source other filestate/;

use constant MYLIST_ANIME_ENUM => qw/anime_title episodes eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd eps_with_state_deleted watched_eps/;

sub new {
	my($package, $opts) = @_;
	my $self = bless $opts, $package;
	$self->{username} or die 'AniDB error: Need a username';
	$self->{password} or die 'AniDB error: Need a password';
	$self->{starttime} = time - 1;
	$self->{queries} = 0;
	$self->{last_command} = 0;
	$self->{handle} = IO::Socket::INET->new(Proto => 'udp', LocalPort => $self->{port}) or die($!);
	my $host = gethostbyname('api.anidb.info') or die($!);
	$self->{sockaddr} = sockaddr_in(9000, $host) or die($!);
	return $self;
}

sub file_query {
	my($self, $query) = @_;

	if(my $r = $self->{db}->fetch("adbcache_file", ["*"], $query, 1)) {
		return $r;
	}

	my $file_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Updating file information');

	$query->{fmask} = FILE_FMASK;
	$query->{amask} = FILE_AMASK;

	my $recvmsg = $self->_sendrecv("FILE", $query);
	return unless defined $recvmsg;
	my($code, $data) = split("\n", $recvmsg);
	$file_sl->finalize;
	
	$code = int((split(" ", $code))[0]);
	if($code == 220) { # Success
		my %fileinfo;
		my @fields = split /\|/, $data;
		map { $fileinfo{(CODE_220_ENUM)[$_]} = $fields[$_] } 0 .. scalar(CODE_220_ENUM) - 1;
		
		$fileinfo{updated} = time;
		$self->{db}->set('adbcache_file', \%fileinfo, {fid => $fileinfo{fid}});
		return \%fileinfo;
	} elsif($code == 322) { # Multiple files found.
		die "Error: \"322 MULITPLE FILES FOUND\" not supported.";
	} elsif($code == 320) { # No such file.
		return;
	} else {
		die "Error: Unexpected return code for file query recieved. Got $code.\n";
	}
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

sub mylistadd {
	my $res = shift->mylist_add_query({state => 1, fid => shift});
	return $res;
}

sub mylistedit {
	my ($self, $params) = @_;
	$params->{edit} = 1;
	return $self->mylist_add_query($params);
}

sub mylist_add_query {
	my ($self, $params) = @_;
	my $res;

	if ((!defined $params->{edit}) or $params->{edit} == 0) {
		# Add

		$res = $self->_sendrecv("MYLISTADD", $params);

		if ($res =~ /^210 MYLIST/) { # OK
			return (split(/\n/, $res))[1];
		} elsif ($res !~ /^310/) { # any errors other than 310
			return 0;
		}
		# If 310 ("FILE ALREADY IN MYLIST"), retry with edit=1
		$params->{edit} = 1;
	}
	# Edit

	$res = $self->_sendrecv("MYLISTADD", $params);

	if ($res =~ /^311/) { # OK
		return (split(/\n/, $res))[1];
	}
	return 0; # everything else
}

sub mylist_file_by_fid {
	my($self, $fid) = @_;
	my $mylistinfo = $self->{db}->fetch("anidb_mylist_file", ["*"], {fid => $fid}, 1);
	return $mylistinfo if defined $mylistinfo;
	return $self->_mylist_file_query({fid => $fid});;
}

sub mylist_file_by_lid {
	my($self, $lid) = @_;

	my $mylistinfo = $self->{db}->fetch("anidb_mylist_file", ["*"], {lid => $lid}, 1);
	return $mylistinfo if defined $mylistinfo;
	return $self->_mylist_file_query({lid => $lid});
}

sub mylist_file_by_ed2k_size {
	my ($self, $ed2k, $size) = @_;

	my $fileinfo = $self->{db}->fetch("adbcache_file", ["*"], {size => $size, ed2k => $ed2k}, 1);
	if(defined($fileinfo)) {
		return if !$fileinfo->{lid};
		
		$self->{db}->remove("anidb_mylist_file", {lid => $fileinfo->{lid}});
		return $self->mylist_file_by_lid($fileinfo->{lid});
	}
	return $self->_mylist_file_query({size => $size, ed2k => $ed2k});
}

sub _mylist_file_query {
	my($self, $query) = @_;
	my $mylist_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Updating mylist information');
	(my $msg = $self->_sendrecv("MYLIST", $query)) =~ s/.*\n//im;
	$mylist_sl->finalize;
	my @f = split /\|/, $msg;
	if(scalar @f) {
		my %mylistinfo;
		map { $mylistinfo{(MYLIST_FILE_ENUM)[$_]} = $f[$_] } 0 .. $#f;
		$mylistinfo{updated} = time;
		$self->{db}->set('anidb_mylist_file', \%mylistinfo, {lid => $mylistinfo{lid}});
		return \%mylistinfo;
	}
	undef;
}

sub mylist_anime_by_aid {
	my($self, $aid) = @_;
	my $mylistanimeinfo = $self->{db}->fetch("anidb_mylist_anime", ["*"], {aid => $aid}, 1);
	return $mylistanimeinfo if defined $mylistanimeinfo;
	return $self->_mylist_anime_query({aid => $aid});
}

sub _mylist_anime_query {
	my($self, $query) = @_;
	my $mylist_anime_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Updating mylist anime information');
	my $msg = $self->_sendrecv("MYLIST", $query);
	$mylist_anime_sl->finalize;
	my $single_episode = ($msg =~ /^221/);
	my $success = ($msg =~ /^312/);
	return if not ($success or $single_episode);
	$msg =~ s/.*\n//im;
	my @f = split /\|/, $msg;
	
	if(scalar @f) {
		my %mylistanimeinfo;
		$mylistanimeinfo{aid} = $query->{aid};
		if($single_episode) {
			my %mylistinfo;
			map { $mylistinfo{(MYLIST_FILE_ENUM)[$_]} = $f[$_] } 0 .. $#f;
			
			my $fileinfo = $self->file_query({fid => $mylistinfo{fid}});
			
			$mylistanimeinfo{anime_title} = $fileinfo->{anime_romaji_name};
			$mylistanimeinfo{episodes} = '';
			$mylistanimeinfo{eps_with_state_unknown} = "";
			
			if($fileinfo->{episode_number} =~ /^(\w*?)[0]*(\d+)$/) {
				$mylistanimeinfo{eps_with_state_on_hdd} = "$1$2";
				$mylistanimeinfo{watched_eps} = ($mylistinfo{viewdate} > 0 ? "$1$2" : "");
			} else {
				$mylistanimeinfo{eps_with_state_on_hdd} = $fileinfo->{episode_number};
				$mylistanimeinfo{watched_eps} = ($mylistinfo{viewdate} > 0 ? $fileinfo->{episode_number} : "");
			}
			$mylistanimeinfo{eps_with_state_on_cd} = "";
			$mylistanimeinfo{eps_with_state_deleted} = "";
		} else {
			map { $mylistanimeinfo{(MYLIST_ANIME_ENUM)[$_]} = $f[$_] } 0 .. scalar(MYLIST_ANIME_ENUM) - 1;
		}
		$mylistanimeinfo{updated} = time;
		$self->{db}->set('anidb_mylist_anime', \%mylistanimeinfo, {aid => $mylistanimeinfo{aid}});
		return \%mylistanimeinfo;
	}
	return;
}

sub login {
	my($self) = @_;
	if(!defined $self->{skey} || (time - $self->{last_command}) > (35 * 60)) {
		my $login_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Logging in to AniDB');
		my $msg = $self->_sendrecv("AUTH", {user => lc($self->{username}), pass => $self->{password}, protover => 3, client => CLIENT_NAME, clientver => CLIENT_VER, nat => 1, enc => "UTF8", comp => 1});
		if(defined $msg && $msg =~ /20[01]\ ([a-zA-Z0-9]*)\ ([0-9\.\:]).*/) {
			$self->{skey} = $1;
			$self->{myaddr} = $2;
		} else {
			die "Login Failed: $msg\n";
		}
		$login_sl->finalize;
	}
	return 1;
}

sub logout {
	my($self) = @_;
	if($self->{skey} && (time - $self->{last_command}) > (35 * 60)) {
		my $logout_sl = Term::StatusLine::Freeform->new(parent => $sl, value => 'Logging out of AniDB');
		$self->_sendrecv("LOGOUT");
		$logout_sl->finalize;
	}
	delete $self->{skey};
}

# Sends and reads the reply. Tries up to 10 times.
sub _sendrecv {
	my($self, $query, $vars) = @_;
	my $recvmsg;
	my $attempts = 0;
	
	$self->login if $query ne "AUTH" && (!defined $self->{skey} || (time - $self->{last_command}) > (35 * 60));

	$vars->{'s'} = $self->{skey} if $self->{skey};
	$vars->{'tag'} = "T" . $self->{queries};
	$query .= ' ' . join('&', map { "$_=$vars->{$_}" } keys %{$vars}) . "\n";
	$query = encode_utf8($query);

	while(!$recvmsg) {
		if($self->{queries} > LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) {
			while((my $waittime = (30 * ($self->{queries} - LONG_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) + $self->{starttime}) - Time::HiRes::time) > 0) {
				Time::HiRes::sleep($waittime);
			}
		}
		if($self->{queries} > SHORT_TERM_FLOODCONTROL_ENFORCEMENT_THRESHHOLD) {
			if($self->{last_command} + 2 > Time::HiRes::time) {
				Time::HiRes::sleep($self->{last_command} + 2 - Time::HiRes::time);
			}
		}
		
		$self->{last_command} = Time::HiRes::time;
		$self->{queries} += 1;
		
		send($self->{handle}, $query, 0, $self->{sockaddr}) or die( "Send error: " . $! );
		
		my $rin = '';
		my $rout;
		vec($rin, fileno($self->{handle}), 1) = 1;
		recv($self->{handle}, $recvmsg, 1500, 0) or die("Recv error:" . $!) if select($rout = $rin, undef, undef, 30.0);
		
		$attempts++;
		die "\nTimeout while waiting for reply.\n" if $attempts == 4;
        }

	# Check if the data is compressed.
	if(substr($recvmsg, 0, 2) eq "\x00\x00") {
		my $data = substr($recvmsg, 2);
		if(!inflate(\$data, \$recvmsg)) {
			warn "\nError inflating packet: $InflateError";
			return;
		}
	}
	
	$recvmsg = decode_utf8($recvmsg);
	
	if($recvmsg =~ /^555/) {
		print "\nBanned, exiting.";
		exit(1);
	}
	
	if($recvmsg =~ /^602/) {
		print "\nAniDB is too busy, will retry in $conf->{anidb}->{time_to_sleep_when_busy} seconds.";
		Time::HiRes::sleep($conf->{anidb}->{time_to_sleep_when_busy});
		return $self->_sendrecv($query, $vars);
	}
	
	# Check for a server error.
	if($recvmsg =~ /^6\d+.*$/ or $recvmsg =~ /^555/) {
		die("\nAnidb error:\n$recvmsg");
	}
	
	# Check that the answer we received matches the query we sent.
	$recvmsg =~ s/^(T\d+) (.*)/$2/;
	if(not defined($1) or $1 ne $vars->{tag}) {
		die("\nTag mismatch");
	}
	
	# Check if our session is invalid.
	if($recvmsg =~ /^501.*|^506.*/) {
		undef $self->{skey};
		$self->login();
		return $self->_sendrecv($query, $vars);
	}
	
	return $recvmsg;
}

sub DESTROY {
	my $self = shift;
	$self->logout;
}
