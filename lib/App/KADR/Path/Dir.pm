package App::KADR::Path::Dir;
# ABSTRACT: Path::Class::Dir for KADR, faster

use App::KADR::Path::File;
use App::KADR::Path::Util qw(expand_user);
use App::KADR::Util qw(_STRINGLIKE0);
use Carp qw(croak);
use common::sense;
use File::Spec::Memoized;
use Params::Util qw(_INSTANCE);

# Can't use stringify because overload sends extra params.
use overload '""' => sub { $_[0]{string} }, fallback => 1;

use parent 'Path::Class::Dir', 'App::KADR::Path::Entity';

use Class::XSAccessor
	getters => { stringify => 'string', volume => 'volume' },
	true    => ['is_dir'];

my %cache;

sub file_class() { 'App::KADR::Path::File' }

sub children {
	my ($self, %opts) = @_;

	my $dh = $self->open or die 'Can\'t open directory ' . $self . ': ' . $!;
	my $spec = $self->_spec;

	my $not_all   = !$opts{all};
	my $no_hidden = $opts{no_hidden};

	my ($updir, $curdir) = ($spec->updir, $spec->curdir) if $not_all;
	my $is_dir_exists = $self->can('is_dir_exists');

	my @out;
	while (defined(my $entry_name = $self->_decode_path(scalar $dh->read))) {
		next if $not_all && ($entry_name eq $updir || $entry_name eq $curdir);

		my $entry
			= $is_dir_exists->($spec->catfile($self, $entry_name))
			? $self->subdir($entry_name)
			: $self->file($entry_name);

		next if $no_hidden && $entry->is_hidden;

		push @out, $entry;
	}

	@out;
}

sub is_absolute {
	$_[0]->{is_absolute} //= $_[0]->SUPER::is_absolute;
}

sub is_hidden {
	$_[0]{dirs}[-1] =~ /^\./;
}

sub new {
	my $class = ref $_[0] ? ref shift : shift;

	# Compile args into a single string.
	my $path = do {
		if (@_ == 1) {

			# dir('dir')
			return $_[0] if ref $_[0] eq $class;

			# 'dir'
			if (length $_[0]) { expand_user $class->_spec, $_[0] }

			# ''
			elsif (defined $_[0]) { $class->_spec->rootdir }

			# If the only arg is undef, it's probably a mistake.
			# Without this special case here, we'd return the root directory,
			# which is a lousy thing to do to someone when they made a mistake.
			# Return nothing instead.
			else {return}
		}

		# ()
		elsif (@_ == 0) { $class->_spec->curdir }

		# 'dir', 'dir'
		else { expand_user $class->_spec, $class->_spec->catdir(@_) }
	};

	# Try to return an cached class for the path.
	$cache{$path} //= do {

		# This is a new path
		my $self = $class->Path::Class::Entity::new;
		my $spec = $class->_spec;

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
		: ($self->{_relative}{$self->_spec->curdir} //= $self->SUPER::relative);
}

sub subsumes {
	my ($self, $other) = @_;

	return $self->{_subsumes}{$other} if exists $self->{_subsumes}{$other};

	# Path::Class::Dir::subsumes does not detect the File class correctly
	if (ref $other) {
		if (_INSTANCE($other, 'Path::Class::Entity')) {
			$other = $other->dir if !$other->is_dir;
		}
		elsif (!_STRINGLIKE0($other)) {
			croak 'parameter to subsumes must be a dir, file, or stringlike';
		}
	}

	# Memoize
	$self->{_subsumes}{$other} //= $self->SUPER::subsumes($other);
}

0x6B63;

=head1 DESCRIPTION

App::KADR::Path::Dir is an optimized and memoized subclass of
L<Path::Class::Dir>. Identical logical paths use the same instance for
performance.

=head1 METHODS

App::KADR::Path::Dir inherits all methods from L<Path::Class::Dir> and
L<App::KADR::Path::Entity> and implements the following new ones.

=head2 C<new>

	my $dir = App::KADR::Path::Dir->new('/home', ...);
	my $dir = dir('/home', ...);

Turn a path into a dir. This static method is memoized.

=head2 C<children>

	my @children = $dir->children;
	my @children = $dir->children(all => 0, no_hidden => 0); # Defaults

Gather a list of this dir's children, filtered by options.
If C<all>, the current and parent directories will be included.
If C<no_hidden>, entries that are hidden will not be included.

=head2 C<file_class>

	my $file_class = $dir->file_class;

File class in use by this dir.

=head2 C<is_absolute>

	my $is_absolute = $dir->is_absolute;

Check if dir is absolute. This method is memoized.

=head2 C<is_hidden>

	my $is_hidden = $dir->is_hidden;

Check if dir is hidden.

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

	L<App::KADR::Path::File>, L<App::KADR::Path::Entity>, and L<Path::Class::Dir>
