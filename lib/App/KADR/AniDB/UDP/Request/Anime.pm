package App::KADR::AniDB::UDP::Request::Anime;

use App::KADR::AniDB::Types qw(ID);
use App::KADR::AniDB::UDP::Request;

with 'MooseX::OneArgNew' => {init_arg => 'aid', type => 'Int'};

has_field 'aid', isa => ID;
