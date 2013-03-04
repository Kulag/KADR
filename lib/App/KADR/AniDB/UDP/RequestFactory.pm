package App::KADR::AniDB::UDP::RequestFactory;

use common::sense;
use Carp qw(confess);
use Class::Load 'load_class';
use Module::Find qw(findsubmod);

use parent 'Class::Factory';

sub add_factory_type {
	my ($class, $type, $implementation) = @_;

	load_class $implementation;

	confess 'Class ' . $implementation . ' does not inherit ::Message::Request'
		unless $implementation->isa('App::KADR::AniDB::UDP::Message::Request');

	$class->SUPER::add_factory_type($type, $implementation);
}

sub req {
	my ($class, $type) = (shift, shift);

	$class->get_factory_class($type)->new(@_);
}

for my $class (findsubmod 'App::KADR::AniDB::UDP::Request') {
	my $type = lc substr $class, rindex($class, ':') + 1;
	__PACKAGE__->register_factory_type($type, $class);
}

1;
