use v5.14;
use Test::More;
use Test::Fatal;

package TestRole {
	use App::KADR::Moose::Role {into => 'TestRole'};

	has 'role_attr';

	method test {}

	# strict refs off
	Test::More::is Test::Fatal::exception {
		my $a;
		$a = @{ $a->[0] };
	}, undef, 'common::sense loaded by ::Moose::Role';
}

package TestClass {
	use App::KADR::Moose -meta_name => 'moo';

	with 'TestRole';

	has 'rw';
	has 'ro', is => 'ro', builder => sub {'foo'}, clearer => 1, predicate => 1;

	# strict refs off
	Test::More::is Test::Fatal::exception {
		my $a;
		$a = @{ $a->[0] };
	}, undef, 'common::sense loaded by ::Moose';
}

package TestNoclean {
	use App::KADR::Moose -noclean => 1;
}

package TestMutable {
	use App::KADR::Moose -mutable => 1;
}

package TestAttrs {
	use App::KADR::Moose -attr => { is => 'ro' };
	has 'ro';
}

use common::sense;

my $t = TestClass->new;

ok !$t->can('has'), 'namespace is clean';

ok(TestClass->can('moo'), 'import args passed to Moose correctly');

my $meta = TestClass->moo;
ok $meta->is_immutable, 'metaclass immutable';

is $t->rw(1), $t, 'rw writable, chainable';
is $t->rw, 1, 'rw is readable';

like exception { $t->ro(1) }, qr/read-only/, 'ro not made writable';
is $t->ro, 'foo', 'my_ro readable';
$t->clear_ro;
ok !$t->has_ro, 'ro unset';

ok(TestNoclean->can('has'), '-noclean works');

ok $t->role_attr('foo'), 'role_attr writable';
is $t->role_attr, 'foo', 'role_attr readable';

ok !TestMutable->meta->is_immutable, 'mutable flag works';

like exception { TestAttrs->new->ro(1) }, qr/read-only/,
	'TestAttrs default is ro';

done_testing;
