package App::KADR::Collate::Unicode;
use common::sense;

use parent 'Unicode::Collate';

sub new {
	my ($class, %opts) = @_;

	$opts{level} //= 1;

	# Explicitly set undef to disable normalization. See Unicode::Collate.
	$opts{normalize} //= undef;

	$class->SUPER::new(%opts);
}

sub sort {
	my $self = shift;

	return $self->SUPER::sort(@_) unless ref $_[0] eq 'CODE';

	my $keygen = shift;
	map      { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map  { [ $self->getSortKey($keygen->()), $_ ] } @_;
}

1;

=head1 NAME

App::KADR::Collate::Unicode - Unicode collation

=head1 METHODS

L<App::KADR::Collate::Unicode> inherits all methods from L<Unicode::Collate>,
and implements the following new ones.

=head2 C<new>

	my $collate = App::KADR::Collate->new('unicode');
	my $collate = App::KADR::Collate::Unicode->new;

Create a new Unicode collator. Defaults level to 1 (case-insensitive),
and normalize to undef.

=head2 C<sort>

	my @array = $collate->sort(@list);
	my @array = $collate->sort(sub { $_ }, @list);

Sort list with Unicode::Collate.

=head1 SEE ALSO

L<App::KADR::Collate>, L<Unicode::Collate>

=cut
