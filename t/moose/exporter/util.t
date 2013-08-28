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

		is_deeply((my $ret = $sub->($args)), {});
		is $args->[3], $ret;
	};

	subtest 'already present' => sub {
		my $args = [
			(my $self = bless {}),
			-traits => [],
			(my $h = {into => 'foo'}),
			abc => {-as => 'bca'},
		];

		is((my $ret = $sub->($args)), $h);
		is $args->[3], $ret;
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
