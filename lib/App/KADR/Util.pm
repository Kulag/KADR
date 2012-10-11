package App::KADR::Util;
use common::sense;
use List::Util qw(reduce);
use Sub::Exporter -setup => {
	exports => [qw(pathname_filter pathname_filter_windows shortest)],
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
	$_[0] =~ tr{/\\?"<>|:*}{∕⧵？”⟨⟩❘∶＊}r;
}

sub shortest(@) {
	reduce { length $b < length $a ? $b : $a } @_
}

1;
