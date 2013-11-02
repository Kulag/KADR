package App::KADR::AniDB::Types;
# ABSTRACT: Types common to AniDB

use App::KADR::AniDB::Regexp qw($tag_rx);
use MooseX::Types -declare => [
	qw(ID LowerCaseWhitespacelessSimpleStr MaybeID Tag WhitespacelessSimpleStr
		UserName)
	];
use MooseX::Types::Moose qw(Int Maybe Str);
use MooseX::Types::Common::Numeric qw(PositiveInt);
use MooseX::Types::Common::String qw(SimpleStr);

subtype ID, as PositiveInt;

subtype MaybeID, as Maybe[ID];
coerce MaybeID, from Int, via { $_ > 0 ? $_ : () };

subtype Tag,
	as Str,
	where { $_ =~ /^ $tag_rx $/x },
	message {
		'Must be a non-empty single line without whitespace of no more than '
			. '255 chars which does not begin with a number or null' },
	inline_as {
		$_[0]->parent->_inline_check($_[1]) . " && $_[1] =~ /^ $tag_rx \$/x";
	};

subtype WhitespacelessSimpleStr, as SimpleStr,
	where { $_ =~ /^ \S+ $/x },
	message {
		'Must be a non-empty single line without whitespace of no more than '
		. '255 chars' },
	inline_as {
		$_[0]->parent->_inline_check($_[1]) . " && $_[1] =~ " . '/^ \S+ $/x';
	};

subtype LowerCaseWhitespacelessSimpleStr, as WhitespacelessSimpleStr,
	where { !/\p{Upper}/ms },
	message {
		'Must be a non-empty single line without whitespace of no more than '
		. '255 chars which contains no uppercase characters'
	},
	inline_as {
		$_[0]->parent()->_inline_check($_[1]) . " && $_[1] !~ /\\p{Upper}/ms";
	};

coerce LowerCaseWhitespacelessSimpleStr,
	from WhitespacelessSimpleStr,
	via {lc};

subtype UserName, as LowerCaseWhitespacelessSimpleStr;

0x6B63;

=head1 TYPES

=head2 C<ID>

A AniDB ID is a positive integer. See also C<MooseX::Types::Comment::Numeric

=head2 C<MaybeID>

Undef or an AniDB ID. 0 is used for undef IDs in the UDP API.
XXX: This should be moved to typemapping when it's implemented.

=head2 C<LowerCaseWhitespacelessSimpleStr>

A lowercase simple string with no whitespace. Coerces from
WhitespacelessSimpleStr.

=head2 C<Tag>

A simple string with no whitespace which does not begin with a null or numeric
character.

=head2 C<UserName>

AniDB username are lower-case simple strings with no whitespace.

=head2 C<WhitespacelessSimpleStr>

A simple string with no whitespace.

=head1 SEE ALSO

L<App::KADR::AniDB::Regexp>, L<MooseX::Types::Common::String>
