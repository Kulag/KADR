package App::KADR::Util;
# ABSTRACT: Utility functions for KADR

use common::sense;
use List::AllUtils qw(firstidx reduce);
use Params::Util qw(_STRING);
use Sub::Exporter -setup => {
	exports => [qw(pathname_filter pathname_filter_windows shortest _STRINGLIKE0)],
	groups => {
		pathname_filter => [qw(pathname_filter pathname_filter_windows)],
	}
};

sub pathname_filter {
	$_[0] =~ tr{/}{∕}r;
}

sub pathname_filter_windows {
	# All non-described replacements are double-width
	# versions of the original characters.
	# ∕ U+2215 DIVISION SLASH
	# ⧵ U+29F5 REVERSE SOLIDUS OPERATOR
	# ” U+201D RIGHT DOUBLE QUOTATION MARK
	# ⟨ U+27E8 MATHEMATICAL LEFT ANGLE BRACKET
	# ⟩ U+27E9 MATHEMATICAL RIGHT ANGLE BRACKET
	# ❘ U+2758 LIGHT VERTICAL BAR
	$_[0] =~ tr!/\\?"<>|:*!∕⧵？”⟨⟩❘∶＊!r;
}

sub shortest(@) {
	reduce { length $b < length $a ? $b : $a } @_
}

# XXX: From Moose::Util, replace with Params::Util version once it gets moved.
sub _STRINGLIKE0 ($) {
	_STRING($_[0])
	|| (blessed $_[0] && overload::Method($_[0], q{""}))
	|| (defined $_[0] && $_[0] eq '');
}

0x6B63;

=head1 FUNCTIONS

=head2 C<pathname_filter>
=head2 C<pathname_filter_windows>

	my $pathname = pathname_filter 'foo/bar';

Replace invalid characters in path names with similar unicode characters. The
former replaces / only. The windows version replaces \?"<>|:*

=head2 C<shortest>

	my $a = shortest qw(a ab abc);

Return the shortest string of the list.

=head2 C<_STRINGLIKE0>

	my $str = _STRINGLIKE0 $_[1] or die 'Invalid parameter';

Test if parameter is a string or an object with a stringify overload.

=head1 IMPORT TAGS

=head2 C<-pathname_filter>

C<pathname_filter> C<pathname_filter_windows>
