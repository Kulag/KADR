use App::KADR::AniDB::Types -all;
use common::sense;
use Eval::Closure qw(eval_closure);
use Moose::Util::TypeConstraints qw(find_type_constraint);
use Scalar::Util qw(blessed openhandle);
use Test::More;

my %types = (
	Tag ,=> {
		accept => [ 't1', "t\x00", -1 ],
		reject => [ '',   10, 0, "\x00t", 't' x 256, 't t', "t\n1", [] ],
	},
	LowerCaseWhitespacelessSimpleStr ,=> {
		accept => ['abc'],
		reject => [ '', 'abc ', "abc\n", 'a' x 256, 'ABC', [] ]
	},
	WhitespacelessSimpleStr ,=> {
		accept => ['aBc'],
		reject => [ '', 'a c', "abc\n", 'a' x 256, [] ]
	}
);

$types{ +UserName } = $types{ +LowerCaseWhitespacelessSimpleStr };

while (my @a = each %types) {
	test_constraint(@a);
}

is to_MaybeID(0),                              undef;
is to_LowerCaseWhitespacelessSimpleStr('FOO'), 'foo';

done_testing;

# The following are copied from Moose's test suite.
# TODO: Make a library of this instead.
sub test_constraint {
	my ($type, $tests) = @_;

	local $Test::Builder::Level = $Test::Builder::Level + 1;

	unless (blessed $type) {
		$type = find_type_constraint($type) or BAIL_OUT("No such type $type!");
	}

	my $name = $type->name;

	my $unoptimized
		= $type->has_parent
		? $type->_compile_subtype($type->constraint)
		: $type->_compile_type($type->constraint);

	my $inlined;
	if ($type->can_be_inlined) {
		$inlined = eval_closure(
			source      => 'sub { ( ' . $type->_inline_check('$_[0]') . ' ) }',
			environment => $type->inline_environment,
		);
	}

	for my $accept (@{ $tests->{accept} }) {
		my $described = describe($accept);
		ok $type->check($accept), "$name accepts $described using ->check";
		ok $unoptimized->($accept),
			"$name accepts $described using unoptimized constraint";
		if ($inlined) {
			ok $inlined->($accept),
				"$name accepts $described using inlined constraint";
		}
	}

	for my $reject (@{ $tests->{reject} }) {
		my $described = describe($reject);
		ok !$type->check($reject), "$name rejects $described using ->check";
		ok !$unoptimized->($reject),
			"$name rejects $described using unoptimized constraint";
		if ($inlined) {
			ok !$inlined->($reject),
				"$name rejects $described using inlined constraint";
		}
	}
}

sub describe {
	my $val = shift;

	return 'undef' unless defined $val;

	if (!ref $val) {
		return q{''} if $val eq q{};

		$val =~ s/\n/\\n/g;

		return $val;
	}

	return 'open filehandle' if openhandle $val && !blessed $val;

	return blessed $val ? (ref $val) . ' object' : (ref $val) . ' reference';
}

