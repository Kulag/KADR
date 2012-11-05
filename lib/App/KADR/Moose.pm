package App::KADR::Moose;
use common::sense;
use App::KADR::Moose::Policy ();

my ($import, $unimport, $init_meta) = Moose::Exporter->setup_import_methods(
	also    => [qw(Moose App::KADR::Moose::Policy)],
	install => [qw(unimport init_meta)],
);

sub import {
	__PACKAGE__->strip_import_params(\@_);

	goto &$import;
}

sub strip_import_params {
	App::KADR::Moose::Policy->strip_import_params($_[1]);
}

1;

=head1 NAME

App::KADR::Moose - Moose policy

=head1 SYNPOSIS

	package Foo;
	use App::KADR::Moose;
	# Implicit
	# use common::sense;
	# use namespace::autoclean;
	# use true;

	# Implicitly is 'rw' and traits Chained.
	has 'attr';

	# Implicit
	__PACKAGE__->meta->make_immutable;

=head1 DESCRIPTION

L<App::KADR::Moose> makes your class a Moose class with some default imports
and attribute options.

=head1 IMPORT PARAMETERS

L<App::KADR::Moose> inherits all import parameters from
L<App::KADR::Moose::Policy>.

=head1 CLASS METHODS

=head2 C<strip_import_params>

	sub my_import {
		App::KADR::Moose->strip_import_params(\@_);

		...
	}

Strip parameters from your import when chaining L<Moose::Exporter> imports.

=head1 SEE ALSO

L<App::KADR::Moose::Policy>, L<App::KADR::Moose::Role>

=cut
