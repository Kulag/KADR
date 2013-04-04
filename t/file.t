use App::KADR::Path -all;
use common::sense;
use FindBin;
use Test::More;

my $file = dir($FindBin::Bin)->file('file.t');

subtest 'abs_cmp' => sub {
	ok $file == dir($FindBin::Bin)->file('file.t');
	ok $file != dir($FindBin::Bin)->file('dir.t');
	ok $file != dir($FindBin::Bin, 'file.t');
};

done_testing;
