package App::KADR::Moose::Exporter::Util;
# Utils for Moose::Exporter parameters

use common::sense;
use Sub::Exporter::Progressive -setup =>
	{ exports => [qw(get_sub_exporter_into_hash strip_import_params)] };

sub get_sub_exporter_into_hash {
	my $args = shift;

	# Start after $class
	for (my $i = 1; $i < @$args; $i += 2) {

		# Pass the MX params.
		next if $args->[$i] =~ /^-/;

		# The first argument is it if it's a hash.
		return $args->[$i] if ref $args->[$i] eq 'HASH';

		last;
	}

	# Not present, so add a blank hash.
	push @$args, my $params = {};
	return $params;
}

sub strip_import_params {
	my $args = shift;
	my %param_names = map { $_ => 1 } @_;

	my $i;
	my $params;
	while (++$i < @$args) {
		local $_ = $args->[$i];
		next if ref $_;
		my $name = s{^-}{}r;
		next unless delete $param_names{$name};

		$params->{$name} = $args->[ $i + 1 ];
		splice @$args, $i, 2;
	}

	$params;
}

0x6B63;

=head1 FUNCTIONS

=head2 C<get_sub_exporter_into_hash>

	my $hashref = get_sub_exporter_into_hash(\@_);

Returns the hashref meant for Sub::Exporter from a Moose::Exporter import array,
creating it if neccessary.

=head2 C<strip_import_params>

	my $params = strip_import_params(\@_, qw(foo bar));

Strips dash-prefixed params from an array, returning them.
