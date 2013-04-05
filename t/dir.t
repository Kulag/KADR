use App::KADR::Path -all;
use common::sense;
use File::HomeDir;
use FindBin;
use Test::More;

my $bindir   = dir($FindBin::Bin);
my $home     = dir(File::HomeDir->my_home);
my $homefile = file(File::HomeDir->my_home);

subtest 'abs_cmp' => sub {
	ok $home != undef;
	ok $home eq File::HomeDir->my_home;
	ok $home != $homefile;
	is $home <=> $homefile, ($homefile <=> $home) * -1;
	ok $home eq dir(File::HomeDir->my_home);
	ok $home == dir(File::HomeDir->my_home);
	ok $home ne $bindir;
	ok $home != $bindir;
	ok $bindir ne $bindir->relative($home);
	ok $bindir != $bindir->relative($home);
	ok $bindir == $bindir->relative;
	ok $bindir->relative == $bindir;
	ok $bindir->relative != $bindir->relative($home);
};

done_testing;
