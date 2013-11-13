package App::KADR::Collate::None;
# ABSTRACT: Do-Nothing collation

use common::sense;

sub new { bless \(do { my $a = 1 }), shift }

sub sort { ref $_[1] eq 'CODE' ? @_[ 2 .. $#_ ] : @_[ 1 .. $#_ ] }

0x6B63;

=head1 DESCRIPTION

L<App::KADR::Collate::None> is a do-nothing collation implementation which
allows the option of no collation at all without needing to special-case it
in your collation-desiring code.

=head1 METHODS

L<App::KADR::Collate::None> implements the following methods.

=head2 C<new>

	my $collate = App::KADR::Collate->new('none');
	my $collate = App::KADR::Collate::None->new;

Create a new non-collator collator.

=head2 C<sort>

	my @array = $collate->sort(@list);
	my @array = $collate->sort(sub { $_ }, @list);

Doesn't sort the list.

=head1 SEE ALSO

App::KADR::Collate
