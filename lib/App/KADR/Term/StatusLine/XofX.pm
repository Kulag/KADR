package App::KADR::Term::StatusLine::XofX;
use v5.10;
use Moose;

extends 'App::KADR::Term::StatusLine::Fractional';

sub current_item_count { shift->current(@_) }
sub total_item_count { shift->max(@_) }

around BUILDARGS => sub {
	my $orig = shift;
	my $class = shift;
	my $args = $class->$orig(@_);

	if (my $current = delete $args->{current_item_count}) {
		$args->{current} = $current;
	}

	if (my $max = delete $args->{total_item_count}) {
		$args->{max} = $max;
	}

	$args;
};

__PACKAGE__->meta->make_immutable;
1;