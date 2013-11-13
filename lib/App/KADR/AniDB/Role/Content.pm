package App::KADR::AniDB::Role::Content;
# ABSTRACT: Role for content classes

use App::KADR::Moose::Role;
use List::MoreUtils qw(mesh);
use List::UtilsBy qw(nsort_by);

use aliased 'App::KADR::AniDB::Meta::Attribute::Field';

has 'updated',
	is      => 'ro',
	isa     => 'Int',
	default => sub {time};

sub parse {
	my ($class, $str) = @_;
	my @fields
		= map    { $_->does(Field) ? $_->name : () }
		nsort_by { $_->insertion_order } $class->meta->get_all_attributes;
	my @values = (split /\|/, $str)[ 0 .. @fields - 1 ];
	$class->new(mesh @fields, @values);
}

=head1 DESCRIPTION

This is the base role for all content classes. When you use
L<App::KADR::AniDB::Content> in a class, this role will be applied.

It provides a default parser and the cache time shared by content classes.

=head1 ATTRIBUTES

=head2 C<updated>

	$epoch = $content->updated;

When this content was cached.

=head1 CLASS METHODS

=head2 C<parse>

	$file = File->parse($str);

Parse a new content object from a string.

=head1 SEE ALSO

App::KADR::AniDB::Content
