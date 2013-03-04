use common::sense;
use Test::Fatal;
use Test::More;

package TestClass {
	use Moose;
	use MooseX::HasDefaults::RW;
	use App::KADR::AniDB::Types ':all';

	has 'id',               isa => ID;
	has 'user_name',        isa => UserName;
	has 'user_name_coerce', isa => UserName;
}

sub c {
	TestClass->new(@_);
}

sub run_tests {
	my $c = TestClass->new;

	isnt exception { c(id => 0) }, undef, '0 id';
	is exception { c(id => 1) }, undef, '1 id';
}

run_tests();

TestClass->meta->make_immutable;

run_tests();

done_testing;
