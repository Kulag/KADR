package App::KADR::AniDB::UDP::Transaction;
# ABSTRACT: AniDB UDP Transaction

use App::KADR::Moose;
use MooseX::NonMoose;

extends 'Mojo::EventEmitter';

has 'req', default => sub { {} }, isa => 'HashRef';
has 'res', default => sub { {} }, isa => 'HashRef';

sub error {
	my $self = shift;

	# Set
	if (@_) {
		$self->{error} = [@_];
		return $self;
	}

	return unless my $e = $self->{error};
	wantarray ? @$e : $e->[0];
}

sub success {
	my $self = shift;
	$self->error ? undef : $self->res;
}

sub tag {
	$_[0]->req->{params}->{tag};
}

=head1 DESCRIPTION

L<App::KADR::AniDB::UDP::Transaction> is a container for AniDB UDP transactions.

=head1 EVENTS

L<App::KADR::AniDB::UDP::Transaction> can emit the following events.

=head2 C<finish>

	$tx->on(finish => sub {
		my $tx = shift;
		...
	});

Emitted when transaction is finished.

=head1 ATTRIBUTES

L<App::KADR::AniDB::UDP::Transaction> implements the following attributes.

=head1 C<req>

	my $req = $tx->req;
	$tx     = $tx->req($tx);

Request, defaults to a HashRef.

=head1 C<res>

	my $res = $tx->res;
	$tx     = $tx->res($res);

Response, defaults to a HashRef.

=head1 METHODS

L<App::KADR::AniDB::UDP::Transaction> inherits all methods from
L<Mojo::EventEmitter> and implements the following new ones.

=head2 C<error>

	my $err          = $tx->error;
	my ($err, $code) = $tx->error;

Parser errors and codes.

=head2 C<success>

	my $res = $tx->success;

Returns the response (res) if transaction was successful or undef otherwise.
Connection and parser errors only have a message in C<error>, 600 errors
also a code.

=head1 SEE ALSO

L<App::KADR::AniDB::UDP::Client>
