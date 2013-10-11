package App::KADR::AniDB::Meta::Attribute::ContentReference::Builder;
# ABSTRACT: Builder for attributes that refer to other content

use App::KADR::Moose;
use Carp ();
use Lingua::EN::Inflect qw(WORDLIST);
use strict 'refs';

extends 'App::KADR::Meta::Method::AttrInlined';

sub accessor_type {'builder'}

method _always_defined($key) {
	my $tc = $key->type_constraint;
	!($tc && $tc->is_a_type_of('Maybe'));
}

method _inline_body {
	my $attr      = $self->attribute;
	my $metaclass = $attr->associated_class;
	my @key_names = @{ $attr->keys };
	my @keys      = map { $metaclass->find_attribute_by_name($_) } @key_names;
	my @source;

	for my $key (@keys) {
		my $name = $key->name;
		my $val  = '$_[0]->' . $key->get_read_method;

		if ($self->_always_defined($key)) {
			return (
				@source,
				$self->_inline_call_client('$_[0]', "$name => $val"),
			);
		}

		push @source, (
			"if (my \$id = $val) {",
				'return ' . $self->_inline_call_client('$_[0]', "$name => \$id"),
			'}',
		);

	}

	(
		@source,
		'Carp::croak q{One of '
			. WORDLIST(@key_names, { conj => 'or' })
			. ' must be defined};',
	);
}

method _inline_call_client($inv, $args) {
	"$inv->client->" . $self->attribute->client_method . "($args);";
}

__PACKAGE__->meta->make_immutable(replace_constructor => 1);

=head1 EXTENDS

L<App::KADR::Meta::Method::AttrInlined>

=head1 SEE ALSO

L<App::KADR::AniDB::Meta::Attribute::ContentReference>
