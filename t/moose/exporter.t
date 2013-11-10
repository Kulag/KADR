package TestClass {
use v5.14;

	use t::lib::Moose::Exporter -foo => 'bar';
}

package TestSubClass {
	use t::lib::Moose::Exporter::Sub -foo => 'baz';
}

use aliased;
use Test::More;

sub Exporter()    {'t::lib::Moose::Exporter'}
sub SubExporter() {'t::lib::Moose::Exporter::Sub'}

ok($_->isa('Moose::Object'), "also a Moose: $_")
	for qw(TestClass TestSubClass);

is_deeply(
	\@t::lib::Moose::Exporter::order,
	[
		Exporter . '::before',
		Exporter . '::after',
		SubExporter . '::before',
		Exporter . '::before',
		Exporter . '::after',
		SubExporter . '::after',
	],
	'modifier ordering'
);

is(TestClass->$_, Exporter . ' bar', "TestClass::$_") for qw(beforei afteri);
is(TestSubClass->beforei, Exporter . ' baz',    'TestSubClass::beforei');
is(TestSubClass->afteri,  SubExporter . ' baz', 'TestSubClass::afteri');

done_testing;
