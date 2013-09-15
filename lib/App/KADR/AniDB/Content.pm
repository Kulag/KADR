package App::KADR::AniDB::Content;
# ABSTRACT: Moose with content extras

use App::KADR::AniDB::Types qw(ID MaybeID);
use Method::Signatures;

use aliased 'App::KADR::AniDB::Meta::Attribute::Field';
use aliased 'App::KADR::AniDB::Meta::Attribute::ContentReference';
use aliased 'App::KADR::AniDB::Role::Content::Referencer';

func field($meta, $name, %opts) {
	$opts{definition_context} = {
		Moose::Util::_caller_info,
		context => 'field declaration',
		type    => 'class',
	};
	push @{ $opts{traits} ||= [] }, Field;

	$meta->add_attribute($_, %opts) for ref $name ? @$name : $name;
}

func refer($meta, $name, $keys, %opts) {
	Moose::Util::apply_all_roles($meta, Referencer);

	$opts{definition_context} = {
		Moose::Util::_caller_info,
		context => 'refer declaration',
		type    => 'class',
	};
	$opts{keys} = ref $keys ? $keys : [$keys];
	push @{ $opts{traits} ||= [] }, ContentReference;

	$meta->add_attribute($name, %opts);
}

use App::KADR::Moose::Exporter
	also             => 'App::KADR::Moose',
	as_is            => [qw(ID MaybeID)],
	base_class_roles => ['App::KADR::AniDB::Role::Content'],
	with_meta        => [qw(field refer)];

=head1 SYNOPSIS

	use App::KADR::AniDB::Content;

	field 'fid', ...;
	refer 'file' => 'fid', ...;

=head1 DESCRIPTION

Exports L<App::KADR::Moose> with L<App::KADR::AniDB::Role::Content>.
Exports C<field> and C<refer> to assist in declaring content classes.
Reexports C<ID> and C<MaybeID> from L<App::KADR::AniDB::Types>

=head1 FUNCTIONS

=head2 C<field>

	field 'name', isa => Str, ...;

Add a field (attribute with Field trait) to your class. See L<Moose>.

=head2 C<refer>

	refer 'foo' => 'foo_id', ...;
	refer 'bar' => ['bar_id', 'foo_id'], ...;

Add a memoized relation lookup to another content. If multiple identifiers
are provided, the first true one is used.

Adding a reference applies L<App::KADR::AniDB::Role::Content::Referencer> to
your class.
