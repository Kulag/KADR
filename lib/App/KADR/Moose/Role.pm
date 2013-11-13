package App::KADR::Moose::Role;
# ABSTRACT: Moose::Role with KADR policy

use App::KADR::Moose::Exporter also => [qw(Moose::Role App::KADR::Moose::Policy)];

=head1 SYNOPSIS

	use App::KADR::Moose::Role;

=head1 DESCRIPTION

App::KADR::Moose::Role makes your class a Moose role with some with some
default imports and attribute options.

=head1 IMPORT PARAMETERS

L<App::KADR::Moose::Role> inherits all import parameters from
L<App::KADR::Moose::Policy>.

=head1 SEE ALSO

App::KADR::Moose
App::KADR::Moose::Policy
