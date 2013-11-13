package App::KADR::Collate::ASCII;
# ABSTRACT: Case-insensitive ASCII-betical collation

use common::sense;

sub new { bless \(do { my $a = 1 }), shift }

sub sort {
	shift;

	return sort { lc $a cmp lc $b } @_ unless ref $_[0] eq 'CODE';

	my $keygen = shift;
	map      { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map  { [ lc $keygen->(), $_ ] } @_;
}

0x6B63;

=head1 METHODS

L<App::KADR::Collate::ASCII> implements the following methods.

=head2 C<new>

	my $collate = App::KADR::Collate->new('ascii');
	my $collate = App::KADR::Collate::ASCII->new;

Create a new ASCII collator.

=head2 C<sort>

	my @array = $collate->sort(@list);
	my @array = $collate->sort(sub { $_ }, @list);

Sort list ASCII-betically

=head1 SEE ALSO

App::KADR::Collate
