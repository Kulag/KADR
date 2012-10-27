package App::KADR::Moose::Role;
use common::sense;
use App::KADR::Moose::Policy ();

my ($import, $unimport, $init_meta) = Moose::Exporter->setup_import_methods(
	also    => [qw(Moose::Role App::KADR::Moose::Policy)],
	install => [qw(unimport init_meta)],
);

sub import {
	App::KADR::Moose::Policy->strip_import_params(\@_);

	goto &$import;
}

1;

=head1 NAME

App::KADR::Moose::Role - Moose::Role policy

=head1 SYNPOSIS

	package Bar;
	use App::KADR::Moose::Role;

=head1 DESCRIPTION

App::KADR::Moose::Role makes your class a Moose role with some with some
default imports and attribute options.

=head1 SEE ALSO

L<App::KADR::Moose>, L<App::KADR::Moose::Policy>

=cut
