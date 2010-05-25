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
use DBI::SpeedySimple;
use Digest::ED2K;
use Encode;
use File::Copy;
use File::HomeDir;
use File::Find;
use Getopt::Long;
use PortIO;
use Readonly;

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
	dirs => {
		delete_empty_dirs_in_scanned => 1,
		to_put_unwatched_eps => undef,
		to_put_watched_eps => undef,
		to_scan => [],
		valid_for_unwatched_eps => [],
		valid_for_watched_eps => [],
	},
	load_local_cache_into_memory => 1,
	show_hashing_progress => 1, # Only disable if you think that printing the hashing progess is taking up a significant amount of CPU time when hashing a file.
	use_windows_compatible_filenames => 0, # Off by default since not having to do this produces nicer filenames.
);
$conf->read("$appdir/config");

# Some variables for the printer
my $max_status_len = 1;
my $last_msg_len = 1;
my $last_msg_type = 0;

# A cache to speed up in_list calls.
my $in_list_cache = {};

my $db = DBI::SpeedySimple->new("dbi:SQLite:$appdir/db");

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

my @files;
my @ed2k_of_processed_files;
my $dirs_done = 1;
foreach(@{$conf->{dirs}->{to_scan}}) {
	next if !-e $_;
	printer($_, "Scanning", 0, $dirs_done++, scalar(@{$conf->{dirs}->{to_scan}}));
	@files = (@files, sort(recurse($_)));
}

my $fcount = scalar(@files);
my $file;
while ($file = shift @files) {
	next if $file =~ /\.part$/;
	if (my $ed2k = process_file($file, $a)) {
		push(@ed2k_of_processed_files, $ed2k);
	}
}

if($conf->{anidb}->{update_records_for_deleted_files}) {
	my @dead_files = sort { $::a->[2] cmp $::b->[2] } @{$db->{dbh}->selectall_arrayref("SELECT ed2k, size, filename FROM known_files WHERE ed2k NOT IN (" . join(',', map { "'$_'" } @ed2k_of_processed_files) . ");")};
	my($count, $dead_files_len) = (1, scalar(@dead_files) + 1);
	while($file = shift @dead_files) {
		printer($$file[2], "Cleaning", 0, $count, $dead_files_len);
		my $mylistinfo = $a->mylist_file_by_ed2k_size(@$file);
		if ( defined($mylistinfo) ) {
			if ($mylistinfo->{state} == 1) {
				printer($$file[2], "Removed", 1, $count, $dead_files_len);
				$a->mylistedit({lid => $mylistinfo->{lid}, state => 3});
			} else {
				printer($$file[2], "Cleaned", 1, $count, $dead_files_len);
			}
			$db->remove("anidb_mylist_file", {lid => $mylistinfo->{lid}});
		} else {
			printer($$file[2], "Not Found", 1, $count, $dead_files_len);
		}
		$db->remove("known_files", {ed2k => $$file[0]});
		$count++;
	}
}

cleanup();

if($conf->{dirs}->{delete_empty_dirs_in_scanned}) {
	for(@{$conf->{dirs}->{to_scan}}) {
		finddepth({wanted => sub{rmdir}, follow => 1}, $_) if -e;
	}
}

sub recurse {
	my(@paths) = @_;
	my @files;
	for my $path (@paths) {
		opendir IMD, $path;
		for(readdir IMD) {
			if(!($_ eq '.' or $_ eq '..')) {
				$_ = "$path/$_";
				if(-d $_) {
					push @paths, $_;
				} else {
					push @files, decode_utf8($_);
				}
			}
		}
		close IMD;
	}
	return @files;
}

sub process_file {
	my($file, $a) = @_;
	return if(not -e $file);
	printer($file, "Processing", 0);

	my $ed2k = ed2k_hash($file);
	my $fileinfo = $a->file_query({ed2k => $ed2k, size => -s $file});

	if(!defined $fileinfo) {
		printer($file, "Ignored", 1);
		return $ed2k;
	}
	
	# Auto-add to mylist.
	my $mylistinfo = $a->mylist_file_by_fid($fileinfo->{fid});
	if(!defined $mylistinfo) {
		printer($file, "Adding", 0);
		if (my $lid = $a->mylistadd($fileinfo->{fid})) {
			$db->update("adbcache_file", {lid => $lid}, {fid => $fileinfo->{fid}});
			printer($file, "Added", 1);
		} else {
			printer($file, "Failed", 1);
		}
	} elsif ($mylistinfo->{state} != 1) {
		printer($file, "Updating", 0);
		if($a->mylistedit({lid => $fileinfo->{lid}, state => 1})) {
			$db->update("anidb_mylist_file", {state => 1}, {fid => $mylistinfo->{fid}});
			printer($file, "Updated", 1);
		} else {
			printer($file, "Failed", 1);
		}
	}
	
	my $mylistanimeinfo = $a->mylist_anime_by_aid($fileinfo->{aid});
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

	if(defined $mylistanimeinfo and $mylistanimeinfo->{eps_with_state_on_hdd} !~ /^[a-z]*\d+$/i and !($fileinfo->{episode_number} eq $mylistanimeinfo->{eps_with_state_on_hdd}) and not ($file_output_dir eq $conf->{dirs}->{to_put_watched_eps} and $fileinfo->{episode_number} eq $mylistanimeinfo->{watched_eps}) and not ($file_output_dir eq $conf->{dirs}->{to_put_unwatched_eps} and count_list($mylistanimeinfo->{eps_with_state_on_hdd}) - count_list($mylistanimeinfo->{watched_eps}) == 1)) {
		my $anime_dir = $fileinfo->{anime_romaji_name};
		$anime_dir =~ s/\//∕/g;
		$file_output_dir .= "/$anime_dir";
		mkdir($file_output_dir) if !-e $file_output_dir;
	}
	
	my $file_version = $a->file_version($fileinfo);
	my $newname = $fileinfo->{anime_romaji_name} . ($fileinfo->{episode_english_name} =~ /^(Complete Movie|ova|special|tv special)$/i ? '' : " - " . $fileinfo->{episode_number} . ($file_version > 1 ? "v$file_version" : "") . " - " . $fileinfo->{episode_english_name}) . ((not $fileinfo->{group_short_name} eq "raw") ? " [" . $fileinfo->{group_short_name} . "]" : "") . "." . $fileinfo->{file_type};
	
	$newname = $fileinfo->{anime_romaji_name} . " - " . $fileinfo->{episode_number} . " - Episode " . $fileinfo->{episode_number} . ((not $fileinfo->{group_short_name} eq "raw") ? " [" . $fileinfo->{group_short_name} . "]" : "") . "." . $fileinfo->{file_type} if length($newname) > 250;
	
	$newname =~ s/\//∕/g;
	
	unless($file eq "$file_output_dir/$newname") {
		if(-e "$file_output_dir/$newname") {
			print "\n";
			printer("$file_output_dir/$newname", 'Rename target already exists', 1);
		} else {
			printer($file, "File", 1);
			if(!$dont_move) {
				printer("$file_output_dir/$newname", "Moving to", 0);
				$db->update("known_files", {filename => $newname}, {ed2k => $ed2k, size => -s $file});
				move($file, "$file_output_dir/$newname");
				printer("$file_output_dir/$newname", "Moved to", 1);
			} else {
				printer("$file_output_dir/$newname", "Would have moved to", 1);
			}
			
		}
	}
	
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
	my($file, $ed2k, $size) = @_;
	printer($file, "Avdumping", 0);
	(my $esc_file = $file) =~ s/(["`])/\\\$1/g;
	system "$conf->{avdump} -as -tout:20:6555 \"$esc_file\" > /dev/null";
	$db->update("known_files", {avdumped => 1}, {ed2k => $ed2k, size => $size});
	printer($file, "Avdumped", 1);
}

sub ed2k_hash {
	my($file) = @_;
	my $file_sn = substr($file, rindex($file, '/') + 1, length($file));
	my $size = -s $file;

	if(my $r = $db->fetch('known_files', ['ed2k', 'avdumped'], {filename => $file_sn, size => $size}, 1)) {
		avdump($file, $r->{ed2k}, $size) if $conf->{avdump} and !$r->{avdumped};
		return $r->{ed2k};
	}

	my $ctx = Digest::ED2K->new;
	my $fh = file_open('<:mmap:raw', $file);
	if($conf->{show_hashing_progress}) {
		my $buffer;
		my $bytes_done;
		while(my $bytes_read = read $fh, $buffer, Digest::ED2K::CHUNK_SIZE) {
			$ctx->add($buffer);
			$bytes_done += $bytes_read;
			printer($file, sprintf('Hashing %.01f%%', ($bytes_done / $size) * 100), 0);
		}
	}
	else {
		printer($file, 'Hashing', 0);
		$ctx->addfile($fh);
	}
	close $fh;
	my $ed2k = $ctx->hexdigest;
	printer($file, 'Hashed', 1);

	if($db->exists('known_files', {ed2k => $ed2k, size => $size})) {
		$db->update('known_files', {filename => $file_sn}, {ed2k => $ed2k, size => $size});
	}
	else {
		$db->insert('known_files', {filename => $file_sn, size => $size, ed2k => $ed2k});
		avdump($file, $ed2k, $size) if $conf->{avdump};
	}
	return $ed2k;
}

sub printer {
	my($file, $status, $type, $progress, $total) = @_;
	my $status_len = length($status);
	$max_status_len = $status_len if $status_len > $max_status_len;
	my $msg = "[" . (defined $progress ? $progress : ($fcount - scalar(@files))) . "/" . (defined $total ? $total : $fcount) . "][$status]" . (" " x ($max_status_len - $status_len + 1)) . $file;
	STDOUT->printflush(($last_msg_type ? "\n" : ("\r" . (length($msg) < $last_msg_len ? (' ' x $last_msg_len) . "\r" : ''))) . $msg);
	$last_msg_len = length($msg);
	$last_msg_type = $type;
}

# Determines if the specified number is in a AniDB style list of episode numbers.
# Example: in_List(2, "1-3") == true
sub in_list {
	my($needle, $haystack) = @_;
	#print "\nneedle: $needle\t haystack: $haystack\n";
	if($needle =~ /^(\w+)-(\w+)$/) {
		return in_list($1, $haystack);
		# This is commented out to work around a bug in the AniDB UDP API.
		# For multi-episode files, the API only includes the first number in the lists that come in MYLIST commands.
		#for ($first..$last) {
		#	return 0 if !in_list($_, $haystack);
		#}
		#return 1;
	}
	
	$needle =~ s/^(\w*?)[0]*(\d+)$/$1$2/;
	#print "ineedle: $needle\t haystack: $haystack\n";
	cache_list($haystack);
	return(defined $in_list_cache->{$haystack}->{$needle} ? 1 : 0);
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
				$in_list_cache->{$list}->{$_} = 1;
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
	STDOUT->printflush("\r" . ' ' x $last_msg_len . "\r");
	if(defined $a) {
		say 'Logging out.';
		$a->logout();
	}
	$db->{dbh}->disconnect();
	$conf->write;
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
	
	$query->{fmask} = FILE_FMASK;
	$query->{amask} = FILE_AMASK;
	
	my($code, $data) = split("\n", $self->_sendrecv("FILE", $query));
	
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
	# Due to the current design, if me need to get this record from AniDB, it's a new file, so we should update the mylist_anime record at the same time. Deleting the old record will atuomatically force it to fetch if from the server again.
	my $fileinfo = $self->file_query({fid => $fid});
	$self->{db}->remove("anidb_mylist_anime", {aid => $fileinfo->{aid}});
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
	(my $msg = $self->_sendrecv("MYLIST", $query)) =~ s/.*\n//im;
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
	my $msg = $self->_sendrecv("MYLIST", $query);
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
		my $msg = $self->_sendrecv("AUTH", {user => lc($self->{username}), pass => $self->{password}, protover => 3, client => CLIENT_NAME, clientver => CLIENT_VER, nat => 1, enc => "UTF8", comp => 1});
		if(defined $msg && $msg =~ /20[01]\ ([a-zA-Z0-9]*)\ ([0-9\.\:]).*/) {
			$self->{skey} = $1;
			$self->{myaddr} = $2;
		} else {
			die "Login Failed: $msg\n";
		}
	}
	return 1;
}

sub logout {
	my($self) = @_;
	if($self->{skey} && (time - $self->{last_command}) > (35 * 60)) {
		$self->_sendrecv("LOGOUT");
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
		inflate \$data => \$recvmsg or return;
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
	$self->logout;
}