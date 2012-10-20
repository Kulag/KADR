package App::KADR::Moose;
use v5.14;
use Hook::AfterRuntime;
use List::Util qw(first);
use List::MoreUtils qw(firstidx);
use Moose ();
use Moose::Exporter ();
use MooseX::Attribute::Chained ();
use MooseX::StrictConstructor 0.19 ();
use namespace::autoclean;
use true;

use common::sense;

sub FEATURE_VERSION() { ':5.14' }

my %prefix = (
	clearer => 'clear',
	predicate => 'has',
);

my ($moose_import) = Moose::Exporter->setup_import_methods(
	with_meta => [qw(has)],
	also => [qw(Moose MooseX::StrictConstructor)],
	install => [qw(unimport init_meta)],
);

sub build_importer {
	my ($class, $moose_import, $import) = @_;

	sub {
		my $self = shift;
		my $opts = _get_extra_argument(\@_);
		my $into = $opts->{into} ||= scalar caller;
		my $clean = 1;

		if ((my $i = firstidx { $_ eq '-noclean' } @_) >= 0) {
			splice @_, $i, 2;
			$clean = 0;
		}

		$self->$import($opts, \@_) if $import;
		$self->$moose_import(@_);
		$class->import_base($into);

		namespace::autoclean->import(-cleanee => $into) if $clean;
	}
}

sub has($;@) {
	my $meta = shift;
	my $name = shift;

	Moose->throw_error('Usage: has \'name\' => ( key => value, ... )')
		if @_ % 2 == 1;

	my %options = (definition_context => Moose::Util::_caller_info(), @_);
	my $attrs = ref $name eq 'ARRAY' ? $name : [$name];

	$options{builder} = '_build_' . $name if $options{builder} eq '1';
	$options{is} //= 'rw';

	my $default_template = $name =~ /^_/ ? '_%s%s' : '%s_%s';
	my $default_for = sub {
		my $opt = shift;
		$options{$opt} = sprintf $default_template, $prefix{$opt}, $name
			if $options{$opt} eq '1';
	};
	$default_for->($_) for qw(clearer predicate);

	$options{traits} //= [];
	push @{$options{traits}}, 'Chained' unless $options{traits} ~~ 'Chained';

	$meta->add_attribute($_, %options) for @$attrs;
}

*import = __PACKAGE__->build_importer($moose_import, sub {
	my ($self, $opts, $args) = @_;
	my $into = $opts->{into};
	
	my $meta_name = 'meta';
	if ((my $i = firstidx { $_ eq '-meta_name' } @$args) >= 0) {
		$meta_name = $args->[$i+1];
	}

	# Mutable.
	if ((my $idx = firstidx { $_ eq '-mutable' } @$args) >= 0) {
		splice @$args, $idx, 1;
	}
	else {
		after_runtime {
			$into->$meta_name->make_immutable;
		};
	}
});

sub import_base {
	my ($self, $into) = @_;

	# use common::sense
	strict->unimport;
	warnings->unimport;
	common::sense->import;

	# Require a perl version.
	feature->import(FEATURE_VERSION);

	# Cleanliness
	$into->true::import;
}

sub _get_extra_argument {
	my $args = shift;

	if (my $extra = first { ref $_ eq 'HASH' } @$args) {
		return $extra;
	}

	my $extra = {};
	push $args, $extra;
	$extra;
}

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

L<Moose>, L<common::sense>, L<namespace::autoclean>, L<true>
