package App::KADR::Collate::UnicodeICU;
# ABSTRACT: Fast Unicode collation using the ICU library

use App::KADR::Moose;
use Unicode::ICU::Collator qw(:attributes);

has 'icu', is => 'lazy';
has 'locale', default => 'en';

sub getSortKey {
	# This character is used by default for : substitution. Unicode::Collate
	# normalizes it away, but ICU does not.
	shift->icu->getSortKey(shift =~ s{∶}{}rg);
}

sub sort {
	my $self = shift;
	my $keygen = ref $_[0] eq 'CODE' ? shift : ();
	my $get_sort_key
		= $keygen
		? sub { [ $self->getSortKey($keygen->()), $_ ] }
		: sub { [ $self->getSortKey($_), $_ ] };

	map { $_->[1] } sort { $a->[0] cmp $b->[0] } map &$get_sort_key, @_;
}

sub _build_icu {
	my $icu = Unicode::ICU::Collator->new($_[0]->locale);

	$icu->setAttribute(UCOL_STRENGTH,           UCOL_PRIMARY);
	$icu->setAttribute(UCOL_ALTERNATE_HANDLING, UCOL_SHIFTED);

	$icu;
}

0x6B63;

=head1 SYNOPSIS

	my $collate = App::KADR::Collate->new('unicodeicu', %params);
	my $collate = App::KADR::Collate::UnicodeICU->new(%params);

	my @array = $collate->sort(@list);

=head1 DESCRIPTION

L<App::KADR::Collate::UnicodeICU> is a partial L<Unicode::Collate>-like
wrapper for L<Unicode::ICU::Collator>. At present it is unconfigurable aside
from locale, and attempts to mimic Unicode::Collate's sort output with
(level => 1, normalize => undef).

=head1 USAGE

L<App::KADR::Collate::UnicodeICU> requires L<Unicode::ICU::Collator>,
which in turn requires the ICU library and headers, and a compiler to install.

=head1 METHODS

L<App::KADR::Collate::UnicodeICU> implements the following methods.

=head2 C<getSortKey>

	my $key = $collate->getSortKey($string);

Get sort key for string. Removes ∶ from the string before getting the sort key
since ICU doesn't shift ∶ to level 4 like Unicode::Collate.

=head2 C<sort>

	my @array = $collate->sort(@list);
	my @array = $collate->sort(sub { $_ }, @list);

Sort list with Unicode::ICU::Collator.

=head1 SEE ALSO

L<App::KADR::Collate>, L<Unicode::ICU::Collator>
