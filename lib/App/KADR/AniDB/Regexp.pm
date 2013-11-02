package App::KADR::AniDB::Regexp;
# ABSTRACT: Common regexes for anidb

use common::sense;
use Const::Fast;

use parent 'Exporter';

our @EXPORT_OK = qw($tag_rx);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

const our $tag_rx => qr/[^\d\x00\s\n] [^\s\n]{0,254}/sx;

0x6B63;

=head1 SYNOPSIS

	use App::KADR::AniDB::Regexp qw(:all);

	my $check = $foo =~ /^ $tag_rx $/x;

=head1 EXPORTS

=head2 C<$tag_rx>

	my $check = $foo =~ /^ $tag_rx $/x;

Regex for strings which are valid tags for use on AniDB's UDP API.
