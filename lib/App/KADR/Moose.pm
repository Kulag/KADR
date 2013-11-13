package App::KADR::Moose;
# ABSTRACT: Moose with KADR policy

use App::KADR::Moose::Exporter also => [qw(Moose App::KADR::Moose::Policy)];

=head1 SYNOPSIS

	use App::KADR::Moose;

=head1 DESCRIPTION

L<App::KADR::Moose> makes your class a Moose class with some default imports
and attribute options.

=head1 IMPORT PARAMETERS

L<App::KADR::Moose> inherits all import parameters from
L<App::KADR::Moose::Policy>.

=head1 SEE ALSO

App::KADR::Moose::Policy
App::KADR::Moose::Role
