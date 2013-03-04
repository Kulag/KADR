use v5.14;
use common::sense;

use App::KADR::AniDB::UDP::Util -all;
use Test::Fatal;
use Test::More;

package App::KADR::AniDB::UDP::Request::Test {
	use App::KADR::AniDB::UDP::Request;
}

package App::KADR::AniDB::UDP::Request::NonInherit {
	use Moose;
}

like exception { type_of_request() }, qr/Request undefined/;

like
	exception {
		type_of_request(App::KADR::AniDB::UDP::Request::NonInherit->new)
	},
	qr/does not inherit/;

like exception { type_of_request('main') },
	qr/Unable to determine request type/;

is type_of_request('App::KADR::AniDB::UDP::Request::Test'), 'TEST';
is type_of_request(App::KADR::AniDB::UDP::Request::Test->new), 'TEST';

done_testing;
