#!/usr/bin/env perl
use v5.10;
use common::sense;
use Test::Fatal;
use Test::More tests => 43;

use App::KADR::AniDB::EpisodeNumber;

sub EpisodeNumber { App::KADR::AniDB::EpisodeNumber->parse(@_) }

is EpisodeNumber('2'), '2', 'parses single digit';
is EpisodeNumber('2-4'), '2-4', 'parses range';
is EpisodeNumber('S1'), 'S1', 'single tagged';
is EpisodeNumber('O1-O2'), 'O1-O2', 'tagged range';
like exception { EpisodeNumber('O1-2') }, qr{Error parsing}, 'missing tag on second';
like exception { EpisodeNumber('C1-S2') }, qr{Error parsing}, 'wrong tag on second';
like exception { EpisodeNumber('1 - 2') }, qr{Error parsing}, 'whitespace';

is EpisodeNumber('2,4'), '2,4', 'multiple singles';
is EpisodeNumber('1-2,5-6'), '1-2,5-6', 'multiple ranges';
is EpisodeNumber('1,5-6'), '1,5-6', 'mixed multiple';
is EpisodeNumber('1-10,S1,C1,C3-C4'), '1-10,C1,C3-C4,S1', 'tagged and not';

is EpisodeNumber('01'), '1', 'leading zeros stripped';
is EpisodeNumber('S005'), 'S5', 'zeros stripped on tagged too';

is EpisodeNumber()->count, 0, 'null count';
is EpisodeNumber('2')->count, 1, 'single count';
is EpisodeNumber('2-5,8')->count, 5, 'range count';
is EpisodeNumber('2,S2')->count, 2, 'tagged count';
is EpisodeNumber('2')->count('S'), 0, 'null typed count of specials';
is EpisodeNumber('2,S2')->count(''), 1, 'typed count of normals';
is EpisodeNumber('2,S2')->count('S'), 1, 'typed count of specials';

is EpisodeNumber('1-10') & 1, '1', '1-10 contains 1';
is EpisodeNumber('1-10') & 10, '10', '1-10 contains 10';
is EpisodeNumber('1-10') & 7, '7', '1-10 contains 7';
ok !(EpisodeNumber('1-10') & 11), '1-10 does not contain 11';
ok !(EpisodeNumber('1-10') & 'S1'), '1-10 does not contain S1';

is EpisodeNumber('1-2,C3-C4') & 2, '2', '1-2,C3-C4 contains 2';
is EpisodeNumber('1-2,C3-C4') & "C3-C4", "C3-C4", '1-2,C3-C4 contains C3-C4';
is EpisodeNumber('1-2,C3-C4') & "C3-C5", "C3-C4", '1-2,C3-C4 contains C3-C4, not C3-C5';

is EpisodeNumber('1-2,C5-C6,S1-S5') & EpisodeNumber('C1-C3,C5,S8,S1,2-3'), '2,C5,S1', 'comparing instances works';

ok EpisodeNumber('5-6,S1,C4')->in('1-13,C1-C6,S1-S2'), 'in works';
ok !EpisodeNumber('5-6,S1,C4')->in('1'), 'in caches correctly';
is exception { EpisodeNumber('54')->in('1-13') }, undef, 'Doesn\'t mysteriously rethrow exceptions';

ok EpisodeNumber('1-13,C1-C6,S1-S2')->contains('5-6,S1,C4'), 'contains works';
ok !EpisodeNumber('1')->contains('5-6,S1,C4'), 'not contains works';
ok !EpisodeNumber('5-6,S1,C4')->contains(EpisodeNumber('1')), 'reverse ok';

ok EpisodeNumber('1-2')->in_ignore_max('1'), 'in_ignore_max works';
ok EpisodeNumber('S3-S4')->in_ignore_max('S3,S5'), 'in_ignore_max works on tags';
ok !EpisodeNumber('4-5')->in_ignore_max('1,3,5,7'), 'negative in_ignore_max works';

is EpisodeNumber(1)->padded(2), '01', 'padding ok';
is EpisodeNumber('2-3,S1')->padded(3), '002-003,S001', 'tagged padding ok';
is EpisodeNumber('1,S1')->padded({'' => 2}), '01,S1', 'unconfigured tags work ok';
is EpisodeNumber('2-3,S1,C1')->padded({'' => 3, S => 2, C => 1}), '002-003,C1,S01', 'per-tag padding';
like exception { EpisodeNumber(1)->padded([]) }, qr{Invalid padding configuration};
