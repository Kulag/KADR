package App::KADR::AniDB::UDP::Types;

use common::sense;

use MooseX::Types -declare => [qw(
	RequestType
)];

use MooseX::Types::Moose qw(Str);

subtype RequestType,
	as Str,
	where { /[A-Z]/ && length $_ <= 1400 },
	message { 'Must be a single word shorter than UDP packet length' },
	inline_as {
		$_[0]->parent->_inline_check($_[1])
		. qq{ && ($_[1] =~ /[A-Z]/ && length $_[1] <= 1400)};
	};

coerce RequestType, from Str, via { uc };
