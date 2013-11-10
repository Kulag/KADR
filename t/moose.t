use v5.14;
use Test::More;
use Test::Fatal;

package t::Role {
	use App::KADR::Moose::Role { into => 't::Role' };

	has 'role_attr';

	method test {}

	# strict refs off
	Test::More::is Test::Fatal::exception {
		my $a;
		$a = @{ $a->[0] };
	}, undef, 'common::sense loaded by ::Moose::Role';
}

package t::Class {
	use App::KADR::Moose -meta_name => 'moo';

	with 't::Role';

	has 'rw';
	has 'ro', is => 'ro', builder => sub {'foo'}, clearer => 1, predicate => 1;

	# strict refs off
	Test::More::is Test::Fatal::exception {
		my $a;
		$a = @{ $a->[0] };
	}, undef, 'common::sense loaded by ::Moose';
}

package t::Noclean {
	use App::KADR::Moose -noclean => 1;
}

package t::Mutable {
	use App::KADR::Moose -mutable => 1;
}

package t::Attrs {
	use App::KADR::Moose -attr => { is => 'ro' };
	has 'ro';
}

use common::sense;

my $t = t::Class->new;

ok !$t->can('has'), 'namespace is clean';

ok(t::Class->can('moo'), 'import args passed to Moose correctly');

my $meta = t::Class->moo;
ok $meta->is_immutable, 'metaclass immutable';

is $t->rw(1), $t, 'rw writable, chainable';
is $t->rw, 1, 'rw is readable';

like exception { $t->ro(1) }, qr/read-only/, 'ro not made writable';
is $t->ro, 'foo', 'my_ro readable';
$t->clear_ro;
ok !$t->has_ro, 'ro unset';

ok(t::Noclean->can('has'), '-noclean works');

ok $t->role_attr('foo'), 'role_attr writable';
is $t->role_attr, 'foo', 'role_attr readable';

ok !t::Mutable->meta->is_immutable, 'mutable flag works';

like exception { t::Attrs->new->ro(1) }, qr/read-only/,
	'TestAttrs default is ro';

done_testing;
