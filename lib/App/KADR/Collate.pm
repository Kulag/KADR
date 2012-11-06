package App::KADR::Collate;
use Module::Find qw(findsubmod);
use MooseX::Types -declare => ['Collate'];
use MooseX::Types::Moose qw(Object Str);

use parent 'Class::Factory';

subtype Collate, as Object;
coerce Collate, from Str, via { __PACKAGE__->new($_) };

sub new {
	my ($class, $type) = (shift, shift);

	$type = $class->resolve_auto if $type eq 'auto';

	$class->get_factory_class($type)->new(@_);
}

sub resolve_auto {
	return 'unicode';
}

for my $class (findsubmod __PACKAGE__) {
	my $type = lc substr $class, rindex($class, ':') + 1;
	__PACKAGE__->register_factory_type($type, $class);
}

1;

=head1 NAME

App::KADR::Collate - Collation factory

=head1 SYNOPSIS

	my $collate = App::KADR::Collate->new($type, %params);

	my $type = App::KADR::Collate->resolve_auto;

=head1 CLASS METHODS

L<App::KADR::Collate> implements the following methods.

=head2 C<new>

	my $collate = App::KADR::Collate->new($type, %params);

Create collator of a type. If type is "auto",
the best available type will be used.

=head2 C<resolve_auto>

	my $type = App::KADR::Collate->resolve_auto;

Determine best available collator type.

=head1 SEE ALSO

L<App::KADR::Collate::None>, L<App::KADR::Collate::Ascii>,
L<App::KADR::Collate::Unicode>

=cut
