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
