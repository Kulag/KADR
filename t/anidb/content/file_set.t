package Client;
use App::KADR::Moose;
extends 'App::KADR::AniDB::UDP::Client';

sub file {
	App::KADR::AniDB::Content::File->new(fid => $_[1]);
}

package main;
use Test::Fatal;
use Test::More;

use aliased 'App::KADR::AniDB::Content::File';
use aliased 'App::KADR::AniDB::Content::FileSet';

my $set = FileSet->parse('1|2|3');
my @objs = map { File->new(fid => $_) } (1, 2, 3);

$set->client(my $client = bless {}, 'Client');

is_deeply $set->fids, [ 1, 2, 3 ], 'parse ok';

subtest 'files' => sub {
	is_deeply $set->files, \@objs, 'files';
	is_deeply [@$set], \@objs, 'array deref';
};

subtest 'iter' => sub {
	my $iter = $set->ifiles;
	is_deeply $iter->next, $objs[0], 'iter 0';
	is_deeply $set->(), $objs[0], 'code deref';
	is_deeply $iter->next, $objs[1], 'iter 1';
	is_deeply scalar <$set>, $objs[1], 'iterator overload';
	$set->reset_iterator;
	is_deeply $iter->next, $objs[2], 'iter 2';
	is_deeply $set->(), $objs[0], 'internal iterator got reset';
};

my $set = FileSet->new(files => \@objs);
is_deeply $set->fids, [ 1, 2, 3 ], 'fids from files';

like exception { FileSet->new->fids }, qr{no files set}i,
	'error getting fids without files';
like exception { FileSet->new->files }, qr{no fids set}i,
	'error getting files without fids';

done_testing;
