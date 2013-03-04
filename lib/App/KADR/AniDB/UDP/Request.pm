package App::KADR::AniDB::UDP::Request;

use aliased 'App::KADR::AniDB::UDP::Message::Request', 'RequestBase';
use aliased 'App::KADR::AniDB::UDP::Message::Sugar';
use App::KADR::AniDB::UDP::Util qw(type_of_request);
use App::KADR::Moose ();
use App::KADR::Util ();
use Carp qw(croak);
use common::sense;
use Moose::Exporter ();
use namespace::autoclean;

my @PARAM_NAMES => qw(anonymous type);

my $import_params;

my ($import, $unimport, $init_meta) = Moose::Exporter->build_import_methods(
	also => ['App::KADR::Moose', Sugar],
	class_metaroles => {
		class => ['App::KADR::AniDB::UDP::Meta::Class::Trait::Request'],
	},
	install => ['unimport'],
);

sub import {
	__PACKAGE__->strip_import_params(\@_);
	goto &$import;
}

sub init_meta {
	my ($class, %args) = @_;
	my $params = $import_params;
	undef $import_params;

	#$class->$init_meta(%args) if $init_meta;
	my $meta = Moose->init_meta(%args);

	$meta->superclasses(RequestBase);

	$meta->is_anonymous(1) if $params->{anonymous};
	$meta->request_type($params->{type}) if exists $params->{type};

	Class::MOP::class_of($args{for_class});
}

sub strip_import_params {
	App::KADR::Moose->strip_import_params($_[1]);
	$import_params = App::KADR::Util::strip_import_params($_[1], @PARAM_NAMES);
}

=head1 NAME

App::KADR::AniDB::UDP::Request - AniDB UDP API request

=head1 SYNOPSIS

	my $req = App::KADR::AniDB::UDP::Request->new(
		type => 'anime',
		params => { aid => 1, amask => ANIME_MASK },
	);
	
	my $string = $req->stringify;

=head1 ATTRIBUTES

L<App::KADR::AniDB::UDP::Request> implements the following attributes.

Request type.

=head2 C<params>

	my $params = $req->params;
	$params->{aid} = 1;

Request parameters.

=head2 C<type>

	my $type = $req->type;

=head1 METHODS

L<App::KADR::AniDB::UDP::Request> implements the following methods.

=head2 C<stringify>

	my $string = "$req";
	my $string = $req->stringify;

Stringify request.

=cut
