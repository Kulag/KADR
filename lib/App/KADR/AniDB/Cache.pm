package App::KADR::AniDB::Cache;
# ABSTRACT: A cache with support for searches

use Moose::Util::TypeConstraints;
use App::KADR::Moose;

coerce __PACKAGE__, from 'HashRef', via { __PACKAGE__->new($_) };

has 'db', is => 'ro', isa => 'App::KADR::DBI', required => 1;
has 'ignore_max_age', is => 'ro', isa => 'Bool';
has 'max_ages', is => 'ro', default => sub { {} };

method compute(@_) {
	my $code = pop;
	my ($class, $keys, $opts) = @_;

	if (my $obj = $self->get($class, $keys, $opts)) {
		return $obj;
	}

	if (my $obj = $code->()) {
		$self->set($obj);
		return $obj;
	}

	();
}

method get($class, $keys, $opts?) {
	return unless my $obj = $self->db->fetch($class, ['*'], $keys, 1);

	# Expiry
	my $max_age = $self->max_age_for($obj, $opts->{max_age});
	return if $obj->updated < time - $max_age && !$self->ignore_max_age;

	$obj;
}

method max_age_for($obj, $override?) {

	# Per-object maximum age
	if ($obj->max_age_is_dynamic) {
		if (my $defaults = $self->max_ages->{ ref $obj || $obj }) {
			if (defined $override) {
				if (ref $override eq 'HASH') {
					return $obj->max_age({ %$defaults, %$override });
				}
				return $obj->max_age($override);
			}
			return $obj->max_age($defaults);
		}
		return $obj->max_age($override);
	}

	# Per-class maximum age
	$self->{max_age_for}{ ref $obj || $obj }{$override}
		//= $obj->max_age($override // $self->max_ages->{ ref $obj || $obj });
}

method set($obj) {
	my $pk = $obj->primary_key;

	$self->db->set(ref $obj, $obj, { $pk => $obj->$pk });

	();
}

=head1 SYNOPSIS

	use aliased 'App::KADR::AniDB::Cache';

	my $cache = Cache->new(db => App::KADR::DBI->new('dbi:SQLite::memory:'));

	# Calculate the maximum age before a class's record is stale.
	my $time = $cache->max_age_for(File);

	# Calculate the maximum age before a content instance is stale,
	# overriding some tags.
	my $time = $cache->max_age_for(MylistSet, { watching => 2 * 60 * 60 });

	# Save something
	$cache->set($file);

	# Get something out of the cache.
	$cache->get(File, { fid => 1 });

=head1 DESCRIPTION

C<App::KADR::AniDB::Cache> is a simple cache with support for searching for
cached items by attribute. 

Maximum ages for content classes and objects are specified in each content
class. C<max_ages> overrides those defaults on a per-cache object basis, and a
maximum age can be specified in the options for each <get>.

Why not use CHI? Unfortunately, it only has key-value lookup, which could mean
unnecessary additional queries to AniDB.

=head1 ATTRIBUTES

L<App::KADR::AniDB::Cache> implements the following attributes.

=head2 C<ignore_max_age>

	my $bool  = $cache->ignore_max_age;
	my $cache = Cache->new(ignore_max_age => 1);

Set to always return cached content, even if it's older than the C<max_age_for>
it.

=head2 C<max_ages>

	my $max_ages = $cache->max_ages;
	my $cache    = Cache->new(
		max_ages => {
			# Per-class default
			File ,=> 12 * 24 * 60 * 60,

			# Per-class default on a class that supports per-instance defaults
			MylistSet ,=> 12 * 24 * 60 * 60,

			# Per-instance defaults
			MylistSet ,=> {
				# Default for an unblessed class
				'' => 12 * 24 * 60 * 60,

				# Default for an instance which is tagged 'watching'
				watching => 24 * 60 * 60,
			},
		}
	);

Cache-level defaults for content max ages. See individual content classes for
their defaults, and whether they support per-instance defaults.

=head2 C<db>

	my $db = $client->db;

A L<App::KADR::DBI> instance. Required at creation.

=head1 METHODS

L<App::KADR::AniDB::Cache> implements the following methods.

=head2 C<get>

	my $obj = $cache->get(File, { fid => 1 });
	my $obj = $cache->get(File, { fid => 1 }, { max_age => 0 });

Get the object associated with the keys. Expired items are not removed.

=head2 C<max_age_for>

	my $time = $cache->max_age_for($class || $object);
	my $time = $cache->max_age_for($class || $object, 0); # override to 0.
	my $time = $cache->max_age_for($class || $object, {
		# Default for an class name
		'' => 12 * 24 * 60 * 60,

		# Default for an object which is tagged 'watching'
		watching => 24 * 60 * 60,
	});

Calculate the maximum age before a content class or object is stale.
Defaults set by the content class and in the cache object can be overridden.
If the content class supports tagged per-instance defaults, you can override
tags individually.

=head2 C<set>

	my $obj = $cache->set($object);

Add the object to the cache. If the cache contains record with the same primary
key, it will be updated in place.
