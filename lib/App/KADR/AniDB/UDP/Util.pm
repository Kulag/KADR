package App::KADR::AniDB::UDP::Util;

use aliased 'App::KADR::AniDB::UDP::Message::Request';
use Carp qw(croak);
use common::sense;
use Params::Util qw(_INVOCANT);
use Scalar::Util qw(blessed);

use Sub::Exporter::Progressive -setup => {
	exports => ['type_of_request'],
};

my $REQUEST_CLASS_RE = qr{^App::KADR::AniDB::UDP::Request::([^:]+)$};

sub type_of_request {
	my $req = $_[0] or croak 'Request undefined';

	if (_INVOCANT($req)) {
		if ($req->isa(Request)) {
			my $meta = $req->meta;
			return $meta->req_type if $meta->has_req_type;
		}

		croak 'Object does not inherit ::Message::Request' if blessed $req;
	}

	# Guess from class name.
	return uc $1 if $req =~ $REQUEST_CLASS_RE;

	croak 'Unable to determine request type of ' . $req;
}
