#! /usr/bin/env perl

use Module::Build;

my $build = Module::Build->new(
	module_name => "App::KADR",
	license => "open_source",
	dist_abstract => "Kulag's AniDB Renamer",
	dist_version => 1,
	dist_author => 'Kulag <g.kulag@gmail.com>',
	script_files => "kadr.pl",
	requires => {
		"perl" => "5.14.0",
		"Class::Load" => "0",
		"common::sense" => "0",
		"DBD::SQLite" => "0",
		"DBI" => "0",
		"Digest::ED2K" => "0",
		"Digest::MD4" => "0",
		"enum" => "0",
		"Expect" => "0",
		"File::Copy" => "0",
		"File::Find" => "0",
		"File::Spec::Memoized" => "0",
		"List::AllUtils" => "0",
		"Moose" => "0",
		"MooseX::Getopt" => "0",
		"MooseX::SimpleConfig" => "0",
		"MooseX::Types::Stringlike" => "0",
		"Template" => "0",
		"YAML::XS" => "0",
	},
	meta_merge => {
		resources => {
			license => 'http://opensource.org/licenses/ISC',
		},
	},
);

$build->create_build_script;
