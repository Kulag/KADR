package App::KADR::Moose;
use v5.14;
use Hook::AfterRuntime;
use Moose ();
use Moose::Exporter ();
use MooseX::Attribute::Chained ();
use namespace::autoclean;
use true;

use common::sense;

my $FEATURE_VERSION = ':14';

my ($moose_import) = Moose::Exporter->setup_import_methods(
	with_meta => [qw(has)],
	also => [qw(Moose)],
	install => [qw(unimport init_meta)],
);

sub has($;@) {
	my $meta = shift;
	my $name = shift;

	Moose->throw_error('Usage: has \'name\' => ( key => value, ... )')
		if @_ % 2 == 1;

	my %options = (definition_context => Moose::Util::_caller_info(), @_);
	my $attrs = ref $name eq 'ARRAY' ? $name : [$name];

	$options{is} //= 'rw';
	$options{traits} //= [];
	push @{$options{traits}}, 'Chained' unless $options{traits} ~~ 'Chained';

	$meta->add_attribute($_, %options) for @$attrs;
}

sub import {
	my ($self, $opts) = @_;
	my $into = $opts->{into} ||= scalar caller;
	my $mutable = delete $opts->{mutable};

	feature->import($FEATURE_VERSION);

	namespace::autoclean->import(-cleanee => $into);
	$into->true::import;

	unless ($mutable) {
		after_runtime {
			$into->meta->make_immutable;
		};
	}

	goto &$moose_import;
}
