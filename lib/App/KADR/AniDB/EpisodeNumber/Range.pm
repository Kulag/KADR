package App::KADR::AniDB::EpisodeNumber::Range;
# ABSTRACT: A range of AniDB episode numbers

use v5.10;
use common::sense;
use Carp qw(croak);
use overload
	fallback => 1,
	'""' => 'stringify';
use Scalar::Util qw(blessed looks_like_number);

use App::KADR::AniDB::EpisodeNumber;

my %cache;
my $tag_range_re = qr/^ ([a-xA-Z]*) (\d+) (?: - \g{1} (\d+) )? $/x;

sub count { $_[0]{max} - $_[0]{min} + 1 }

sub intersection {
	my ($self, $other) = @_;

	# Return something sane if this range gets called with something other than another range.
	return App::KADR::AniDB::EpisodeNumber->new($self)->intersection($other)
		unless blessed $other && $other->isa(__PACKAGE__);

	return if $self->{tag} ne $other->{tag};

	my $min = $self->{min} > $other->{min} ? $self->{min} : $other->{min};
	return unless defined $min;

	my $max = $self->{max} < $other->{max} ? $self->{max} : $other->{max};

	return if !defined $max || $max < $min || $min > $max;

	$self->new($min, $max, $self->{tag});
}

sub new {
	# my ($class, $min, $max, $tag) = @_;
	return unless my $min = int $_[1];
	($min, my $max) = sort { $a <=> $b } $min, int($_[2]) || $min;

	$cache{$_[3]}->{$min}{$max} //= do {
		my $class = ref $_[0] || $_[0];
		bless {min => $min, max => $max, tag => $_[3]}, $class;
	};
}

sub padded {
	my ($self, $padding) = @_;
	my $format = '%0' . ($padding || 1) . 'd';

	$self->{tag} . (
		$self->{max} > $self->{min}
		? sprintf($format . '-' . $format, $self->{min}, $self->{max})
		: sprintf($format, $self->{min})
	);
}

sub parse {
	my ($class, $string) = @_;
	$class = ref $class if ref $class;

	croak 'Error parsing episode number range'
		unless $string =~ $tag_range_re;

	$class->new($2, $3, $1);
}

sub stringify {
	$_[0]{stringify} //= $_[0]{tag} . $_[0]{min} . ($_[0]{max} > $_[0]{min} ? '-' . $_[0]{tag} . $_[0]{max} : '');
}

sub tag { $_[0]{tag} }

0x6B63;
