package App::KADR::Moose;
use common::sense;
use App::KADR::Moose::Policy ();

my ($import, $unimport, $init_meta) = Moose::Exporter->setup_import_methods(
	also    => [qw(Moose App::KADR::Moose::Policy)],
	install => [qw(unimport init_meta)],
);

sub import {
	App::KADR::Moose::Policy->strip_import_params(\@_);

	goto &$import;
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

App::KADR::Moose makes your class a Moose class with some default imports
and attribute options.

=head1 SEE ALSO

L<App::KADR::Moose::Policy>, L<App::KADR::Moose::Role>

=cut
