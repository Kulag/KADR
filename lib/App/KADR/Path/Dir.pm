package App::KADR::Path::Dir;
use Moose;

use App::KADR::Path::File;

extends 'Path::Class::Dir';

my %cache;

sub file_class() { 'App::KADR::Path::File' }

sub is_absolute {
	$_[0]->{is_absolute} //= $_[0]->SUPER::is_absolute;
}

sub new {
	my $class = ref $_[0] ? ref shift : shift;

	if (@_ == 1) {
		# If the only arg is undef, it's probably a mistake. Without this
		# special case here, we'd return the root directory, which is a
		# lousy thing to do to someone when they made a mistake. Return
		# undef instead.
		return if !defined $_[0];

		# No-op
		return $_[0] if ref $_[0] eq $class;
	}

	my $spec = $class->_spec;

	# Compile args into single string
	my $path
		= !@_         ? $spec->curdir
		: $_[0] eq '' ? $spec->rootdir
		:               $spec->catdir(@_);

	# Try to return an cached class for the path.
	$cache{$path} //= do {
		# This is a new path
		my $self = $class->Path::Class::Entity::new;
		$self->{string} = $path;

		# Volume
		($self->{volume}, my $dirs) = $spec->splitpath($path, 1);

		# Dirs
		$self->{dirs} = [ $spec->splitdir($dirs) ];

		$self;
	};
}

sub relative {
	my $self = shift;
	@_
		? $self->SUPER::relative(@_)
		: $self->{_relative}{$self->_spec->curdir} //= $self->SUPER::relative;
}

sub stringify { $_[0]{string} }

sub subsumes {
	my ($self, $other) = @_;

	# Path::Class::Dir::subsumes does not detect the File class correctly
	$other = $other->dir if blessed $other && !$other->is_dir;

	# Memoize
	my $key = $other . '';
	$self->{_subsumes}{$key} = $self->SUPER::subsumes($other) unless exists $self->{_subsumes}{$key};
	$self->{_subsumes}{$key}
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 NAME

App::KADR::Path::Dir - like L<Path::Class::Dir>, but faster

=head1 DESCRIPTION

App::KADR::Path::Dir is an optimized and memoized subclass of
L<Path::Class::Dir>. Identical logical paths use the same instance for
performance.

=head1 METHODS

App::KADR::Path::Dir inherits all methods from L<Path::Class::Dir> and
implements the following new ones.

=head2 C<new>

	my $dir = App::KADR::Path::Dir->new('/home', ...);
	my $dir = dir('/home', ...);

Turn a path into a dir. This static method is memoized.

=head2 C<file_class>

	my $file_class = $dir->file_class;

File class in use by this dir.

=head2 C<is_absolute>

	my $is_absolute = $dir->is_absolute;

Check if dir is absolute. This method is memoized.

=head2 C<relative>

	my $relative_dir = $dir->relative;
	my $relative_dir = $dir->relative('..');

Turn dir into a dir relative to another dir.
The other dir defaults to the current directory.

=head2 C<stringify>

	my $string = $dir->stringify;
	my $string = $dir . '';

Turn dir into a string. This method is memoized.

=head2 C<subsumes>

	my $subsumes = $dir->subsumes(dir());
	my $subsumes = $dir->subsumes(file('foo'));

Check if another dir or file is logically contained within this dir.
This method is memoized.

=head1 SEE ALSO

	L<App::KADR::Path::File>, L<Path::Class::Dir>
