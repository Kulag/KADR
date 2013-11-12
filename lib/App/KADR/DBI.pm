package App::KADR::DBI;
# ABSTRACT: A terrible DBI wrapper you should feel bad for using

use 5.010001;
use common::sense;
use DBI;
use Encode;
use Scalar::Util qw(blessed);

use aliased 'App::KADR::Meta::Attribute::DoNotSerialize';

sub new {
	my $self = bless {}, shift;
	my $dsn = shift;
	$self->{class_map} = shift;
	$self->{rclass_map} = { map { ($self->{class_map}{$_}, $_) } keys %{ $self->{class_map} } };

	$self->{dbh} = DBI->connect($dsn) or die "Cannot connect: $DBI::errstr";

	if ($dsn =~ /^dbi:SQLite/) {
		$self->{dbh}{sqlite_unicode} = 1;
		$self->{unicode} = 1;
	}

	return $self;
}

sub cache {
	my($self, $to_cache_items) = @_;

	for my $to_cache (@$to_cache_items) {
		my @indexes = sort @{$to_cache->{indices}};
		my $ckey = join '-', $to_cache->{table}, @indexes;
		my $cache = $self->{cache}->{$ckey} = {};
		my $class = $self->{class_map}{ $to_cache->{table} };
		my $keys = join ',', $self->_keys_for($class);
		my $sth = $self->{dbh}->prepare("SELECT $keys FROM " . $to_cache->{table});
		$sth->execute;

		while (my $row = $sth->fetchrow_hashref) {
			unless ($self->{unicode}) {
				Encode::_utf8_on($row->{$_}) for keys %$row;
			}

			my $ckey2 = join '-', map { $row->{$_} } @indexes;
			$cache->{$ckey2} = $class->new($row);
		}
	}
}

sub fetch {
	my($self, $table, $what, $whereinfo, $limit) = @_;

	if (my $t = $self->{rclass_map}{$table}) {
		$table = $t;
	}

	# From cache
	my @cache_keys = sort keys %$whereinfo;
	if (my $a = $self->{cache}->{ join '-', $table, @cache_keys }->{ join '-', @$whereinfo{@cache_keys} }) {
		return $a;
	}

	my $class = $what->[0] eq '*' && $self->{class_map}{$table};
	if ($class) {
		$what = [$self->_keys_for($class)];
	}

	my $sth = $self->{dbh}->prepare_cached("SELECT " . join(",", @$what) . " FROM `$table`" . $self->_whereinfo($whereinfo) . ($limit ? "LIMIT $limit" : "")) or die $DBI::errstr;
	my @vals = values %$whereinfo;

	$sth->execute(@vals);
	my $r = int($limit) == 1 ? $sth->fetchrow_hashref() : $sth->fetchall_hashref();
	$sth->finish();

	if (defined $r) {
		for my $r (ref $r eq 'ARRAY' ? @$r : $r) {
			if (!$self->{unicode}) {
				Encode::_utf8_on $r->{$_} for keys %$r;
			}
			$r = $class->new($r) if $class;
		}
	}

	return $r;
}

sub exists {
	my($self, $table, $whereinfo) = @_;

	if (my $t = $self->{rclass_map}{$table}) {
		$table = $t;
	}

	my $sth = $self->{dbh}->prepare_cached("SELECT count(*) FROM $table" . $self->_whereinfo($whereinfo)) or die $DBI::errstr;
	my @vals = values %$whereinfo;

	$sth->execute(@vals);
	my($count) = $sth->fetchrow_array();
	$sth->finish();
	return $count;
}

sub insert {
	my($self, $table, $info) = @_;

	if (my $t = $self->{rclass_map}{$table}) {
		$table = $t;
	}

	if (blessed $info and my $class = $self->{class_map}{$table}) {
		$info = { map { ($_, $info->$_) } $self->_keys_for($class) };
	}

	my $sth = $self->{dbh}->prepare_cached("INSERT INTO $table (" . join(",", map { "`$_`" } keys(%{$info})) . ") VALUES(" . join(",", map {"?"} keys(%{$info})) . ")");
	my @vals = values(%{$info});
	$sth->execute(@vals);
	$sth->finish();
}

sub update {
	my($self, $table, $info, $whereinfo) = @_;

	if (my $t = $self->{rclass_map}{$table}) {
		$table = $t;
	}

	if (blessed $info and my $class = $self->{class_map}{$table}) {
		$info = { map { ($_, $info->$_) } $self->_keys_for($class) };
	}

	my $sth = $self->{dbh}->prepare_cached("UPDATE $table SET `" . join("`=?,`", keys(%{$info})) . "`=?" . $self->_whereinfo($whereinfo));
	my @vals = (values(%$info), values(%$whereinfo));
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

	if (my $t = $self->{rclass_map}{$table}) {
		$table = $t;
	}

	# From cache
	my @cache_keys = sort keys %$whereinfo;
	my $ckey = join '-', $table, @cache_keys;
	if (exists $self->{cache}->{$ckey}) {
		my $cache = $self->{cache}->{$ckey};
		$ckey = join '-', @$whereinfo{@cache_keys};
		delete $cache->{$ckey} if exists $cache->{$ckey};
	}

	my $sth = $self->{dbh}->prepare_cached("DELETE FROM $table" . $self->_whereinfo($whereinfo));
	my @vals = values(%{$whereinfo});

	$sth->execute(@vals);
	$sth->finish();
}

sub _whereinfo {
	my($self, $whereinfo) = @_;
	return scalar(keys %{$whereinfo}) ? " WHERE " . join(" and ",  map { "$_=?" } keys(%{$whereinfo})) : "";
}

sub _keys_for {
	my ($self, $class) = @_;
	map { $_->does(DoNotSerialize) ? () : $_->name }
		$class->meta->get_all_attributes;
}

1;

=head1 SYNOPSIS

  use App::KADR::DBI;
  
  my $db = App::KADR::DBI->new("dbi:SQLite:example.db");
  
  # Cache the contents of the files table in memory for quick access
  # when fetching with filename and size as the where clause.
  $db->cache([{table => "files", indices => ["filename", "size"]}]);
  
  # This probably doesn't even work...
  $result = $db->fetch("files", ['filename', 'size'], {filename => "foo"});
  $result->{foo}->{size};
  
  # This does, though.
  $result = $db->fetch("files", ['filename', 'size'], {filename => "foo"}, 1);
  $result->{size};
  
  # Will return true if a row in files with filename="foo" exists.
  $result = $db->exists("files", {filename => "foo"});
  
  $db->insert("files", {filename => "foo", size => 3});
  
  # Update files size=6 where filename="foo";
  $db->update("files", {size => 6}, {filename => "foo"});
  
  # Decides whether to insert a new row or update an existing one based on the where clause.
  $db->set("files", {filename => "foo", size => 6}, {filename => "foo"});
  
  $db->remove("files", {filename => "foo"});
  
  # DBI can still be accessed for more complex queries.
  $result = $db->{dbh}->selectone_arrayref("SELECT size, filename FROM files");

=head1 DESCRIPTION

App::KADR::DBI is a very simplistic interface for L<DBI> that aims to simplify
and speed up writing common database calls.

The main differences from the helper functions found within L<DBI> itself are: 
 - usage of prepare_cached rather than prepare
 - the ability to load a table into a transparent cache in RAM to speed access
 - functions are not called with SQL queries but the table name and a somewhat
   more perlish representation of data. Substitutions are handled for you.
 - it assumes the database uses utf8, encoding everything it sends and decoding
   everything it receives as utf8.
