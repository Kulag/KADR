use v5.14;

package t::Class {
	use t::lib::Moose::Exporter -foo => 'bar';
}

package t::SubClass {
	use t::lib::Moose::Exporter::Sub -foo => 'baz';
}

use aliased;
use Test::More;

sub Exporter()    {'t::lib::Moose::Exporter'}
sub SubExporter() {'t::lib::Moose::Exporter::Sub'}

ok($_->isa('Moose::Object'), "also a Moose: $_")
	for qw(t::Class t::SubClass);

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

is(t::Class->$_, Exporter . ' bar', "t::Class::$_") for qw(beforei afteri);
is(t::SubClass->beforei, Exporter . ' baz',    't::SubClass::beforei');
is(t::SubClass->afteri,  SubExporter . ' baz', 't::SubClass::afteri');

done_testing;
