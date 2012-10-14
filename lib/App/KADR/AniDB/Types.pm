package App::KADR::AniDB::Types;
use MooseX::Types -declare => [qw(UserName)];
use MooseX::Types::Moose qw(Str);

subtype UserName, as Str;
coerce UserName, from Str, via { lc $_ };

1;
