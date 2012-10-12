#!/usr/bin/env perl

use Test::More tests => 11;
use Test::Exception ();

{
	package TestRole;
	use App::KADR::Moose::Role;

	has 'role_attr';

	# strict refs off
	Test::Exception::lives_ok {
		my $a;
		$a = @{ $a->[0] };
	} 'common::sense loaded by ::Moose::Role';
}

{
	package TestClass;
	use App::KADR::Moose;

	with 'TestRole';

	has 'my_rw';

	has 'my_ro',
		is => 'ro';

	# strict refs off
	Test::Exception::lives_ok {
		my $a;
		$a = @{ $a->[0] };
	} 'common::sense loaded by ::Moose';
}


use common::sense;

ok !TestClass->can('has'), 'namespace is clean';

my $meta = TestClass->meta;

my $rw = $meta->get_attribute('my_rw');
ok $rw->has_read_method, 'my_rw is rw';
ok $rw->has_write_method, 'my_rw writable';

my $ro = $meta->get_attribute('my_ro');
ok $ro->has_read_method, 'my_ro readable';
ok !$ro->has_write_method, 'my_ro not made writable';

ok grep(sub { $_ eq 'Chained' }, $rw->applied_traits), 'accessors chainable';

ok $meta->is_immutable, 'metaclass immutable';

{
	my $ra = $meta->find_attribute_by_name('role_attr');
	ok $ra->has_read_method, 'role_attr readable';
	ok $ra->has_write_method, 'role_attr writable';
}
