package App::KADR::Collate;
# ABSTRACT:: Collation factory

use Class::Load qw(load_optional_class);
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
	return 'unicodeicu' if load_optional_class('Unicode::ICU::Collator');
	return 'unicode';
}

for my $class (findsubmod __PACKAGE__) {
	my $type = lc substr $class, rindex($class, ':') + 1;
	__PACKAGE__->register_factory_type($type, $class);
}

0x6B63;

=head1 SYNOPSIS

	my $collate = App::KADR::Collate->new($type, %params);

	my $type = App::KADR::Collate->resolve_auto;

=head1 CLASS METHODS

L<App::KADR::Collate> implements the following methods.

=head2 C<new>

	my $collate = App::KADR::Collate->new($type, %params);

Create collator of a type. If type is "auto", the result of
resolve_auto will be used.

=head2 C<resolve_auto>

	my $type = App::KADR::Collate->resolve_auto;

Determine best available collator type.
'unicodeicu' if L<Unicode::ICU::Collator> is available, otherwise 'unicode'.

=head1 SEE ALSO

L<App::KADR::Collate::None>, L<App::KADR::Collate::Ascii>,
L<App::KADR::Collate::Unicode>
