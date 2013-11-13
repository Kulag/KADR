package App::KADR::AniDB::Meta::Attribute::ContentReference;
# ABSTRACT: Trait for attributes that refer to other content

use App::KADR::Moose::Role -attr => {is => 'ro'};
use Carp qw(croak);
use Moose::Util::TypeConstraints;
use strict 'refs';

with 'App::KADR::Meta::Attribute::DoNotSerialize';
with 'MooseX::RelatedClasses' => { name => 'Builder' };

has 'client_method', isa => 'Str', lazy => 1, default => sub { $_[0]->name };
has 'keys', isa => 'ArrayRef[Str]', required => 1;

# Because Roles don't allow +attr definitions.
before _process_options => method($name, $opts) {
	$opts->{is} //= 'lazy';
};

after install_accessors => sub { shift->install_builder(@_) };
after remove_accessors  => sub { shift->remove_builder(@_) };

method install_builder {
	my @keys  = @{ $self->keys };
	my $class = $self->associated_class;

	for (@keys) {
		croak "No such attribute '$_' in " . $class->name
			unless $class->find_attribute_by_name($_);
	}

	my $name = '_build_' . $self->name;
	my $meth = $self->builder_class->new(attribute => $self, name => $name);

	$class->add_method($name, $meth);
	$self->associate_method($meth);
}

method remove_builder {
	$self->associated_class->remove_method($self->builder);
}

=head1 DESCRIPTION

This trait handles lazy acquisition of related content via their IDs.

See L<App::KADR::AniDB::Content> for examples.

=head2 C<client_method>

	$method_name = $attr->client_method;

AniDB client method to call. Defaults to the attribute name.

=head2 C<keys>

	@keys = @{ $attr->keys };

Attributes in the associated class used to lookup content.

=head1 METHODS

=head2 C<install_builder>

Install attribute builder into associated class.

=head2 C<remove_builder>

Remove attribute builder from associated class.

=head1 SEE ALSO

App::KADR::AniDB::Content
