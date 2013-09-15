package App::KADR::AniDB::Types;
# ABSTRACT: Types common to AniDB

use MooseX::Types -declare => [qw(ID MaybeID UserName)];
use MooseX::Types::Moose qw(Int Maybe Str);
use MooseX::Types::Common::Numeric qw(PositiveInt);

subtype ID, as PositiveInt;

subtype MaybeID, as Maybe[ID];
coerce MaybeID, from Int, via { $_ > 0 ? $_ : () };

subtype UserName, as Str;
coerce UserName, from Str, via { lc $_ };

0x6B63;

=head1 TYPES

=head2 C<ID>

A AniDB ID is a positive integer. See also C<MooseX::Types::Comment::Numeric

=head2 C<MaybeID>

Undef or an AniDB ID. 0 is used for undef IDs in the UDP API.
XXX: This should be moved to typemapping when it's implemented.

=head2 C<UserName>

AniDB username are lower-case simple strings.
