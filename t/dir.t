use App::KADR::Path -all;
use common::sense;
use File::HomeDir;
use FindBin;
use Test::More;
use Test::Fatal;

my $bindir   = dir($FindBin::Bin);
my $home     = dir(File::HomeDir->my_home);
my $homefile = file(File::HomeDir->my_home);

my $username = do {
	if ($^O eq 'Win32') {
		require Win32;
		Win32::LoginName();
	}
	else {
		require POSIX;
		POSIX::cuserid();
	}
};

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

subtest 'new' => sub {
	is dir('~'), $home;
	is dir('~/foo'), $home->subdir('foo');
	is dir('foo/~'), 'foo/~';

	like exception { dir('~foo') }, qr/No homedir for user/;
	is dir('~' . $username), $home;
	is dir('~' . $username . '/foo'), $home->subdir('foo');
};

done_testing;
