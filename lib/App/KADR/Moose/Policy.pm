package App::KADR::Moose::Policy;
use v5.14;
use common::sense;
use Const::Fast;
use Hook::AfterRuntime;
use List::AllUtils qw(firstidx);
use Moose 1.9900               ();
use Moose::Exporter            ();
use MooseX::Attribute::Chained ();
use MooseX::AttributeShortcuts ();
use MooseX::HasDefaults::RW    ();
use MooseX::StrictConstructor 0.19 ();
use namespace::autoclean;
use true;

const my @ATTRIBUTE_TRAITS => qw(
	MooseX::AttributeShortcuts::Trait::Attribute
	MooseX::HasDefaults::Meta::IsRW
	MooseX::Traits::Attribute::Chained
);
const my $FEATURE_VERSION => ':5.14';
const my @PARAM_NAMES     => qw(noclean mutable);

my ($import, $unimport, $init_meta) = Moose::Exporter->build_import_methods(
	also            => [qw(MooseX::StrictConstructor)],
	class_metaroles => { attribute => [@ATTRIBUTE_TRAITS] },
	install         => ['unimport'],
	role_metaroles  => { applied_attribute => [@ATTRIBUTE_TRAITS] },
);

my $import_params;

sub import {
	$_[0]->strip_import_params(\@_);

	goto &$import;
}

sub init_meta {
	my ($class, %args) = @_;
	my $params = $import_params || delete $args{moose_policy_params};
	undef $import_params;

	my $for_class = $args{for_class};
	my $meta = $init_meta->($class, %args);

	# use common::sense
	# This needs to happen after Moose sets strict and warnings.
	strict->unimport;
	warnings->unimport;
	common::sense->import;

	# Require a perl version.
	feature->import($FEATURE_VERSION);

	# Cleanliness
	$for_class->true::import;

	unless ($params->{noclean}) {
		namespace::autoclean->import(-cleanee => $for_class);
	}

	unless ($params->{mutable} || $meta->isa('Moose::Meta::Role')) {
		after_runtime {
			Class::MOP::class_of($for_class)->make_immutable;
		};
	}

	Class::MOP::class_of($for_class);
}

sub strip_import_params {
	my ($class, $args) = @_;

	$import_params
		= { map { $_ => _strip_param($args, '-' . $_) } @PARAM_NAMES };

	return;
}

sub _strip_param {
	my ($args, $name) = @_;
	my $i = firstidx { $_ eq $name } @$args;

	return undef unless $i >= 0;

	my $param = $args->[ $i + 1 ];

	splice @$args, $i, 2;

	$param;
}

=head1 NAME

App::KADR::Moose::Policy - Moose policy for KADR

=head1 SYNPOSIS

	use Moose;
	use App::KADR::Moose::Policy;

=head1 DESCRIPTION

L<App::KADR::Moose::Policy> bundles default configuration for KADR's Moose
classes and roles.

Moose's default strictures and warnings are replaced with L<common::sense>.

Perl version 5.14 is required.

L<true> is used to remove the need for returning true in user modules.

L<namespace::autoclean> is imported into your module by default.

Moose classes are made immutable by default.

L<MooseX::AttributeShortcuts>, L<MooseX::HasDefaults::RW>,
and L<MooseX::Attribute::Chained> are applied to your attributes.

L<MooseX::StrictConstructor> is enabled.

=head1 CLASS METHODS

L<App::KADR::Moose::Policy> implements the following class methods.

=head2 C<import>

	use App::KADR::Moose::Policy;
	use App::KADR::Moose::Policy -mutable => 1, -noclean => 1;

Import policy into calling module.
Set -mutable => true to disable automatic immutability.
Set -noclean => true to disable namespace::autoclean.

=head2 C<strip_import_params>

	sub my_import {
		App::KADR::Moose::Policy->strip_import_params(\@_);

		...
	}

Strip parameters for L<App::KADR::Moose::Policy> from your import when
chaining Moose::Exporter imports.

=head1 SEE ALSO

L<App::KADR::Moose>, and L<App::KADR::Moose::Role>

=cut
