package App::KADR::Term::StatusLine::Freeform;
use v5.10;
use Moose;
use common::sense;

with 'App::KADR::Term::StatusLine';

has 'value' => (is => 'rw', isa => 'Str', predicate => 'has_value');

sub _to_text { $_[0]->value }

sub update {
	my ($self, $value) = @_;
	$self->value($value);
	$self->update_term;
}

__PACKAGE__->meta->make_immutable;
