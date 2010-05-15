# Copyright (c) 2009, Kulag <g.kulag@gmail.com>

# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.

# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

package db;
use strict;
use warnings;
use DBI;
use Encode;

sub new {
	my $self = bless {}, shift;
	$self->{dbh} = DBI->connect(shift) or die "Cannot connect: $DBI::errstr";
	return $self;
}

sub cache {
	my($self, $to_cache) = @_;
	$self->{cache} = bless {};
	for(@{$to_cache}) {
		my $ckey = join '-', ($_->{table}, @{$_->{indices}});
		$self->{cache}->{$ckey} = $self->{dbh}->selectall_hashref('SELECT * FROM ' . $_->{table}, $_->{indices});
		if(defined $self->{cache}->{$ckey}) {
			_cache_mark_utf8($self->{cache}->{$ckey}, scalar(@{$_->{indices}}));
		}
	}
	return;
}

sub _cache_mark_utf8 {
	my($cache, $index_depth) = @_;
	if($index_depth == 0) {
		for(keys %$cache) {
			Encode::_utf8_on($cache->{$_});
		}
	}
	elsif($index_depth > 0) {
		my $new_depth = $index_depth - 1;
		for(keys %$cache) {
			_cache_mark_utf8($cache->{$_}, $new_depth);
		}
	}
	else {
		die 'bad index depth in cache';
	}
	return;
}

sub fetch {
	my($self, $table, $what, $whereinfo, $limit) = @_;
	my $ckey = join('-', ($table, keys %{$whereinfo}));
	if(defined $self->{cache}->{$ckey}) {
		my $ptr = $self->{cache}->{$ckey};
		for(values %{$whereinfo}) {
			$ptr = $ptr->{$_};
		}
		return $ptr if defined $ptr;
	}
	
	my $sth = $self->{dbh}->prepare_cached("SELECT " . join(",", @$what) . " FROM `$table`" . $self->_whereinfo($whereinfo) . ($limit ? "LIMIT $limit" : "")) or die $DBI::errstr;
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	my $r = int($limit) == 1 ? $sth->fetchrow_hashref() : $sth->fetchall_hashref();
	$sth->finish();
	if(defined $r) {
		Encode::_utf8_on($r->{$_}) for keys %$r;
	}
	return $r;
}

sub exists {
	my($self, $table, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("SELECT count(*) FROM $table" . $self->_whereinfo($whereinfo)) or die $DBI::errstr;
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	my($count) = $sth->fetchrow_array();
	$sth->finish();
	return $count;
}

sub insert {
	my($self, $table, $info) = @_;
	my $sth = $self->{dbh}->prepare_cached("INSERT INTO $table (" . join(",", map { "`$_`" } keys(%{$info})) . ") VALUES(" . join(",", map {"?"} keys(%{$info})) . ")");
	my @vals = values(%{$info});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub update {
	my($self, $table, $info, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("UPDATE $table SET `" . join("`=?,`", keys(%{$info})) . "`=?" . $self->_whereinfo($whereinfo));
	my @vals = (values(%$info), values(%$whereinfo));
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub set {
	my($self, $table, $info, $whereinfo) = @_;
	return $self->update($table, $info, $whereinfo) if $self->exists($table, $whereinfo);
	return $self->insert($table, $info);
}

sub remove {
	my($self, $table, $whereinfo) = @_;
	if($self->{caching} and defined $self->{cache}->{join('-', ($table, keys %{$whereinfo}))}) {
		my $ptr = $self->{cache}->{join('-', ($table, keys %{$whereinfo}))};
		for my $index (keys %{$whereinfo}) {
			$ptr = $ptr->{$whereinfo->{$index}};
		}
		#delete $ptr if defined $ptr;
	}
	
	my $sth = $self->{dbh}->prepare_cached("DELETE FROM $table" . $self->_whereinfo($whereinfo));
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub _whereinfo {
	my($self, $whereinfo) = @_;
	return scalar(keys %{$whereinfo}) ? " WHERE " . join(" and ",  map { "$_=?" } keys(%{$whereinfo})) : "";
}

1;
