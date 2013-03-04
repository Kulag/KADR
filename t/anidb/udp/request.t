use common::sense;
use FindBin;
use Test::Fatal;
use Test::More;

use lib "$FindBin::Bin/lib";
use aliased 'App::KADR::AniDB::UDP::Request::NoParams';

my $req = NoParams->new;

ok !$req->meta->req_needs_session, 'noparams requires session';
is $req->meta->req_type, 'NOPARAMS', 'type is noparams';

is $req->stringify, "NOPARAMS\n", 'stringify without params works';
is "$req", "NOPARAMS\n", 'overloaded stringify works';

$req->tag('foo');

is $req->stringify, "NOPARAMS tag=foo\n", 'stringify with params should work';

$req->session_key('bar');
is $req->session_key, 'bar';

ok "$req" eq "NOPARAMS s=bar&tag=foo\n" || "$req" eq "NOPARAMS tag=foo&s=bar\n",
	'stringify with multiple params works - Got: ' . "$req";

done_testing;
