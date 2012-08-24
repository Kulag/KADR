#!/usr/bin/env perl
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

use v5.14;
use common::sense;
use open qw(:std :utf8);
use utf8;
use DBI::SpeedySimple;
use Digest::ED2K;
use Encode;
use Expect;
use File::Copy;
use File::Find;
use FindBin;
use List::AllUtils qw(first none reduce);
use Path::Class;
use Time::HiRes;

use lib "$FindBin::RealBin/lib";
use App::KADR::AniDB::UDP::Client;
use App::KADR::Config;
use App::KADR::Term::StatusLine::Freeform;
use App::KADR::Term::StatusLine::XofX;

sub TERM_SPEED() { $ENV{KADR_TERM_SPEED} // 0.05 }

sub shortest(@) { reduce { length($a) < length($b) ? $a : $b } @_ }

$SIG{INT} = \&cleanup;
STDOUT->autoflush(1);
STDOUT->binmode(':utf8');

my $conf = App::KADR::Config->new_with_options;

# A cache to speed up in_list calls.
my $in_list_cache = {};

my $db = DBI::SpeedySimple->new($conf->database);
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

if ($conf->expire_cache) {
	$db->{dbh}->do('DELETE FROM adbcache_file WHERE updated < ' . (time - $conf->cache_timeout_file));
	$db->{dbh}->do('DELETE FROM anidb_mylist_anime WHERE updated < ' . (time - $conf->cache_timeout_mylist_unwatched) . ' AND watched_eps != eps_with_state_on_hdd');
	$db->{dbh}->do('DELETE FROM anidb_mylist_anime WHERE updated < ' . (time - $conf->cache_timeout_mylist_watched) . ' AND watched_eps = eps_with_state_on_hdd');
}

if($conf->load_local_cache_into_memory) {
	$db->cache([
		{table => 'known_files', indices => ['filename', 'size']},
		{table => 'adbcache_file', indices => ['ed2k', 'size']},
		{table => 'anidb_mylist_file', indices => ['fid']},
		{table => 'anidb_mylist_anime', indices => ['aid']},
	]);
}

my $a = App::KADR::AniDB::UDP::Client->new({
	username => $conf->anidb_username,
	password => $conf->anidb_password,
	time_to_sleep_when_busy => $conf->time_to_sleep_when_busy,
	max_attempts => $conf->query_attempts,
	timeout => $conf->query_timeout,
});

my $files = find_files(@{$conf->dirs_to_scan});

print 'Sorting... ';
$files = $conf->collator->($files);
say 'done.';

my @ed2k_of_processed_files;
my $sl = App::KADR::Term::StatusLine::XofX->new(total_item_count => scalar @$files);
for my $file (@$files) {
	next unless -e $file;

	$sl->incr->update_label(shortest $file->relative, $file);

	push @ed2k_of_processed_files, my $ed2k = ed2k_hash($file);
	process_file($file, $ed2k);
}
$sl->finalize;

if(!$conf->test && $conf->update_anidb_records_for_deleted_files) {
	my @missing_files = @{$db->{dbh}->selectall_arrayref('SELECT ed2k, size, filename FROM known_files WHERE ed2k NOT IN (' . join(',', map { "'$_'" } @ed2k_of_processed_files) . ') ORDER BY filename')};
	$sl = App::KADR::Term::StatusLine::XofX->new(label => 'Missing File', total_item_count => scalar(@missing_files));
	for my $file (@missing_files) {
		$sl->update('++', $$file[2]);
		my $file_status = $sl->child('Freeform', value => 'Checking AniDB record');
		my $mylistinfo = mylist_file_by_ed2k_size(@$file);
		if(defined($mylistinfo)) {
			if($mylistinfo->{state} == $a->MYLIST_STATE_HDD) {
				$file_status->update('Setting AniDB status to "deleted".');
				$a->mylistedit({lid => $mylistinfo->{lid}, state => $a->MYLIST_STATE_DELETED});
				$file_status->finalize_and_log('Set AniDB status to "deleted".');
			}
			else {
				$file_status->finalize_and_log('AniDB Mylist status already set.');
			}
			$db->remove('anidb_mylist_file', {lid => $mylistinfo->{lid}});
		}
		else {
			$file_status->finalize_and_log('No AniDB Mylist record found.');
		}
		$db->remove('known_files', {ed2k => $$file[0]});
	}
}

if (!$conf->test && $conf->delete_empty_dirs_in_scanned) {
	print "Deleting empty folders in those scanned... ";
	for(@{$conf->dirs_to_scan}) {
		finddepth({wanted => sub{rmdir}, follow => 1}, $_);
	}
	say "done.";
}

cleanup();

sub valid_file {
	return if /\.part$/;
	return unless -f $_;
	1;
}

sub find_files {
	my @dirs = map { shortest $_, $_->relative } @_;
	my @files;

	my $sl = App::KADR::Term::StatusLine::XofX->new(label => 'Scanning Directory', total_item_count => sub { scalar(@dirs) });
	for my $dir (@dirs) {
		$sl->incr;
		$sl->update_label(decode_utf8 $dir) if $sl->last_update + TERM_SPEED < Time::HiRes::time;

		for ($dir->children) {
			if ($_->is_dir) { push @dirs, $_ }
			else {
				$_ = file(decode_utf8 $_);
				push @files, $_ if valid_file
			}
		}
	}

	$sl->log(sprintf 'Found %d files in %d directories.', scalar @files, scalar @dirs);

	\@files;
}

sub process_file {
	my ($file, $ed2k) = @_;
	my $file_size = -s $file;
	my $fileinfo = file_query(ed2k => $ed2k, size => $file_size);

	# File not in AniDB.
	return $sl->child('Freeform')->finalize_and_log('Ignored') unless $fileinfo;

	# Auto-add to mylist.
	my $mylistinfo = mylist_file_query($fileinfo->{lid} ? (lid => $fileinfo->{lid}) : (fid => $fileinfo->{fid}));
	if(!defined $mylistinfo && !$conf->test) {
		my $proc_sl = $sl->child('Freeform');
		$proc_sl->update('Adding to AniDB Mylist');
		if(my $lid = $a->mylist_add(fid => $fileinfo->{fid}, state => $a->MYLIST_STATE_HDD)) {
			$db->remove('anidb_mylist_anime', {aid => $fileinfo->{aid}}); # Force an update of this record, it's out of date.
			$db->update('adbcache_file', {lid => $lid}, {fid => $fileinfo->{fid}});
			$proc_sl->finalize_and_log('Added to AniDB Mylist');
		}
		else {
			$proc_sl->finalize_and_log('Error adding to AniDB Mylist');
		}
	}
	elsif($mylistinfo->{state} != $a->MYLIST_STATE_HDD && !$conf->test) {
		my $proc_sl = $sl->child('Freeform');
		$proc_sl->update('Setting AniDB Mylist state to "On HDD"');
		if($a->mylistedit({lid => $fileinfo->{lid}, state => $a->MYLIST_STATE_HDD})) {
			$db->update('anidb_mylist_file', {state => $a->MYLIST_STATE_HDD}, {fid => $mylistinfo->{fid}});
			$proc_sl->finalize_and_log('Set AniDB Mylist state to "On HDD"');
		}
		else {
			$proc_sl->finalize_and_log('Error setting AniDB Mylist state to "On HDD"');
		}
	}

	my $mylistanimeinfo = mylist_anime_query(aid => $fileinfo->{aid});
	if(!in_list($fileinfo->{episode_number}, $mylistanimeinfo->{eps_with_state_on_hdd})) {
		# Our mylistanime record is old. Can happen if the file was not added by kadr.
		$db->remove('anidb_mylist_anime', {aid => $fileinfo->{aid}});
		$mylistanimeinfo = mylist_anime_query(aid => $fileinfo->{aid});
	}

	$fileinfo->{episode_watched} = in_list($fileinfo->{episode_number}, $mylistanimeinfo->{watched_eps});

	# Watched / Unwatched directories.
	my $dir = first { $_->subsumes($file) } @{$conf->dirs_to_scan};
	if ($fileinfo->{episode_watched}) {
		if (none { $_->subsumes($dir) } @{$conf->valid_dirs_for_watched_eps}) {
			$dir = $conf->dir_to_put_watched_eps;
		}
	}
	else {
		if (none { $_->subsumes($dir) } @{$conf->valid_dirs_for_unwatched_eps}) {
			$dir = $conf->dir_to_put_unwatched_eps;
		}
	}

	for(keys %$fileinfo) {
		$fileinfo->{$_} =~ s/\//∕/g;
		$fileinfo->{$_} =~ s/\`/'/g;
		if($conf->windows_compatible_filenames) {
			$fileinfo->{$_} =~ tr!\?"\\<>\|:\*!？”￥＜＞｜：＊!;
		}
	}
	$fileinfo->{video_codec} =~ s/H264\/AVC/H.264/g;
	$fileinfo->{audio_codec} =~ s/Vorbis \(Ogg Vorbis\)/Vorbis/g;

	# Check if this is the only episode going into the folder.
	# This should be an assignment, but Parse::TitleSyntax evaluates undef as true.
	$fileinfo->{only_episode_in_folder} = 1 if
		defined $mylistanimeinfo
		# This is the only episode from this anime on HDD.
		&& $mylistanimeinfo->{eps_with_state_on_hdd} =~ /^[a-z]*\d+$/i
		# And this is it.
		&& $fileinfo->{episode_number} eq $mylistanimeinfo->{eps_with_state_on_hdd}
		&& (
			# This episode is the only watched episode from this anime.
			($fileinfo->{episode_watched} && $fileinfo->{episode_number} eq $mylistanimeinfo->{watched_eps})
			# Or this episode is the only unwatched episode from this anime.
			|| (!$fileinfo->{episode_watched} && count_list($mylistanimeinfo->{eps_with_state_on_hdd}) - count_list($mylistanimeinfo->{watched_eps}) == 1)
		);

	$fileinfo->{file_version} = $a->file_version($fileinfo);

	my $newname = $dir->file($conf->file_naming_scheme->Run($fileinfo));
	move_file($file, $ed2k, $newname);
}

sub move_file {
	my ($old, $ed2k, $new) = @_;

	# Doesn't need to be renamed.
	return if $old->absolute eq $new->absolute;

	$new->dir->mkpath unless -e $new->dir;

	my $display_new = shortest $new->relative, $new;
	my $sl = $sl->child('Freeform');

	if (-e $new) {
		return $sl->finalize_and_log('Would overwrite existing file: ' . $display_new);
	}

	if ($conf->test) {
		return $sl->finalize_and_log('Would have moved to: ' . $display_new);
	}

	$sl->update('Moving to ' . $display_new);
	if (move($old, $new)) {
		$db->update('known_files', {filename => $new->basename}, {ed2k => $ed2k, size => -s $new});
		$sl->finalize_and_log('Moved to ' . $display_new);
	}
	else {
		$sl->finalize_and_log('Error moving to ' . $display_new);
		#exit 2;
	}
}

sub avdump {
	my($file, $size, $ed2k) = @_;
	my($aved2k, $timedout);
	my $avsl = $sl->child('XofX', label => 'AvHashing', format => 'percent', total_item_count => 100);
	(my $esc_file = $file) =~ s/(["`])/\\\$1/g;
	my $exp = Expect->new($conf->avdump . " -vas -tout:20:6555 \"$esc_file\" 2>&1");
	$exp->log_stdout(0);
	$exp->expect($conf->avdump_timeout,
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
	my $size = -s $file;

	if(my $r = $db->fetch('known_files', ['ed2k', 'avdumped'], {filename => $file->basename, size => $size}, 1)) {
		avdump($file, $size, $r->{ed2k}) if $conf->has_avdump and !$r->{avdumped};
		return $r->{ed2k};
	}

	if($conf->has_avdump) {
		return avdump($file, $size);
	}

	my $ctx = Digest::ED2K->new;
	my $fh = $file->open('<:raw');
	my $ed2k_sl;

	if ($conf->show_hashing_progress) {
		$ed2k_sl = $sl->child('XofX', label => 'Hashing', total_item_count => $size, format => 'percent');
		while(my $bytes_read = read $fh, my $buffer, Digest::ED2K::CHUNK_SIZE) {
			$ctx->add($buffer);
			$ed2k_sl->incr($bytes_read);
			$ed2k_sl->update_term if $ed2k_sl->last_update + TERM_SPEED < Time::HiRes::time;
		}
	}
	else {
		$ed2k_sl = $sl->child('Freeform', value => 'Hashing');
		$ctx->addfile($fh);
	}

	my $ed2k = $ctx->hexdigest;
	if($db->exists('known_files', {ed2k => $ed2k, size => $size})) {
		$db->update('known_files', {filename => $file->basename}, {ed2k => $ed2k, size => $size});
	}
	else {
		$db->insert('known_files', {ed2k => $ed2k, filename => $file->basename, size => $size});
	}
	$ed2k_sl->finalize_and_log('Hashed');
	return $ed2k;
}

# Determines if the specified number is in a AniDB style list of episode numbers.
# Example: in_list(2, "1-3") == true
sub in_list {
	my($needle, $haystack) = @_;
	cache_list($haystack);
	if($needle =~ /^(.+),(.+)$/) {
		return in_list($1, $haystack);
	}
	if($needle =~ /^(\w+)-(\w+)$/) {
		return in_list($1, $haystack);
		# This is commented out to work around a bug in the AniDB UDP API.
		# For multi-episode files, the API only includes the first number in the lists that come in MYLIST commands.
		#for ($first..$last) {
		#	return 0 if !in_list($_, $haystack);
		#}
		#return 1;
	}
	return defined $in_list_cache->{$haystack}->{(int($needle) || $needle)};
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
				$in_list_cache->{$list}->{(int($_) || $_)} = 1;
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
	$a->logout if $a;
	$db->{dbh}->disconnect;
	exit;
}

sub file_query {
	my %params = @_;
	my $r;

	# Cached
	return $r if $r = $db->fetch("adbcache_file", ["*"], \%params, 1);

	# Update
	my $file_sl = $sl->child('Freeform', value => 'Updating file information');
	$r = eval { $a->file(%params) };

	# Due to unconfigurable fieldlists, the response is occasionally too long,
	# and gets truncated by the server after compression.
	if ($@) {
		die unless $@ =~ /^Error inflating response/;
		$file_sl->finalize($@);
	}

	return unless $r;

	# Cache
	$r->{updated} = time;
	$db->set('adbcache_file', $r, {fid => $r->{fid}});

	$r;
}

sub mylist_file_query {
	my $query = {@_};
	my $r;

	# Cached
	return $r if $r = $db->fetch("anidb_mylist_file", ["*"], $query, 1);

	# Update
	my $ml_sl = $sl->child('Freeform', value => 'Updating mylist information');
	$r = $a->mylist_file_query($query);
	return unless $r;

	# Cache
	$r->{updated} = time;
	$db->set('anidb_mylist_file', $r, {lid => $r->{lid}});

	$r
}

# Checks if we can get the lid from the file cache since lid lookups are faster.
sub mylist_file_by_ed2k_size {
	my ($ed2k, $size) = @_;

	my $fileinfo = $db->fetch("adbcache_file", ["*"], {size => $size, ed2k => $ed2k}, 1);
	if(defined($fileinfo)) {
		return if !$fileinfo->{lid};
		
		$db->remove("anidb_mylist_file", {lid => $fileinfo->{lid}});
		return mylist_file_query({lid => $fileinfo->{lid}});
	}
	return $a->mylist_file_query({size => $size, ed2k => $ed2k});
}

sub mylist_anime_query {
	my $query = {@_};
	my $r;

	# Cached
	return $r if $r = $db->fetch("anidb_mylist_anime", ["*"], $query, 1);

	# Update
	my $ml_sl = $sl->child('Freeform', value => 'Updating mylist anime information');
	$r = $a->mylist_anime_query($query);
	return unless $r;
	
	# Cache
	$r->{updated} = time;
	$db->set('anidb_mylist_anime', $r, {aid => $r->{aid}});

	$r
}
