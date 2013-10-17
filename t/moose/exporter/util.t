use common::sense;
use Test::More;

use App::KADR::Moose::Exporter::Util -all;

subtest get_sub_exporter_into_hash => sub {
	my $sub = *get_sub_exporter_into_hash;

	subtest 'no args' => sub {
		my $args = [ my $self = bless {} ];

		is_deeply((my $ret = $sub->($args)), {});
		is $args->[0], $self;
		is $args->[1], $ret;
	};

	subtest 'all but into' => sub {
		my $args = [ (my $self = bless {}), -traits => [],
			abc => { -as => 'bca' } ];
		my $args2 = [@$args];

		ok !keys (my $ret = $sub->($args2)), 'got an empty hash back';
		is $args2->[5], $ret, 'returned into hash is in the args';
		is $args2->[$_], $args->[$_], "nothing changed in $_" for 0 .. $#$args;
	};

	subtest 'already present' => sub {
		my $args = [
			(my $self = bless {}),
			-traits => [],
			(my $h = {into => 'foo'}),
			abc => {-as => 'bca'},
		];
		my $args2 = [@$args];

		is((my $ret = $sub->($args2)), $h), 'got the right arg back';
		is $args->[3], $ret, 'returned into hash is in the args';
		is $args2->[$_], $args->[$_], "nothing changed in $_" for 0 .. $#$args;
	};
};

subtest strip_import_params => sub {
	my $args = [ 1, '-foo', 'a', '-bar', 'b', {} ];
	my $param = strip_import_params($args, 'bar');
	is_deeply $param, { bar => 'b' },
		'strip_import_params should remove correct argument';
	is_deeply $args, [ 1, '-foo', 'a', {} ],
		'strip_import_params should ignore unknown args';

	$param = strip_import_params($args, 'baz');
	is_deeply $param, undef, 'strip_import_params should return undef';
	is_deeply $args, [ 1, '-foo', 'a', {} ],
		'strip_import_params should ignore unknown args';
};

done_testing;
