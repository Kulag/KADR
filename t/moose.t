#!/usr/bin/env perl

use common::sense;

{
	package TestClass;
	use App::KADR::Moose;

	has 'my_rw';

	has 'my_ro',
		is => 'ro';
}

use Test::More tests => 7;

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
