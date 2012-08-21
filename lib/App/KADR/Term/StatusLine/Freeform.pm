package App::KADR::Term::StatusLine::Freeform;
use v5.10;
use Moose;
use common::sense;
use Method::Signatures;

with 'App::KADR::Term::StatusLine';

has 'value' => (is => 'rw', isa => 'Str', predicate => 'has_value');

after 'value' => sub {
	my($self, $update) = @_;
	if($update) {
		shift->update_term;
	}
};

sub BUILD {
	my $self = shift;
	if($self->has_value) {
		$self->update_term;
	}
}

method _to_text {
	return $self->value;
}

method update(Str $value) {
	$self->value($value);
}

__PACKAGE__->meta->make_immutable;
1;