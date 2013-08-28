package t::lib::Moose::Exporter;
use common::sense;

use aliased 'App::KADR::Moose::Exporter', 'MX';

our @order;

for my $package (qw(t::lib::Moose::Exporter t::lib::Moose::Exporter::Sub)) {
	my $stash = Class::MOP::Package->initialize($package);
	for my $modifier (qw(before after)) {
		$stash->add_package_symbol(
			"&${modifier}_import",
			sub {
				push @order, "${package}::${modifier}";

				my $caller = $modifier eq 'after' ? $_[1]->name : $_[1];
				my $foo = $package . ' '
					. MX->get_import_params($caller, $package)->{foo};

				*{"${caller}::${modifier}i"} = sub {$foo};
			});
	}
}

MX->setup_import_methods(also => ['Moose'], import_params => ['foo']);
