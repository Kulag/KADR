package App::KADR::AniDB::Role::Content::Referencer;
# ABSTRACT: Role for content classes that reference other content

use App::KADR::Moose::Role;
use MooseX::LazyRequire;

has 'client',
	lazy_required => 1,
	traits => ['App::KADR::Meta::Attribute::DoNotSerialize'],
	weak_ref => 1;

=head1 DESCRIPTION

This is a base role for classes which refer to other content classes. It is
applied when you use L<App::KADR::AniDB::Content>C<::refer> to setup a content
relation.

=head1 ATTRIBUTES

=head2 C<client>

	$client = $content->client;

The client that retrieved this content object.

=head1 SEE ALSO

C<App::KADR::AniDB::Content>, C<App::KADR::AniDB::UDP::Client>
