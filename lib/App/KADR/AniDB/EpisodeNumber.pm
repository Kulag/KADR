package App::KADR::AniDB::EpisodeNumber;
# ABSTRACT: A set of AniDB episode numbers

use v5.10;
use App::KADR::AniDB::EpisodeNumber::Range;
use common::sense;
use Carp qw(croak);
use List::Util qw(sum);
use overload
	fallback => 1,
	'""'     => 'stringify',
	'&'      => 'intersection';
use Scalar::Util qw(blessed);

sub range_class() {'App::KADR::AniDB::EpisodeNumber::Range'}

my %cache;

sub contains {
	my $other = blessed $_[1] ? $_[1] : $_[0]->parse($_[1]);

	$_[0]{_contains}{$other} //= $other->{_in}{ $_[0] }
		//= $_[0]->intersection($other) eq $other;
}

sub count {
	my ($self, $type) = @_;
	my @ranges
		= defined $type
		? grep { $_->tag eq $type } $self->ranges
		: $self->ranges;

	@ranges ? sum map { $_->count } @ranges : 0;
}

sub in {
	$_[0]{_in}{ $_[1] } //= $_[1]{_contains}{ $_[0] }
		//= $_[0]->intersection($_[1]) eq $_[0];
}

sub in_ignore_max {
	$_[0]{in_ignore_max}{ $_[1] } //= do {
		my $intersection = $_[0]->intersection($_[1]);
		my ($first_range) = $_[0]->ranges;

		$intersection eq $_[0]
			|| $intersection eq $first_range->tag . $first_range->{min};
	};
}

sub intersection {
	my ($self, $other) = @_;

	$other = $self->parse($other) unless blessed $other;

	if ($other->isa(__PACKAGE__)) {
		return $self->new(
			map {
				my $other = $_;
				map { $_->intersection($other) } $self->ranges
			} $other->ranges
		);
	}

	if ($other->isa(range_class)) {
		return $self->new(map { $_->intersection($other) } $self->ranges);
	}

	die 'Unable to handle type: ' . ref $other;
}

sub new {
	my $class = ref $_[0] ? ref shift : shift;

	my @ranges = sort {
		my $t = $a->tag cmp $b->tag;
		$t == 0 ? $_->{min} <=> $b->{min} : $t;
	} grep {defined} @_;

	bless { ranges => \@ranges }, $class;
}

sub padded {
	my ($self, $padding) = @_;
	my $range_padded
		= ref $padding eq 'HASH' ? sub { $_->padded($padding->{ $_->tag }) }
		: $padding =~ /^\d+$/    ? sub { $_->padded($padding) }
		:                          croak 'Invalid padding configuration';

	join ',', map &$range_padded, $_[0]->ranges;
}

sub parse {
	$cache{ $_[1] } //= do {
		my $class = ref $_[0] || $_[0];
		my $range_class = $class->range_class;

		$class->new(map { $range_class->parse($_) } split /,/, $_[1]);
	};
}

sub ranges { @{ $_[0]{ranges} } }

sub stringify { $_[0]{stringify} //= join ',', $_[0]->ranges }

0x6B63;

=head1 SYNOPSIS

use aliased 'App::KADR::AniDB::EpisodeNumber';

my $episode = EpisodeNumber->parse('05');
my $episodes = EpisodeNumber->parse('1-13,C1-C2,S1');

$episode eq '5';
$episode->stringify eq '5';
$episodes eq '1-13,C1-C2,S1';

$episode->in($episodes); # true

$episodes->contains($episode) # true
$episodes->contains('12-13') # true
$episodes->contains('13-14') # false

=head1 DESCRIPTION

Provides methods for calculation on episode number ranges.

=head1 METHODS

=head2 C<count>

	my $all_count = $epno->count;
	my $type_count = $epno->count($episode_type_tag);

Count of episodes represented by this episode number,
optionally filtered by type.

=head2 C<contains>

	my $epno = EpisodeNumber->parse('1-10');

	# True
	$epno->contains('5');
	$epno->contains('9-10');
	$epno->contains(EpisodeNumber->parse('1'));

	# False
	$epno->contains('S1');
	$epno->contains('10-11');

Check if this episode number contains another. Equivalent to C<in> with its arguments swapped, but slightly slower. This method is memoized.

=head2 C<in>

	# True
	EpisodeNumber->parse('5')->in('1-10');
	EpisodeNumber->parse('9-10')->in('1-10');

	# False
	EpisodeNumber->parse('S1')->in('1-10');
	EpisodeNumber->parse('10-11')->in('1-10');

Check if another episode number contains this one. Equivalent to C<contains>, with its arguments swapped, but slightly faster. This method is memoized.

=head2 C<in_ignore_max>

	# True
	EpisodeNumber->parse('5')->in('1-10');
	EpisodeNumber->parse('9-10')->in('1-10');
	EpisodeNumber->parse('9-10')->in('1,3,5,7,9');
	EpisodeNumber->parse('10-11')->in('1-10');

	# False
	EpisodeNumber->parse('S1')->in('1-10');

Check if another episode number which is broken contains this one.
Use this to work around MULTIPLE MYLIST ENTRIES incorrectly returning only the
first applicable episode numbers from the files it represents.
This method is memoized.

=head2 C<intersection>

	my $epno = $epno->intersection('5-6');
	my $epno = $epno->intersection(EpisodeNumber->parse('1'));

Calculate the intersection of this episode number and another.

=head2 C<new>

	my $epno = EpisodeNumber->new; # Empty
	my $epno = EpisodeNumber->new(Range->new('epno', 1, 1, ''), ...);

Create episode number.

=head2 C<padded>

	my $string = EpisodeNumber->parse('1,S1')->padded(2); # 01,S01
	my $string = EpisodeNumber->parse('1,S1')->padded({'' => 2, S => 1}); # 01,S1

Turn episode number into a zero-padded string.

head2 C<parse>

	my $epno = $class->parse('1-10', ...);
	my $epno = $epno->parse('1-10', ...)

Parse episode number. This static method is memoized.

=head2 C<stringify>

	my $string = "$epno";
	my $string = $epno->stringify;

Turn episode number into a string. This method is memoized.
