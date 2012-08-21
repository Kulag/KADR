package App::KADR::Term::StatusLine::XofX;
use v5.10;
use Moose;
use Moose::Util::TypeConstraints;
use common::sense;
use Method::Signatures;

with 'App::KADR::Term::StatusLine';

subtype 'App::KADR::Term::StatusLine::XofX::Count' => as 'CodeRef';
coerce 'App::KADR::Term::StatusLine::XofX::Count' => from 'Int' => via { my $int = $_; sub { $int } };
coerce 'App::KADR::Term::StatusLine::XofX::Count' => from 'ScalarRef' => via { my $ref = $_; sub { $$ref } };

subtype 'App::KADR::Term::StatusLine::XofX::Format' => as 'CodeRef';
coerce 'App::KADR::Term::StatusLine::XofX::Format' => from 'Str' => via {
	given($_) {
		when('percent') {
			return sub { 
				my $self = shift;
				sprintf('%.0f%%', $self->current_item_count->() / $self->total_item_count->() * 100);
			};
		}
		when('x/x') {
			return sub {
				my $self = shift;
				sprintf('%d/%d', $self->current_item_count->(), $self->total_item_count->());
			};
		}
		default {
			return sub {
				my $self = shift;
				sprintf($_, $self->current_item_count->(), $self->total_item_count->());
			};
		}
	}
};
coerce 'App::KADR::Term::StatusLine::XofX::Format' => from 'CodeRef' => via { return $_ };

has 'current_item_count' => (is => 'rw', isa => 'App::KADR::Term::StatusLine::XofX::Count', coerce => 1, default => 0);
has 'format' => (is => 'rw', isa => 'App::KADR::Term::StatusLine::XofX::Format', coerce => 1, default => 'x/x');
has 'total_item_count' => (is => 'rw', isa => 'App::KADR::Term::StatusLine::XofX::Count', required => 1, coerce => 1);
has 'update_label' => (is => 'rw', predicate => 'has_update_label', trigger => sub { $_[0]->update_term });
has 'update_label_separator' => (is => 'rw', isa => 'Str', default => ' ');

around 'current_item_count' => sub {
	my($orig, $self, $update) = @_;
	if($update) {
		given($update) {
			when('++') {
				$self->$orig($self->$orig->() + 1);
			}
			when(/\+=(\d+)/) {
				$self->$orig($self->$orig->() + $1);
			}
			default {
				$self->$orig($update);
			}
		}
	}
	else {
		return $self->$orig;
	}
};

after 'total_item_count' => sub {
	my($self, $update) = @_;
	if($update) {
		$self->update_term;
	}
};

sub BUILD {
	my $self = shift;
	$self->update_term;
}

method _to_text {
	my $text = $self->format->($self);
	$text .= $self->update_label_separator . $self->update_label if $self->has_update_label;
	$text
}

sub incr {
	my ($self, $by) = @_;
	$self->current_item_count($self->current_item_count->() + ($by // 1));
	$self;
}

method update($item_count, $update_label?) {
	$self->current_item_count($item_count);
	if(defined $update_label) {
		$self->update_label($update_label);
	}
}

__PACKAGE__->meta->make_immutable;
1;