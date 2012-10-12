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

sub import {
	my $self = shift;

	Moose->throw_error('Usage: use ' . __PACKAGE__ . ' (key => value, ...)')
		if @_ % 2 == 1 && ref $_[0] ne 'HASH';

	my $opts = @_ == 1 ? shift : {@_};
	my $into = $opts->{into} ||= scalar caller;

	$self->$moose_import($opts);

	# use common::sense
	strict->unimport;
	warnings->unimport;
	common::sense->import;

	# Require a perl version.
	feature->import(App::KADR::Moose::FEATURE_VERSION);

	# Cleanliness
	namespace::autoclean->import(-cleanee => $into);
	$into->true::import;
}
