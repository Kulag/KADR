use common::sense;
use Mojo::Util qw(camelize);
use Test::More;

use aliased 'App::KADR::AniDB::Role::Content::Referencer';
use aliased 'App::KADR::AniDB::UDP::Client::Caching', 'Client';
use aliased 'App::KADR::DBI';

my $db;
my %types;

sub obj_ok {
	my $obj = shift;
	ok $obj, "obj returned";
	is $obj->updated, 0, "obj updated value is 0";
	ok $obj->client, "obj has client obj attached" if $obj->does(Referencer);
}

sub populate_db {
	for my $type (keys %types) {
		$db->{dbh}->do("delete from $types{$type}->{table}");
		$db->insert($types{$type}->{table},
			{ $types{$type}->{key} => 1, updated => 0 });
	}
}

BEGIN {
	%types = do {
		map {
			my ($type, $key, $table, $class) = @$_;
			$table ||= 'anidb_' . $type;
			$class ||= 'App::KADR::AniDB::Content::' . camelize $type;

			# Alias
			*{ substr $class, rindex($class, ':') + 1 } = sub {$class};

			(
				$type => {
					type  => $type,
					key   => $key,
					table => $table,
					class => $class,
				},
			);

			} (
			[ 'anime', 'aid' ],
			[ 'file', 'fid', 'adbcache_file' ],
			[
				'mylist_file', 'lid', 'anidb_mylist_file',
				'App::KADR::AniDB::Content::MylistEntry',
			],
			[
				'mylist_anime',       'aid',
				'anidb_mylist_anime', 'App::KADR::AniDB::Content::MylistSet',
			],
			);
	};
}

$db = DBI->new('dbi:SQLite::memory:',
	{ map { @$_{qw(table class)} } values %types });
my %client_opts
	= (cache => { db => $db }, username => 'foo', password => 'bar');
my $c = Client->new(%client_opts);

subtest "init cache clear" => sub {
	populate_db;
	my $c = Client->new(%client_opts);

	ok !$db->fetch(File, ['*'], { fid => 1 }, 1);
};

subtest "no init cache clear" => sub {
	populate_db;
	my $c = Client->new(%client_opts,
		cache => { db => $db, ignore_max_age => 1 });

	ok $db->fetch(File, ['*'], { fid => 1 }, 1);
	obj_ok $c->file(fid => 1, { no_update => 1 });
};

subtest "query method options" => sub {
	for my $type (keys %types) {
		my $key = $types{$type}->{key};

		obj_ok $c->$type($key => 1, { max_age => time + 10 });

		ok !$c->$type($key => 1, { no_update => 1 });
	}
};

$db->{dbh}->do('insert into adbcache_file (fid,aid,lid,ed2k,size,updated) values (2,1,1,"foo", 1,0)');

subtest "cached lid" => sub {
	for (
		[ [ fid => 1 ], undef ],
		[ [ fid => 2 ], 1 ],
		[ [ ed2k => 'foo', size => 2 ], undef ],
		[ [ ed2k => 'foo', size => 1 ], 1 ],
		[ [ aid => 1 ], undef ])
	{
		is $c->get_cached_lid(@{ $_->[0] }), $_->[1];
	}
};

done_testing;
