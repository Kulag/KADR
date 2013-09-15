package App::KADR::KnownFile;
# ABSTRACT: Cached info KADR has calculated about a file

use App::KADR::Moose;

has [qw(avdumped ed2k filename size mtime)];
