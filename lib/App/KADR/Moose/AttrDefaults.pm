package App::KADR::Moose::AttrDefaults;
# ABSTRACT: Meta attribute trait to apply default options

use MooseX::Role::Parameterized;

parameter 'opts', isa => 'HashRef', default => sub { {} };

role {
	my $defaults = shift->opts;

	before _process_options => sub {
		my ($class, $name, $options) = @_;
		$options->{$_} //= $defaults->{$_} for keys %$defaults;
	};
};

=head1 SYNOPSIS

	my $default_attr_role = AttrDefaults->meta->generate_role(
		parameters => { opts => { is => 'rw' } });

	Moose::Exporter->setup_import_methods(
		class_metaroles => { attribute => [$default_attr_role] });

=param C<opts>

Hashref of options to apply to the attribute if the option is not defined.
