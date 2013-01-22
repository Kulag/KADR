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
use Guard;
use List::AllUtils qw(first none);
use POSIX ();
use Text::Xslate;
use Time::HiRes;

use lib "$FindBin::RealBin/lib";
use App::KADR::AniDB::UDP::Client::Caching;
use App::KADR::Config;
use App::KADR::Path -all;
use App::KADR::Term::StatusLine::Fractional;
use App::KADR::Term::StatusLine::Freeform;
use App::KADR::Util qw(:pathname_filter shortest);

use constant TERM_SPEED       => $ENV{KADR_TERM_SPEED}       // 0.05;
use constant MTIME_DIFF_LIMIT => $ENV{KADR_MTIME_DIFF_LIMIT} // 10;
use constant EMPTY_ED2K       => "31d6cfe0d16ae931b73c59d7e0c089c0";

use constant SCHEMA_KNOWN_FILES => q{
CREATE TABLE IF NOT EXISTS known_files (
	`filename` TEXT,
	`size` INT,
	`ed2k` TEXT PRIMARY KEY,
	`mtime` INT,
	`avdumped` INT)
};

scope_guard \&cleanup;
$SIG{INT} = \&cleanup;

STDOUT->autoflush(1);

my $conf = App::KADR::Config->new_with_options;

my $db = DBI::SpeedySimple->new($conf->database);
$db->{dbh}->do(SCHEMA_KNOWN_FILES) or die 'Error initializing known_files';

my $a = App::KADR::AniDB::UDP::Client::Caching->new(
	db                      => $db,
	password                => $conf->anidb_password,
	timeout                 => $conf->query_timeout,
	time_to_sleep_when_busy => $conf->time_to_sleep_when_busy,
	username                => $conf->anidb_username,
	($conf->query_attempts > -1 ? (max_attempts => $conf->query_attempts) : ()),
);

if ($conf->expire_cache) {
	$db->{dbh}->do('DELETE FROM anidb_anime WHERE updated < ' . (time - $conf->cache_timeout_anime));
	$db->{dbh}->do('DELETE FROM adbcache_file WHERE updated < ' . (time - $conf->cache_timeout_file));
	$db->{dbh}->do('DELETE FROM anidb_mylist_anime WHERE updated < ' . (time - $conf->cache_timeout_mylist_unwatched) . ' AND watched_eps != eps_with_state_on_hdd');
	$db->{dbh}->do('DELETE FROM anidb_mylist_anime WHERE updated < ' . (time - $conf->cache_timeout_mylist_watched) . ' AND watched_eps = eps_with_state_on_hdd');
}

if($conf->load_local_cache_into_memory) {
	$db->cache([
		{table => 'known_files', indices => ['filename', 'size', 'mtime']},
		{table => 'anidb_anime', indices => ['aid']},
		{table => 'adbcache_file', indices => ['ed2k', 'size']},
		{table => 'anidb_mylist_file', indices => ['lid']},
		{table => 'anidb_mylist_anime', indices => ['aid']},
	]);
}

# Path template.
my $pathname_filter
	= $conf->windows_compatible_filenames
	? \&pathname_filter_windows
	: \&pathname_filter;
my $tx = Text::Xslate->new(
	function => {html_escape => $pathname_filter},
	path => {'path.tx' => $conf->file_naming_scheme},
);

my @files = find_files(@{$conf->dirs_to_scan});

print 'Sorting... ';
@files = $conf->collator->sort(@files);
say 'done.';

my @ed2k_of_processed_files;
my $current_file;
my $sl = App::KADR::Term::StatusLine::Fractional->new(
	max => scalar @files,
	update_label => sub { shortest $current_file->relative, $current_file },
);

$a->on(start => sub {
	my ($anidb, $tx) = @_;
	my $name = $tx->req->{name};

	my $type
		= $name eq 'file'   ? 'file'
		: $name eq 'anime'  ? 'anime'
		: $name eq 'mylist'
			? $tx->req->{params}{aid} ? 'mylist anime'
			:                           'mylist'
		:                      undef;

	return unless $type;

	my $sl = $sl->child('Freeform')->update('Updating ' . $type . ' info');
	$tx->on(finish => sub { $sl });
});

for my $file (@files) {
	$sl->incr;
	$current_file = $file;
	$sl->update_term if $sl->last_update + TERM_SPEED < Time::HiRes::time;

	next unless $file->is_file_exists;

	my $file_size = $file->size;
	my $mtime     = $file->stat->mtime;
	if (time() - $mtime < MTIME_DIFF_LIMIT) {
		$sl->child('Freeform')->finalize('Being Modified');
		next;
	}
	push @ed2k_of_processed_files, my $ed2k = ed2k_hash($file, $file_size, $mtime);

	unless ($conf->hash_only) {
		process_file($file, $ed2k, $file_size);
	}
}
$sl->finalize;

if ($conf->update_anidb_records_for_deleted_files && !$conf->hash_only) {
	update_mylist_state_for_missing_files(\@ed2k_of_processed_files, $a->MYLIST_STATE_DELETED);
}

if (!$conf->test && $conf->delete_empty_dirs_in_scanned) {
	print "Deleting empty folders in those scanned... ";

	my @scan_dirs = @{$conf->dirs_to_scan};
	my %keep;
	@keep{ @scan_dirs } = ();

	finddepth({
		follow => 1,
		no_chdir => 1,
		wanted => sub { rmdir unless exists $keep{$_} },
	}, @scan_dirs);

	say "done.";
}

sub valid_file {
	return if substr($_->basename, -5) eq '.part';
	return if substr($_->basename, 0, 1) eq '.';
	return if $_->basename eq 'Thumbs.db';
	return if $_->basename eq 'desktop.ini';
	1;
}

sub find_files {
	my @dirs = @_;
	my @files;

	my $sl = App::KADR::Term::StatusLine::Fractional->new(
		label => 'Scanning Directory',
		max   => \@dirs,
	);

	for my $dir (@dirs) {
		$sl->incr;
		if ($sl->last_update + TERM_SPEED < Time::HiRes::time) {
			$sl->update(shortest $dir->relative, $dir);
		}

		for ($dir->children) {
			if   ($_->is_dir) { push @dirs,  $_ }
			else              { push @files, $_ if valid_file }
		}
	}

	$sl->log(
		sprintf 'Found %d files in %d directories.',
		scalar @files,
		scalar @dirs
	);

	@files;
}

sub process_file {
	my ($file, $ed2k, $file_size) = @_;
	my $fileinfo = $a->file(ed2k => $ed2k, size => $file_size);

	# File not in AniDB.
	unless ($fileinfo) {
		$sl->child('Freeform')->finalize('Ignored');
		return;
	}

	my $anime = $fileinfo->{anime} = $a->anime(aid => $fileinfo->{aid});

	my $mylistinfo = $fileinfo->{mylist}
		= $a->mylist_file($fileinfo->{lid}
		? (lid => $fileinfo->{lid})
		: (fid => $fileinfo->{fid}));

	# Auto-add to mylist.
	if(!defined $mylistinfo && !$conf->test) {
		my $proc_sl = $sl->child('Freeform')->update('Adding to AniDB Mylist');
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
		my $proc_sl = $sl->child('Freeform')->update('Setting AniDB Mylist state to "On HDD"');
		if($a->mylistedit({lid => $fileinfo->{lid}, state => $a->MYLIST_STATE_HDD})) {
			$db->update('anidb_mylist_file', {state => $a->MYLIST_STATE_HDD}, {fid => $mylistinfo->{fid}});
			$proc_sl->finalize_and_log('Set AniDB Mylist state to "On HDD"');
		}
		else {
			$proc_sl->finalize_and_log('Error setting AniDB Mylist state to "On HDD"');
		}
	}

	my $mylistanimeinfo = $fileinfo->{anime}->{mylist}
		= $a->mylist_anime(aid => $fileinfo->{aid});

	# Note: Mylist anime data is broken server-side, only the min is provided.
	if (!$fileinfo->{episode_number}->in_ignore_max($mylistanimeinfo->{eps_with_state_on_hdd}))
	{
		# Our mylistanime record is old. Can happen if the file was not added by kadr.
		$db->remove('anidb_mylist_anime', {aid => $fileinfo->{aid}});
		$mylistanimeinfo = $a->mylist_anime(aid => $fileinfo->{aid});
	}

	# Note: Mylist anime data is broken server-side, only the min is provided.
	$fileinfo->{episode_watched} = $fileinfo->{episode_number}->in_ignore_max($mylistanimeinfo->{watched_eps});

	my $episode_count = $anime->{episode_count} || $anime->{highest_episode_number};
	$fileinfo->{episode_number_padded} = $fileinfo->{episode_number}->padded({'' => length $episode_count});

	$fileinfo->{video_codec} =~ s/H264\/AVC/H.264/g;
	$fileinfo->{audio_codec} =~ s/Vorbis \(Ogg Vorbis\)/Vorbis/g;

	# Check if this is the only episode going into the folder.
	# TODO: Since unwatched/watched dirs are no longer the only possible
	# states, this may be wrong depending on configuration.
	$fileinfo->{only_episode_in_folder}
		# Sole episode on HDD.
		= $fileinfo->{episode_number} eq $mylistanimeinfo->{eps_with_state_on_hdd}
		|| (
			$fileinfo->{episode_watched}
			# Sole watched episode.
			? $fileinfo->{episode_number} eq $mylistanimeinfo->{watched_eps}
			# Sole unwatched episode.
			: $fileinfo->{episode_number}->count == $mylistanimeinfo->{eps_with_state_on_hdd}->count - $mylistanimeinfo->{watched_eps}->count
		);

	$fileinfo->{is_primary_episode} =
		# This is the only episode.
		$anime->{episode_count} == 1 && $fileinfo->{episode_number} eq 1
		# And this file contains the entire episode.
		&& !$fileinfo->{other_episodes}
		# And it has a generic episode name.
		# Usually equal to the anime_type except for movies where multiple episodes may exist for split releases.
		&& ($fileinfo->{episode_english_name} eq $anime->{type} || $fileinfo->{episode_english_name} eq 'Complete Movie');

	$fileinfo->{file_version} = $a->file_version($fileinfo);

	my $newname = file( $tx->render('path.tx', $fileinfo) =~ s{[\r\n]}{}gr );

	# We can't end file/dir names in a dot on windows.
	if ($conf->windows_compatible_filenames) {
		$newname = file(
			map { s{\.$}{}r }
			($newname->has_dir ? $newname->dir->dir_list : ()),
			$newname->basename
		);
	}

	move_file($file, $ed2k, $newname);
}

sub move_file {
	my ($old, $ed2k, $new) = @_;

	# Doesn't need to be renamed.
	return if $old eq $new || $old->absolute eq $new->absolute;

	$new->dir->mkpath unless -e $new->dir;

	my $display_new = shortest $new->relative, $new;
	my $sl = $sl->child('Freeform');

	if (-e $new) {
		$sl->finalize('Would overwrite existing file: ' . $display_new);
		return;
	}

	if ($conf->test) {
		$sl->finalize('Would have moved to: ' . $display_new);
		return;
	}

	$sl->update('Moving to ' . $display_new);
	if (move($old, $new)) {
		$db->update('known_files', {filename => $new->basename}, {ed2k => $ed2k, size => -s $new});
		$sl->finalize('Moved to ' . $display_new);
	}
	else {
		my $name_max = POSIX::pathconf($new->dir, POSIX::_PC_NAME_MAX);
		if ($name_max < length $new->basename) {
			$sl->finalize('File name exceeds maximum length for folder (' . $name_max . '): ' . $display_new);
		}
		else {
			$sl->finalize('Error moving to ' . $display_new);
			exit 2;
		}
	}
}

sub avdump {
	my($file, $size, $mtime, $ed2k) = @_;
	my($aved2k, $timedout);
	my $avsl = $sl->child('Fractional', label => 'AvHashing', format => 'percent', max => 100);
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
		$db->set('known_files', {avdumped => 1, ed2k => $aved2k, filename => $file_sn, size => $size, mtime => $mtime},
			{filename => $file_sn, size => $size});
		return $aved2k;
	}
}

sub ed2k_hash {
	my($file, $size, $mtime) = @_;

	return EMPTY_ED2K unless $size;

	if(my $r = $db->fetch('known_files', ['ed2k', 'avdumped'],
		{filename => $file->basename, size => $size, mtime => $mtime}, 1)) {
		avdump($file, $size, $mtime, $r->{ed2k}) if $conf->has_avdump and !$r->{avdumped};
		return $r->{ed2k};
	}

	if ($conf->has_avdump && !$conf->hash_only) {
		return avdump($file, $size, $mtime);
	}

	my $ctx = Digest::ED2K->new;
	my $fh = $file->open('<:raw');
	my $ed2k_sl = $sl->child('Fractional', label => 'Hashing', max => $size, format => 'percent');

	while (my $bytes_read = $fh->read(my $buffer, 4096)) {
		$ctx->add($buffer);
		$ed2k_sl->incr($bytes_read);
		$ed2k_sl->update_term if $ed2k_sl->last_update + TERM_SPEED < Time::HiRes::time;
	}

	$ed2k_sl->finalize('Hashed');

	my $ed2k = $ctx->hexdigest;
	if($db->exists('known_files', {ed2k => $ed2k, size => $size})) {
		$db->update('known_files', {filename => $file->basename, mtime => $mtime}, {ed2k => $ed2k, size => $size});
	}
	else {
		$db->insert('known_files', {ed2k => $ed2k, filename => $file->basename, size => $size, mtime => $mtime});
	}

	return $ed2k;
}

sub cleanup {
	$a->logout if $a;
	$db->{dbh}->disconnect if $db;
	exit;
}

sub update_mylist_state_for_missing_files {
	my ($have_files, $set_state) = @_;
	$set_state //= $a->MYLIST_STATE_DELETED;
	my $set_state_name = $a->mylist_state_name_for($set_state);

	# Missing files.
	# Would need to bind/interpolate too many values to "NOT IN ()", this is faster.
	my $all_files = $db->{dbh}->selectall_arrayref('SELECT ed2k, size, filename FROM known_files');
	my %have_files;
	@have_files{ @$have_files } = ();
	my @missing_files
		= $conf->collator->sort(sub { $_->[2] },
			grep { !exists $have_files{$_->[0]} } @$all_files
		);

	# Don't print if no missing files.
	return unless @missing_files;

	$sl = App::KADR::Term::StatusLine::Fractional->new(
		label => 'Missing File',
		max => scalar @missing_files,
	);

	for my $file (@missing_files) {
		my ($ed2k, $size, $name) = @$file;

		# Forget file regardless of other processing.
		scope_guard {
			return if $conf->test;
			$db->remove('known_files', {ed2k => $ed2k, size => $size});
		};

		$sl->incr->update($name);

		# File mylist information.
		my $lid = $a->get_cached_lid(ed2k => $ed2k, size => $size);
		my $mylist_file;
		if ($lid) {
			# Update mylist record so we don't overwrite a user-set state.
			$db->remove('anidb_mylist_file', {lid => $lid});
			$mylist_file = $a->mylist_file(lid => $lid);
		}
		else {
			# Not in cache.
			$mylist_file = $a->mylist_file(ed2k => $ed2k, size => $size);
			$lid = $mylist_file->{lid} if $mylist_file;
		}

		# File not in mylist.
		next unless $mylist_file;

		# Don't overwrite user-set status.
		unless ($mylist_file->{state} == $a->MYLIST_STATE_HDD) {
			$sl->child('Freeform')
				->finalize('AniDB Mylist status already set.');
			next;
		}

		my $update_sl
			= $sl->child('Freeform')
				->update('Setting mylist state to ' . $set_state_name);

		next if $conf->test;

		# Try to edit
		$a->mylist_add(edit => 1, lid => $lid, state => $set_state)
			or die 'Error setting mylist state';

		$update_sl->finalize('Mylist state set to ' . $set_state_name);
		$db->update('anidb_mylist_file', {state => $set_state}, {lid => $lid});
	}
}

