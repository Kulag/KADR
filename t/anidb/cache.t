use common::sense;

package t::Obj {
	use App::KADR::Moose ();    # FIXME: App::KADR::Moose::Exporter bug!
	use App::KADR::AniDB::Content;

	has [qw(id value)];

	max_age 60;

	sub primary_key {'id'}
}

package t::TaggedObj {
	use App::KADR::AniDB::Content;

	extends 't::Obj';

	dynamic_max_age 60, sub { { tag => shift->value } };
}

use Test::More;

use aliased 'App::KADR::AniDB::Cache';
use aliased 'App::KADR::DBI';

sub Obj       {'t::Obj'}
sub TaggedObj {'t::TaggedObj'}

my $db = DBI->new('dbi:SQLite::memory:',
	{ obj => 't::Obj', tobj => 't::TaggedObj' });
$db->{dbh}->do("CREATE TABLE $_ (id INT PRIMARY KEY, value INT, updated INT)")
	for qw(obj tobj);

subtest "get/set" => sub {
	my $cache = Cache->new(db => $db);

	is $cache->max_age_for(Obj), 60, "right max age for class";
	is $cache->max_age_for(Obj, 0), 0,
		"right max age for class when overridden";

	is $cache->get(Obj, { id => 1 }), undef, "nothing cached initially";

	$cache->set(Obj->new(id => 1, value => 1, updated => 0));
	is $cache->get(Obj, { id => 1 }), undef,
		"got nothing because updated is 0";

	$cache->set(my $obj = Obj->new(id => 1, value => 1, updated => time - 5));

	is $cache->max_age_for($obj), 60, "right max age for object";
	is $cache->max_age_for($obj, 0), 0,
		"right max age for object when overridden";

	ok $cache->get(Obj, { id => 1 }), "cached and updated";
	is $cache->get(Obj, { id => 1 }, { max_age => 0 }), undef,
		"right return from get when max age overridden to 0";

	is $cache->max_age_for(TaggedObj), 60, "right max age for tagging class";
	is $cache->max_age_for(TaggedObj, 0), 0,
		"right max age for tagging class when overridden";
	is $cache->max_age_for(TaggedObj, { '' => 1, tagged => 2 }), 1,
		"right max age for tagging class when using tagged overrides";

	my $tobj = TaggedObj->new(id => 1, value => 1, updated => time - 20);
	$cache->set($tobj);

	is $cache->max_age_for($tobj), 1, "right max age for tagging object";
	is $cache->max_age_for($tobj, 100), 100,
		"right max age for tagging object with override";
	is $cache->max_age_for($tobj, { '' => 1, tag => 100 }), 100,
		"right max age for tagging object with tagged overrides";

	is $cache->get(TaggedObj, { id => 1 }), undef,
		"got nothing from get for tagging object";
	ok $cache->get(TaggedObj, { id => 1 }, { max_age => 100 }),
		"got obj from get for tagging object with overridden max_age";
};

subtest "max_ages" => sub {
	my $cache
		= Cache->new(db => $db, max_ages => { Obj ,=> 20, TaggedObj ,=> 20 });

	is $cache->max_age_for(Obj), 20, "right max age for class";
	is $cache->max_age_for(Obj, 0), 0,
		"right max age for class when overridden";

	my $obj = Obj->new(id => 1, value => 1, updated => time - 5);

	is $cache->max_age_for($obj), 20, "right max age for object";
	is $cache->max_age_for($obj, 0), 0,
		"right max age for object when overridden";

	is $cache->max_age_for(TaggedObj), 20, "right max age for tagging class";
	is $cache->max_age_for(TaggedObj, 0), 0,
		"right max age for tagging class when overridden";
	is $cache->max_age_for(TaggedObj, { '' => 1, tagged => 2 }), 1,
		"right max age for tagging class when using tagged overrides";

	my $tobj = TaggedObj->new(id => 1, value => 1, updated => time - 20);

	is $cache->max_age_for($tobj), 20, "right max age for tagging object";
	is $cache->max_age_for($tobj, 100), 100,
		"right max age for tagging object with override";
	is $cache->max_age_for($tobj, { '' => 1, tag => 100 }), 100,
		"right max age for tagging object with tagged overrides";
};

subtest "max_ages tagged overrides" => sub {
	my $cache = Cache->new(
		db       => $db,
		max_ages => { TaggedObj ,=> { '' => 10, tag => 20 } },
	);

	is $cache->max_age_for(TaggedObj), 10, "right max age for tagging class";
	is $cache->max_age_for(TaggedObj, 0), 0,
		"right max age for tagging class when overridden";
	is $cache->max_age_for(TaggedObj, { '' => 1, tagged => 2 }), 1,
		"right max age for tagging class when using tagged overrides";

	my $tobj = TaggedObj->new(id => 1, value => 1, updated => time - 20);

	is $cache->max_age_for($tobj), 20, "right max age for tagging object";
	is $cache->max_age_for($tobj, 100), 100,
		"right max age for tagging object with override";
	is $cache->max_age_for($tobj, { '' => 1, tag => 100 }), 100,
		"right max age for tagging object with tagged overrides";
};

subtest "compute" => sub {
	my $cache = Cache->new(db => $db);

	my $i;

	my $code = sub { Obj->new(id => 2, value => ++$i, updated => time - 1) };

	{
		my $obj = $cache->compute(Obj, { id => 2 }, $code);

		ok $obj, "got obj";
		is $obj->value, 1, 'obj value is 1';
	}

	{
		my $obj = $cache->compute(Obj, { id => 2 }, $code);

		ok $obj, 'got obj';
		is $obj->value, 1, "obj didn't get recreated";
	}

	{
		my $obj = $cache->compute(Obj, { id => 2 }, { max_age => 0 }, $code);

		ok $obj, "got obj";
		is $obj->value, 2, "obj got recreated";
	}
};

done_testing;
