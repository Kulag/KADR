package App::KADR::AniDB::Content::FileSet;
# ABSTRACT: A list of files

use App::KADR::AniDB::Content -noclean => 1;
use Carp qw(croak);
use Iterator::Simple qw(imap list);
use MooseX::Types::Moose -all;

use overload
	'<>'  => sub { shift->_iter->() },
	'@{}' => sub { shift->files },
	'&{}' => sub { shift->_iter };

with 'App::KADR::AniDB::Role::Content::Referencer';

sub File() {'App::KADR::AniDB::Content::File'}

has 'fids', (
	isa => ArrayRef [ID],
	lazy      => 1,
	predicate => '_has_fids',
	builder   => method {
		croak "No files set" unless $self->_has_files;
		[ map { $_->fid } @{ $self->files } ];
	});

has 'files',
	isa => ArrayRef [File],
	lazy      => 1,
	predicate => '_has_files',
	builder   => sub { list shift->ifiles };

has '_iter',
	lazy    => 1,
	clearer => 'reset_iterator',
	builder => sub { shift->ifiles };

method ifiles {
	croak "No fids set" unless $self->_has_fids;
	imap { $self->client->file($_) } $self->fids;
}

method parse($class: $str) {
	$class->new(fids => [ split /\|/, $str ]);
}

=head1 DESCRIPTION

L<App::KADR::AniDB::Content::FileSet> is a set of
L<App::KADR::AniDB::Content::File>s that match a request.

=attr C<fids>

	my $fids = $set->fids;
	$set = $set->fids([1]);

IDs of the files.

=attr C<files>

	my $files = $set->files;
	$set = $set->files([File->new(...)]);

Associated L<App::KADR::AniDB::Content::File> objects. Note that this response
is sent as a list of C<fids> so retrieving their full information could take a
long time. Consider using L</ifiles> instead.

=method C<ifiles>

An L<Iterator::Simple> iterator of associated
L<App::KADR::AniDB::Content::File> objects.

=method C<reset_iterator>

Reset the internal iterator used by the L</E<lt>E<gt>> and L</&{}> overloads.

=overload C<E<lt>E<gt>>

Next associated L<App::KADR::AniDB::Content::File> object from the internal
iterator.

=overload C<@{}>

Associated L<App::KADR::AniDB::Content::File> objects. See L</files>.

=overload C<&{}>

Next associated L<App::KADR::AniDB::Content::File> object from the internal
iterator.

=head1 SEE ALSO

http://wiki.anidb.info/w/UDP_API_Definition

=for Pod::Coverage File
