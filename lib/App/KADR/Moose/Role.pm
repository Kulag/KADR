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
