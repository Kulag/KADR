package App::KADR::Moose::Exporter;
# Extensions to Moose::Exporter's functionality

use common::sense;
use App::KADR::Moose::Exporter::Util -all;
use Class::Load qw(load_class);
use List::AllUtils qw(firstidx);
use Method::Signatures;
use Moose ();
use true;

use aliased 'Moose::Exporter', 'MX';

my %export_spec;
my %import_params;

method build_import_methods($class: %args) {
	my $pkg = $args{exporting_package} ||= caller;
	$export_spec{$pkg} = \%args;

	load_class $_ for ref $args{also} ? @{ $args{also} } : $args{also};

	# Check if import should be installed, and prevent MX from installing its.
	my $install_import = grep { $_ eq 'import' } @{ $args{install} };
	$args{install} = [ grep { $_ ne 'import' } @{ $args{install} } ];

	my @subs = MX->build_import_methods(%args);
	$subs[0] = $class->_make_import($subs[0], %args);

	# Install import
	my $stash = Class::MOP::Package->initialize($pkg);
	if ($install_import && !$stash->has_package_symbol('&import')) {
		$stash->add_package_symbol('&import', $subs[0]);
	}

	@subs;
}

method get_import_params($class: $for_class, $exporting_package = caller) {
	+{ map { %{ $import_params{$for_class}{$_} } }
			($exporting_package, $class->_follow_also($exporting_package)) };
}

sub import {
	common::sense->import;
	true->import;
	goto &setup_import_methods if @_ > 1;
}

method setup_import_methods($class: %args) {
	$args{exporting_package} ||= caller;

	$class->build_import_methods(%args, install => [qw(import unimport init_meta)]);
}

method _follow_also($class: $for_class) {
	state $cache = {};
	@{ $cache->{$for_class} //= [ MX->_follow_also($for_class) ] };
}

method _make_import($class: $mx_import, %args) {
	my @exports_from = (
		$args{exporting_package},
		$class->_follow_also($args{exporting_package}));

	my (@after, @before, @params, %param_classes);
	for my $exporter (@exports_from) {
		push @before, $exporter if $exporter->can('before_import');
		unshift @after, $exporter if $exporter->can('after_import');
		push @params, @{ $export_spec{$exporter}{import_params} };

		push @{ $param_classes{$_} ||= [] }, $exporter
			for @{ $export_spec{$exporter}{import_params} };
	}

	return $mx_import unless @after or @before or @params;

	sub {
		my $caller = Moose::Exporter::_get_caller(@_) if @params or @after;

		if (@params) {
			my $stripped = strip_import_params(\@_, @params);

			for my $k (keys %$stripped) {
				for my $class (@{ $param_classes{$k} }) {
					$import_params{$caller}{$class}{$k} = $stripped->{$k};
				}
			}
		}

		get_sub_exporter_into_hash(\@_)->{into} ||= $caller if @after;

		$_->before_import($caller, @_) for @before;
		goto &$mx_import unless @after;
		&$mx_import;

		my $meta = Class::MOP::class_of($caller);
		$_->after_import($meta, @_) for @after;
	};
}

=head1 DESCRIPTION

L<App::KADR::Moose::Exporter> is a quick wrapper over L<Moose::Exporter> which
adds after/before method modifiers (after a fashion), and the ability to
specify additional import parameters.

This could be expanded to use an Exporter metaclass and Moose's existing method
modifiers, but this gets the jobs done for now.

=head1 IMPORT

L<App::KADR::Moose::Exporter> imports L<common::sense> and L<true> into the
caller, and calls C<setup_import_methods> with its arguments if given any.

=head1 CLASS METHODS

=head2 C<build_import_methods>

As L<Moose::Exporter>, with the following additions which inherit via C<also>:

Modules in C<also> are loaded for you.

	import_params => ['foo'],

	use MooseX::Module -foo => 'bar';

Parameters specified in C<import_params> (without leading dashes) will be
collected and accessible via C<get_import_params>.

If your module has subs C<before_import> and/or C<after_import>, they will be
called around L<Moose::Exporter>'s import method like Moose's method modifiers.
The before modifier is given the caller class before its other arguments.
The after modifier is given the caller metaobject before its other arguments.

=head2 C<get_import_params>

	my $params = App::KADR::Moose::Exporter->get_import_params($for_class);
	my $params = App::KADR::Moose::Exporter->get_import_params($for_class,
		$exporting_package);

Get parameters passed to import of this module or one using it via C<also>.
Parameters collected due to modules included via C<also> are included in the
hash as if they were superclasses.

=head2 C<setup_import_methods>

Identical to L<Moose::Exporter>.

=head1 SEE ALSO

L<Moose::Exporter>
