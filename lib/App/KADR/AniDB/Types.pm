package App::KADR::AniDB::Types;
# ABSTRACT: Types common to AniDB

use MooseX::Types -declare => [qw(UserName)];
use MooseX::Types::Moose qw(Str);

subtype UserName, as Str;
coerce UserName, from Str, via { lc $_ };

0x6B63;
