package App::KADR::Moose::AttrDefaults;
use MooseX::Role::Parameterized;

parameter 'opts', isa => 'HashRef', default => sub { {} };

role {
	my $defaults = shift->opts;

	before _process_options => sub {
		my ($class, $name, $options) = @_;
		$options->{$_} //= $defaults->{$_} for keys %$defaults;
	};
};
