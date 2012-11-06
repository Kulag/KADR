#!/usr/bin/env perl

use common::sense;
use FindBin;
use Test::More;

use lib "$FindBin::RealBin/../lib";
use App::KADR::Collate;

my @types = qw(none ascii unicode unicodeicu);
plan tests => @types * 4;

for my $type (@types) {
	my $collate = App::KADR::Collate->new($type);

	is_deeply [$collate->sort], [], "$type - sorting an empty list returns an empty list";
	is_deeply [$collate->sort(sub {})], [], "$type - sorting an empty list with a coderef returns an empty list";
	is_deeply [$collate->sort(qw(a b c))], [qw(a b c)], "$type - sorting alphabetical list returns the same";
	is_deeply [$collate->sort(sub { ord $_ }, qw(a b c))], [qw(a b c)], "$type - sorting alphabetical list with keygen returns the same";
}
