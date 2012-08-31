package App::KADR::AniDB::EpisodeNumber;
use v5.10;
use common::sense;
use overload
	fallback => 1,
	'""' => 'stringify',
	'&' => 'intersection';
use Scalar::Util qw(blessed);
use Sub::Exporter::Util;
use Sub::Exporter -setup => {
	exports => { 'EpisodeNumber' => Sub::Exporter::Util::curry_method('from_string') },
	groups => { default => [ qw(EpisodeNumber) ]}
};

use App::KADR::AniDB::EpisodeNumber::Range;

sub range_class() { 'App::KADR::AniDB::EpisodeNumber::Range' }

my %cache;

sub contains {
	my $other = blessed $_[1] ? $_[1] : $_[0]->from_string($_[1]);

	$_[0]{_contains}{$other} //= $other->{_in}{$_[0]} //=
		$_[0]->intersection($other) eq $other;
}

sub from_string {
	$cache{join ',', @_[1..$#_]} //= do {
		my $class = ref $_[0] ? ref shift : shift;
		my $range_class = $class->range_class;

		$class->new(
			map { $range_class->parse($_) or die 'Error parsing episode number' } map { split /,/ } @_
		)
	};
}

sub in {
	$_[0]{_in}{$_[1]} //= $_[1]{_contains}{$_[0]} //=
		$_[0]->intersection($_[1]) eq $_[0];
}

sub intersection {
	my ($self, $other) = @_;

	$other = $self->from_string($other) unless blessed $other;

	if ($other->isa(__PACKAGE__)) {
		return $self->new(
			map {
				my $other = $_;
				map { $_->intersection($other) } $self->ranges
			} $other->ranges
		);
	}

	if ($other->isa(range_class)) {
		return $self->new( map { $_->intersection($other) } $self->ranges );
	}

	die 'Unable to handle type: ' . ref $other;
}

sub new {
	my $class = ref $_[0] ? ref shift : shift;

	my @ranges = grep {defined} @_;

	bless {ranges => \@ranges}, $class;
}

sub ranges {
	@{ $_[0]{ranges} }
}

sub stringify {
	$_[0]->{stringify} //=
		join ',', sort { my $t = $a->{tag} cmp $b->{tag}; $t == 0 ? $_->{min} <=> $b->{min} : $t } $_[0]->ranges;
}

0x6B63;

=head1 NAME

App::KADR::AniDB::EpisodeNumber - AniDB episode number range handling

=head1 SYNOPSIS

use App::KADR::AniDB::EpisodeNumber;

my $episode = EpisodeNumber('05');
my $episodes = EpisodeNumber('1-13,C1-C2,S1');

$episode eq '5';
$episode->stringify eq '5';
$episodes eq '1-13,C1-C2,S1';

$episode->in($episodes); # true

$episodes->contains($episode) # true
$episodes->contains('12-13') # true
$episodes->contains('13-14') # false

=head1 DESCRIPTION

Provides methods for calculation on episode number ranges.

=head1 EXPORTS

=head2 C<EpisodeNumber>

A shortcut for App::KADR::AniDB::EpisodeNumber->L<from_string>.

=head1 METHODS

=head2 C<contains>

	my $epno = EpisodeNumber('1-10');

	# True
	$epno->contains('5');
	$epno->contains('9-10');
	$epno->contains(EpisodeNumber('1'));

	# False
	$epno->contains('S1');
	$epno->contains('10-11');

Check if this episode number contains another. Equivalent to C<in> with its arguments swapped, but slightly slower. This method is memoized.

head2 C<from_string>

	my $epno = $class->from_string('1-10', ...);
	my $epno = $epno->from_string('1-10', ...)

Parse episode number. This static method is memoized.

=head2 C<in>

	# True
	EpisodeNumber('5')->in('1-10');
	EpisodeNumber('9-10')->in('1-10');

	# False
	EpisodeNumber('S1')->in('1-10');
	EpisodeNumber('10-11')->in('1-10');

Check if another episode number contains this one. Equivalent to C<contains>, with its arguments swapped, but slightly faster. This method is memoized.

=head2 C<intersection>

	my $epno = $epno->intersection('5-6');
	my $epno = $epno->intersection(EpisodeNumber('1'));

Calculate the intersection of this episode number and another.

=head2 C<new>

	my $epno = App::KADR::AniDB::EpisodeNumber->new(App::KADR::AniDB::EpisodeNumber::Range->new('epno', 1, 1, ''), ...);

Create episode number.

=head2 C<stringify>

	my $string = "$epno";
	my $string = $epno->stringify;

Turn episode number into a string. This method is memoized.
