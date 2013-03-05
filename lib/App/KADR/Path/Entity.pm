package App::KADR::Path::Entity;
# ABSTRACT: Path::Class::Entity for KADR, faster

use Encode;
use Moose;

sub exists { -e $_[0] }

sub is_dir_exists { -d $_[0] }

sub is_file_exists { -f $_[0] }

sub size { -s $_[0] }

sub _decode_path {
	decode_utf8 $_[1];
}

0x6B63;

=head1 SYNOPSIS

	$path->exists         == -e $path;
	$path->is_dir_exists  == -d $path;
	$path->is_file_exists == -f $path;
	$path->size           == -s $path;

=head1 DESCRIPTION

A "placeholder" of sorts to allow portable operations on Unicode paths to be
added later.
