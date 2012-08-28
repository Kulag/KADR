package App::KADR::Term::StatusLine::Freeform;
use v5.10;
use Moose;
use common::sense;
use Method::Signatures;

with 'App::KADR::Term::StatusLine';

has 'value' => (is => 'rw', isa => 'Str', predicate => 'has_value');

method _to_text {
	return $self->value;
}

method update(Str $value) {
	$self->value($value);
	$self->update_term;
}

__PACKAGE__->meta->make_immutable;
1;