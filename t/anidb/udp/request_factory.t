use common::sense;
use FindBin;
use Test::Fatal;
use Test::More;

use lib "$FindBin::Bin/lib";
use aliased 'App::KADR::AniDB::UDP::RequestFactory', 'Factory';

package TestRequest {
	use App::KADR::AniDB::UDP::Request;
}

$INC{'TestRequest'}++;

like exception { Factory->add_factory_type('bad', __PACKAGE__) },
	qr/does not inherit ::Message::Request/,
	'throws error adding non-moose class';

like exception { Factory->add_factory_type('bad', 'Moose::Object') },
	qr/does not inherit ::Message::Request/,
	'throws error adding moose class which does not consume request role';

is exception { Factory->add_factory_type('short', 'TestRequest') }, undef;

like exception { Factory->req() },
	qr/not defined/,
	'request construction requires type';

isa_ok Factory->req('noparams'), 'App::KADR::AniDB::UDP::Request::NoParams';
isa_ok Factory->req('short'), 'TestRequest';

done_testing;
