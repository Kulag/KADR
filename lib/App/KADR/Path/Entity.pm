package App::KADR::Path::Entity;
# ABSTRACT: Path::Class::Entity for KADR, faster

use common::sense;
use Encode;

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
