package App::KADR::Meta::Method::Inlined;
# ABSTRACT: Abstract base class for inlined methods

use App::KADR::Moose;
use MooseX::ABC;

extends qw(Moose::Meta::Method Class::MOP::Method::Inlined);

has 'body',
	is      => 'lazy',
	isa     => 'CodeRef',
	builder => method {
		$self->_compile_code(
			source      => [ 'sub {', $self->_inline_body, '}' ],
			environment => $self->_eval_environment,
		);
	};
has 'name', required => 1;
has '_eval_environment', is => 'ro', default => sub { {} };

requires '_inline_body';

=head1 EXTENDS

=over

=item L<Moose::Meta::Method>
=item L<Class::MOP::Method::Inlined>

=back

=head1 ATTRIBUTES

=head2 C<_eval_environment>

	%env = %{ $self->_eval_environment };

Environment used when compiling the method body. For use by subclasses only.

=head1 REQUIRED METHODS

=head2 C<_inline_body>

The body of your method, less the enclosing C<sub { }>

=head1 SEE ALSO

C<Class::MOP::Method::Inlined>
