package App::KADR::Moose::Role;
use v5.14;
use Moose ();
use Moose::Exporter ();
use namespace::autoclean;
use true;

use App::KADR::Moose ();
use common::sense;

*has = *App::KADR::Moose::has;

my ($moose_import) = Moose::Exporter->setup_import_methods(
	with_meta => [qw(has)],
	also => [qw(Moose::Role)],
	install => [qw(unimport init_meta)],
);

*import = App::KADR::Moose->build_importer($moose_import);

=head1 NAME

App::KADR::Moose::Role - Moose::Role policy

=head1 SYNPOSIS

	package Bar;
	use App::KADR::Moose::Role;

=head1 DESCRIPTION

App::KADR::Moose::Role makes your class a Moose role with some with some
default imports and attribute options. See L<App::KADR::Moose> for details.
