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

sub new {
	my $self = bless {}, shift;
	$self->{dbh} = DBI->connect(shift) or die "Cannot connect: $DBI::errstr";
	return $self;
}

sub cache {
	my($self, $to_cache) = @_;
	$self->{cache} = bless {};
	for(@{$to_cache}) {
		$self->{cache}->{join '-', ($_->{table}, @{$_->{indices}})} = $self->{dbh}->selectall_hashref("SELECT * FROM " . $_->{table}, $_->{indices});
	}
}

sub fetch {
	my($self, $table, $what, $whereinfo, $limit) = @_;
	if(defined $self->{cache}->{join('-', ($table, keys %{$whereinfo}))}) {
		my $ptr = $self->{cache}->{join('-', ($table, keys %{$whereinfo}))};
		for my $index (keys %{$whereinfo}) {
			$ptr = $ptr->{$whereinfo->{$index}};
		}
		return $ptr if defined $ptr;
	}
	
	my $sth = $self->{dbh}->prepare_cached("SELECT " . join(",", @$what) . " FROM `$table`" . $self->_whereinfo($whereinfo) . ($limit ? "LIMIT $limit" : "")) or die $DBI::errstr;
	$sth->execute(map { "$whereinfo->{$_}" } keys(%{$whereinfo}));
	my $r = int($limit) == 1 ? $sth->fetchrow_hashref() : $sth->fetchall_hashref();
	$sth->finish();
	$r;
}

sub exists {
	my($self, $table, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("SELECT count(*) FROM $table" . $self->_whereinfo($whereinfo)) or die $DBI::errstr;
	$sth->execute(map { "$whereinfo->{$_}" } keys(%{$whereinfo}));
	my($count) = $sth->fetchrow_array();
	$sth->finish();
	return $count;
}

sub insert {
	my($self, $table, $info) = @_;
	my $sth = $self->{dbh}->prepare_cached("INSERT INTO $table (" . join(",", map { "`$_`" } keys(%{$info})) . ") VALUES(" . join(",", map {"?"} keys(%{$info})) . ")");
	$sth->execute(map { "$info->{$_}" } keys(%{$info}));
	$sth->finish();
}

sub update {
	my($self, $table, $info, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("UPDATE $table SET `" . join("`=?,`", keys(%{$info})) . "`=?" . $self->_whereinfo($whereinfo));
	my @a = map { "$info->{$_}" } keys(%{$info});
	my @b = map { "$whereinfo->{$_}" } keys(%{$whereinfo});
	$sth->execute(@a, @b);
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
	$sth->execute(map { "$whereinfo->{$_}" } keys(%{$whereinfo}));
	$sth->finish();
}

sub _whereinfo {
	my($self, $whereinfo) = @_;
	return scalar(keys %{$whereinfo}) ? " WHERE " . join(" and ",  map { "$_=?" } keys(%{$whereinfo})) : "";
}

1;
