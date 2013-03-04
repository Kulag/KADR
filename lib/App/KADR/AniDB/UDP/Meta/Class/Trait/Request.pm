package App::KADR::AniDB::UDP::Meta::Class::Trait::Request;

use App::KADR::AniDB::UDP::Types qw(RequestType);
use App::KADR::AniDB::UDP::Util qw(type_of_request);
use App::KADR::Moose::Role;
use MooseX::Types::LoadableClass qw(LoadableClass);

has 'req_needs_session',
	default => 0,
	isa     => 'Bool';

has 'req_type',
	default   => sub { type_of_request($_[0]->name) },
	isa       => RequestType,
	lazy      => 1,
	predicate => 1;

has 'stringifier_class',
	default => 'App::KADR::AniDB::UDP::Meta::Method::Request::Stringifier',
	isa     => LoadableClass;

with 'App::KADR::AniDB::UDP::Meta::Class::Trait::Message';
