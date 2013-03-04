package App::KADR::AniDB::Types;
# ABSTRACT: Types common to AniDB

use MooseX::Types -declare => [qw(ID UserName)];
use MooseX::Types::Common::Numeric qw(PositiveInt);
use MooseX::Types::Common::String qw(LowerCaseSimpleStr);

subtype ID, as PositiveInt;
subtype UserName, as LowerCaseSimpleStr;

0x6B63;
