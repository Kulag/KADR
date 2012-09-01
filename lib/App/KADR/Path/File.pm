package App::KADR::Path::File;
use Moose;

use App::KADR::Path::Dir;

extends 'Path::Class::File';

sub dir_class { 'App::KADR::Path::Dir' }

sub is_absolute {
	$_[0]->{is_absolute} //= $_[0]->SUPER::is_absolute;
}

sub relative {
	my $self = shift;
	@_
		? $self->SUPER::relative(@_)
		: $self->{_relative}{$self->_spec->curdir} //= $self->SUPER::relative;
}

sub stringify {
	$_[0]->{_stringify} //= $_[0]->SUPER::stringify;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 NAME

L<App::KADR::Path::File> - like L<Path::Class::File>, but faster

=head1 DESCRIPTION

L<App::KADR::Path::File> is an optimized and memoized subclass of
L<Path::Class::File>.

=head1 METHODS

L<App::KADR::Path::File> inherits all methods from L<Path::Class::File> and
implements the following new ones.

=head2 C<dir_class>

	my $dir_class = $file->dir_class;

Dir class in use by this file.

=head2 C<is_absolute>

	my $is_absolute = $file->is_absolute;

Check if file is absolute. This method is memoized.

=head2 C<relative>

	my $relative_file = $file->relative;
	my $relative_file = $file->relative('..');

Turn file into a file relative to another dir.
The other file defaults to the current directory.

=head2 C<stringify>

	my $string = $file->stringify;
	my $string = $file . '';

Turn file into a string. This method is memoized.

=head1 SEE ALSO

	L<App::KADR::Path::Dir>, L<Path::Class::File>
