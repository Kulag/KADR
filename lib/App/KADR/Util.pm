package App::KADR::Util;
use common::sense;
use Sub::Exporter -setup => {
	exports => [qw(pathname_filter pathname_filter_windows)],
	groups => {
		pathname_filter => [qw(pathname_filter pathname_filter_windows)],
	}
};

sub pathname_filter {
	$_[0] =~ tr{/}{∕}r;
}

sub pathname_filter_windows {
	$_[0] =~ tr{/\\?"<>|:*}{∕￥？”＜＞｜：＊}r;
}

1;
