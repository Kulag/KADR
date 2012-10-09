#!/usr/bin/env perl

use common::sense;
use Test::More tests => 2;

use App::KADR::Util qw(:pathname_filter);

is pathname_filter('/?"<>|:*!\\'), '∕?"<>|:*!\\', 'unix pathname filter';
is pathname_filter_windows('/?"<>|:*!\\'), '∕？”＜＞｜：＊!￥', 'windows pathname filter';
