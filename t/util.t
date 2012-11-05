#!/usr/bin/env perl

use common::sense;
use FindBin;
use Test::More tests => 12;

use lib "$FindBin::RealBin/../lib";
use App::KADR::Util qw(:pathname_filter shortest strip_import_params);

is pathname_filter('/?"<>|:*!\\'), '∕?"<>|:*!\\', 'unix pathname filter';
is pathname_filter_windows('/?"<>|:*!\\'), '∕？”⟨⟩❘∶＊!⧵', 'windows pathname filter';

is shortest(qw(ab c)), 'c', 'shortest argument returned';
is shortest(qw(a b c)), 'a', 'argument order preserved';
is shortest(undef), undef, 'undef returns safely';
is shortest(qw(a b), undef), undef, 'undef is shortest';

ok !defined shortest(), 'undefined if no args';
is shortest('a'), 'a', 'one arg okay';

{
	my $args = [1, '-foo', 'a', '-bar', 'b', {}];
	my $param = strip_import_params($args, 'bar');
	is_deeply $param, {bar => 'b'},
		'strip_import_params should remove correct argument';
	is_deeply $args, [1, '-foo', 'a', {}],
		'strip_import_params should ignore unknown args';

	$param = strip_import_params($args, 'baz');
	is_deeply $param, undef,
		'strip_import_params should return undef';
	is_deeply $args, [1, '-foo', 'a', {}],
		'strip_import_params should ignore unknown args';
}
