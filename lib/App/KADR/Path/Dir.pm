package App::KADR::Path::Dir;
use Moose;

use App::KADR::Path::File;

extends 'Path::Class::Dir';

sub file_class { 'App::KADR::Path::File' }

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

sub subsumes {
	my ($self, $other) = @_;

	# Path::Class::Dir::subsumes does not detect the File class correctly
	$other = $other->dir if blessed $other && $other->isa('Path::Class::File');

	# Memoize
	my $key = $other . '';
	$self->{_subsumes}{$key} = $self->SUPER::subsumes($key) unless exists $self->{_subsumes}{$key};
	$self->{_subsumes}{$key}
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
