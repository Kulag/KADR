#!/usr/bin/env perl

use Test::More tests => 19;
use Test::Exception ();

{
	package TestRole;
	use App::KADR::Moose::Role {into => 'TestRole'};

	has 'role_attr';

	# strict refs off
	Test::Exception::lives_ok {
		my $a;
		$a = @{ $a->[0] };
	} 'common::sense loaded by ::Moose::Role';
}

{
	package TestClass;
	use App::KADR::Moose -meta_name => 'moo';

	with 'TestRole';

	has 'my_rw';

	has 'my_ro', is => 'ro', builder => 1, clearer => 1, predicate => 1;
	has '_private', clearer => 1, predicate => 1;

	# strict refs off
	Test::Exception::lives_ok {
		my $a;
		$a = @{ $a->[0] };
	} 'common::sense loaded by ::Moose';
}

{
	package TestNoclean;
	use App::KADR::Moose -noclean => 1;
	*dont_clean = sub {};
}

{
	package TestMutable;
	use App::KADR::Moose -mutable => 1;
}

use common::sense;

ok !TestClass->can('has'), 'namespace is clean';

ok(TestClass->can('moo'), 'import args passed to Moose correctly');

my $meta = TestClass->moo;

my $rw = $meta->get_attribute('my_rw');
ok $rw->has_read_method, 'my_rw is rw';
ok $rw->has_write_method, 'my_rw writable';

my $ro = $meta->get_attribute('my_ro');
ok $ro->has_read_method, 'my_ro readable';
ok !$ro->has_write_method, 'my_ro not made writable';

is $ro->builder, '_build_my_ro', 'my_ro has builder';
is $ro->clearer, 'clear_my_ro';
is $ro->predicate, 'has_my_ro';

ok(TestNoclean->can('dont_clean'), '-noclean works');

{
	my $attr = $meta->get_attribute('_private');
	is $attr->clearer, '_clear_private';
	is $attr->predicate, '_has_private';
}

ok grep(sub { $_ eq 'Chained' }, $rw->applied_traits), 'accessors chainable';

ok $meta->is_immutable, 'metaclass immutable';

{
	my $ra = $meta->find_attribute_by_name('role_attr');
	ok $ra->has_read_method, 'role_attr readable';
	ok $ra->has_write_method, 'role_attr writable';
}

ok !TestMutable->meta->is_immutable, 'mutable flag works';
