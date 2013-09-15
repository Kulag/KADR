package App::KADR::Meta::Method::AttrInlined;
# ABSTRACT: Abstract base class for methods associated to an attribute

use App::KADR::Moose;
use MooseX::ABC;

extends 'App::KADR::Meta::Method::Inlined';

has 'attribute', isa => 'Moose::Meta::Attribute', required => 1, weak_ref => 1;
has 'definition_context',
	is      => 'lazy',
	builder => sub {
		my $attr = $_[0]->attribute;
		my $ctx = { %{ $attr->definition_context } };
		$ctx->{description}
			= $attr->_accessor_description($_[0]->name, $_[0]->accessor_type);
		$ctx;
	};
has 'package_name',
	builder => sub { $_[0]->attribute->associated_class->name };

requires qw(accessor_type);

=head1 DESCRIPTION

Sets up the attribute, definition context, and package name from the attribute
in C<-E<gt>new>. Uses the required C<accessor_type> to generate the method
description.

=head1 EXTENDS

L<App::KADR::Meta::Method::Inlined>

=head1 REQUIRED METHODS

=head2 C<accessor_type>

Type of accessor, e.g. "predicate".
