package App::KADR::Path::Entity;
# ABSTRACT: Path::Class::Entity for KADR, faster

use common::sense;
use Encode;
use Params::Util qw(_INSTANCE);
use Scalar::Util qw(refaddr);

use overload '<=>' => 'abs_cmp', fallback => 1;

sub abs_cmp {
	return 1 unless defined $_[1];

	# Same object.
	# Use refaddr since this method is used as the == overload fallback.
	return 0 if refaddr $_[0] == refaddr $_[1];

	my $a = shift;
	my $b = _INSTANCE($_[0], __PACKAGE__) || $a->new($_[0]);

	# Different entity subclass.
	return ref $a cmp ref $b if ref $a ne ref $b;

	return $a->absolute cmp $b->absolute;
}

sub exists         { -e $_[0] }
sub is_dir_exists  { -d $_[0] }
sub is_file_exists { -f $_[0] }

sub size { $_[0]->stat->size }

sub stat     { $_[0]{stat} //= File::stat::stat($_[0]->stringify) }
sub stat_now { $_[0]{stat} = File::stat::stat($_[0]->stringify) }

sub _decode_path {
	decode_utf8 $_[1];
}

0x6B63;

=head1 SYNOPSIS

	$path->exists         == -e $path;
	$path->is_dir_exists  == -d $path;
	$path->is_file_exists == -f $path;
	$path->size           == -s $path;

	my $stat = $path->stat; # Cached
	my $stat = $path->stat_now; # Updates cache

=head1 DESCRIPTION

A "placeholder" of sorts to allow portable operations on Unicode paths to be
added later.

=head1 METHODS

=head2 C<abs_cmp>

	my $cmp = $dir->abs_cmp('/home');
	my $cmp = $dir->abs_cmp(dir());
	my $cmp = $dir <=> '/home';

Compare two path entities of the same subclass as if both are relative to
the current working directory.
