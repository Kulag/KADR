package App::KADR::AniDB::UDP::Meta::Method::Request::Stringifier;

use aliased 'App::KADR::AniDB::UDP::Meta::Attribute::Trait::Field';
use App::KADR::Moose -mutable => 1;
use List::AllUtils qw(part);
use Scalar::Util qw(weaken);
use Try::Tiny;

no strict;
no warnings;
use common::sense;

extends 'Moose::Meta::Method', 'Class::MOP::Method::Inlined';

sub new {
	my $class = shift;
	my %options = @_ == 1 ? %{+shift} : @_;

	$class->throw_error('You must pass a hash of options', data => $options{options})
		unless ref $options{options} eq 'HASH';

	my $self = bless {field_trait => Field}, $class;

	do { $self->{$_} = $options{$_} if exists $options{$_} }
		for qw(associated_metaclass package_name name options definition_context field_trait);

	weaken $self->{associated_metaclass};

	$self->_initialize_body;

	$self;
}

sub options { $_[0]{options} }

sub _compile_code {
	my ($self, %args) = @_;
	try {
		$self->SUPER::_compile_code(%args);
	}
	catch {
		my $source = join "\n", @{ $args{source} };
		$self->throw_error(
			"Could not compile the stringifier:\n\n$source\n\nbecause:\n\n$_",
			error => $_,
			data  => $source,
		);
	}
}

sub _initialize_body {
	my $self = shift;

	my $meta     = $self->associated_metaclass;
	my $type     = $meta->req_type;
	my @fields   = grep { $_->does($self->{field_trait}) } $meta->get_all_attributes;
	my @part_req = part { $_->is_required } @fields;
	my @optional = @{ $part_req[0] };
	my @required = @{ $part_req[1] };

	my @source = (
		'sub {',
			(@fields
				? (
					'my $self = shift;',
					$self->_generate_required('$self', $type, @required),
					$self->_generate_optional('$self', @part_req),
					$self->_generate_return('$self', $type, @part_req),
				)
				: q{"} . $type . q{\n"}
			),
		'}',
	);

	warn join "\n", @source if $self->options->{debug} || $ENV{KADR_REQ_STR_DB};

	$self->{body} = $self->_compile_code(source => \@source);
}

sub _generate_encoded_field {
	my ($self, $inv, $field) = @_;
	# TODO: Add type encoding
	$inv . '->' . $field->get_read_method;
}

sub _generate_field_contents {
	my ($self, $inv, $field) = @_;
	$field->name . '=\' . ' . $self->_generate_encoded_field($inv, $field);
}

sub _generate_if_field_exists {
	my ($self, $inv, $field, @block) = @_;
	('if (' . $inv . '->' . $field->predicate . ') {', @block, '}');
}

sub _generate_optional {
	my ($self, $inv, $optional, $required) = @_;

	return unless @$optional;

	(@$required
		? (
			';',
			map { $self->_generate_optional_field('$self', '$str', $_, 1) } @$optional
		)
		: (
			'my @params;',
			(map { $self->_generate_optional_field('$self', '@params', $_, 0) } @$optional),
		)
	);
}

sub _generate_optional_field {
	my ($self, $inv, $out, $field, $has_one) = @_;

	my $contents = $self->_generate_field_contents($inv, $field) . ';';
	$self->_generate_if_field_exists($inv, $field,
		($has_one ? $out . ' .= \'&' : 'push ' . $out . ', \'') . $contents);
}

sub _generate_required {
	my ($self, $inv, $type, @required) = @_;

	return unless @required;

	(
		'my $str = \'' . $type,
		' ' . $self->_generate_required_field($inv, $required[0]),
		(map { ' . \'&' . $self->_generate_required_field($inv, $_) } @required[1 .. $#required]),
	);
}

sub _generate_required_field {
	my ($self, $inv, $field) = @_;
	$self->_generate_field_contents($inv, $field);
}

sub _generate_return {
	my ($self, $inv, $type, $optional, $required) = @_;

	(
		(@$required ? '$str' : ()),
		(@$optional
			? (
				(@$required
					? q{ . join('&', @params) . "\n"}
					: q{@params ? '} . $type . q{ ' . join('&', @params) . "\n" : "} . $type . q{\n"}
				),
			)
			: ()
		)
	);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
