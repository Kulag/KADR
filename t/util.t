use common::sense;
use Test::More;

use App::KADR::Util qw(:pathname_filter shortest);

is pathname_filter('/?"<>|:*!\\'), '∕?"<>|:*!\\', 'unix pathname filter';
is pathname_filter_windows('/?"<>|:*!\\'), '∕？”⟨⟩❘∶＊!⧵', 'windows pathname filter';

is shortest(qw(ab c)), 'c', 'shortest argument returned';
is shortest(qw(a b c)), 'a', 'argument order preserved';
is shortest(undef), undef, 'undef returns safely';
is shortest(qw(a b), undef), undef, 'undef is shortest';

ok !defined shortest(), 'undefined if no args';
is shortest('a'), 'a', 'one arg okay';

done_testing;
