package App::KADR::Path::File;
# ABSTRACT: Path::Class::Dir for KADR, faster

use App::KADR::Path::Dir;
use Carp 'croak';
use common::sense;
use File::Spec::Memoized;

use parent 'Path::Class::File', 'App::KADR::Path::Entity';

use Class::XSAccessor
	getters => { basename => 'file' },
	false   => ['is_dir'];

my %cache;

sub dir_class() { 'App::KADR::Path::Dir' }

sub has_dir { defined $_[0]{dir} }

sub is_absolute {
	$_[0]->{is_absolute} //= $_[0]->SUPER::is_absolute;
}

sub is_hidden {
	$_[0]{file} =~ /^\./;
}

sub new {
	my $class = shift;
	my $base;

	croak 'No path provided to File->new' unless @_;

	# Split dir and basename from args.
	my $dir = do {
		(my $volume, my $dirs, $base) = $class->_spec->splitpath(pop);

		# dir('dir'), 'dir/file'
		if (length $dirs) {
			# Omit volume when possible to get the fast one-arg new.
			$class->dir_class->new(@_, (length $volume ? $volume : ()), $dirs);
		}

		# dir('dir'), 'file'
		elsif (@_ == 1 && ref $_[0] eq dir_class) { $_[0] }

		# 'dir', 'file'
		else { $class->dir_class->new(@_) }
	};

	# Check for cached file
	$cache{ defined $dir and $dir->stringify }->{$base} //= do {
		my $self = $class->Path::Class::Entity::new;

		$self->{dir}  = $dir;
		$self->{file} = $base;

		$self;
	};
}

sub relative {
	my $self = shift;
	@_
		? $self->SUPER::relative(@_)
		: $self->{_relative}{$self->_spec->curdir} //= $self->SUPER::relative;
}

sub stringify {
	$_[0]{stringify}
		//= defined $_[0]{dir}
		? $_[0]->_spec->catfile($_[0]{dir}->stringify, $_[0]{file})
		: $_[0]{file};
}

0x6B63;

=head1 DESCRIPTION

L<App::KADR::Path::File> is an optimized and memoized subclass of
L<Path::Class::File>. Identical logical paths use the same instance for
performance.

=head1 METHODS

L<App::KADR::Path::File> inherits all methods from L<Path::Class::File> and
L<App::KADR::Path::Entity> and implements the following new ones.

=head2 C<new>

	my $file = App::KADR::Path::File->new('/home', ...);
	my $file = file('/home', ...);

Turn a path into a file. This static method is memoized.

=head2 C<dir_class>

	my $dir_class = $file->dir_class;

Directory class in use.

=head2 C<is_absolute>

	my $is_absolute = $file->is_absolute;

Check if file is absolute. This method is memoized.

=head2 C<is_hidden>

	my $is_hidden = $file->is_hidden;

Check if file is hidden.

=head2 C<relative>

	my $relative_file = $file->relative;
	my $relative_file = $file->relative('..');
	my $relative_file = $file->relative(dir(''));

Turn file into a L<App::KADR::Path::File> relative to another directory.
The other directory defaults to the current directory.

=head2 C<stringify>

	my $string = $file->stringify;
	my $string = $file . '';

Turn file into a string. This method is memoized.

=head1 SEE ALSO

	L<App::KADR::Path::Dir>, L<App::KADR::Path::Entity>, and L<Path::Class::File>
