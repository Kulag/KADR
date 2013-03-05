package App::KADR::Moose::Role;
# ABSTRACT: Moose::Role with KADR policy

use common::sense;
use App::KADR::Moose::Policy ();

my ($import, $unimport, $init_meta) = Moose::Exporter->setup_import_methods(
	also    => [qw(Moose::Role App::KADR::Moose::Policy)],
	install => [qw(unimport init_meta)],
);

sub import {
	__PACKAGE__->strip_import_params(\@_);

	goto &$import;
}

sub strip_import_params {
	App::KADR::Moose::Policy->strip_import_params($_[1]);
}

0x6B63;

=head1 SYNPOSIS

	package Bar;
	use App::KADR::Moose::Role;

=head1 DESCRIPTION

App::KADR::Moose::Role makes your class a Moose role with some with some
default imports and attribute options.

=head1 IMPORT PARAMETERS

L<App::KADR::Moose::Role> inherits all import parameters from
L<App::KADR::Moose::Policy>.

=head1 CLASS METHODS

=head2 C<strip_import_params>

	sub my_import {
		App::KADR::Moose::Role->strip_import_params(\@_);

		...
	}

Strip parameters from your import when chaining L<Moose::Exporter> imports.

=head1 SEE ALSO

L<App::KADR::Moose>, L<App::KADR::Moose::Policy>
