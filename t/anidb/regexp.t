use common::sense;
use App::KADR::AniDB::Regexp ':all';
use Test::More;

my %tests = (
	Tag => {
		rx     => qr/^ $tag_rx $/x,
		accept => [ 't1', "t\x00", -1 ],
		reject => [ '', 10, 0, "\x00t", 't' x 256, 't t', "t\n1" ],
	},
);

while (my @a = each %tests) {
	test_rx(@a);
}

done_testing;

sub test_rx {
	my ($name, $test) = @_;

	for my $accept (@{ $test->{accept} }) {
		ok $accept =~ $test->{rx}, qq{$name accepts "$accept"};
	}

	for my $reject (@{ $test->{reject} }) {
		ok $reject !~ $test->{rx}, qq{$name rejects "$reject"};
	}
}
