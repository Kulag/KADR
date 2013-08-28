package App::KADR::Moose::Policy;
# ABSTRACT: Moose policy for KADR

use v5.14;
use common::sense;
use Const::Fast;
use Hook::AfterRuntime;
use Moose 1.9900 ();
use MooseX::AlwaysCoerce       ();
use MooseX::Attribute::Chained ();
use MooseX::AttributeShortcuts ();
use MooseX::HasDefaults::RW    ();
use MooseX::StrictConstructor 0.19 ();
use namespace::autoclean ();
use true;

use aliased 'App::KADR::Moose::Exporter', 'MX';

# XXX: MooseX::HasDefaults::RW doesn't set role_metaroles.
const my @ATTRIBUTE_TRAITS => qw(
	MooseX::HasDefaults::Meta::IsRW
	MooseX::Traits::Attribute::Chained
);
const my $FEATURE_VERSION => ':5.14';
const my @PARAM_NAMES     => qw(noclean mutable);

MX->setup_import_methods(
	also => [
		'MooseX::AlwaysCoerce', 'MooseX::AttributeShortcuts',
		'MooseX::StrictConstructor',
	],
	class_metaroles => { attribute         => [@ATTRIBUTE_TRAITS] },
	import_params   => [qw(noclean mutable)],
	role_metaroles  => { applied_attribute => [@ATTRIBUTE_TRAITS] },
);

sub after_import {
	my ($class, $meta, @args) = @_;
	my $for_class = $meta->name;
	my $params    = MX->get_import_params($for_class);

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

	$meta;
}

=head1 SYNPOSIS

	use Moose;
	use App::KADR::Moose::Policy;

	# Implicit
	# use common::sense;
	# use namespace::autoclean;
	# use true;

	# Implicitly is 'rw' and traits Chained.
	has 'attr';

	# Implicit
	__PACKAGE__->meta->make_immutable;


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

L<MooseX::AlwaysCoerce> is enabled.

L<MooseX::StrictConstructor> is enabled.

=head1 CLASS METHODS

L<App::KADR::Moose::Policy> implements the following class methods.

=head1 IMPORT PARAMETERS

=head2 C<-mutable>

Set to disable automatic immutability.

=head2 C<-noclean>

Set to disable namespace::autoclean.

=head1 STACKING

When stacking this module, you ought to use L<App::KADR::Moose::Exporter>.

=head1 SEE ALSO

L<App::KADR::Moose>, and L<App::KADR::Moose::Role>,
L<App::KADR::Moose::Exporter>
