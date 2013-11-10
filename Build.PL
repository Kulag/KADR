
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Manage your anime collection with anidb",
  "dist_author" => [
    "Kulag <g.kulag\@gmail.com>"
  ],
  "dist_name" => "App-KADR",
  "dist_version" => "0.001",
  "license" => "mit",
  "module_name" => "App::KADR",
  "recommends" => {
    "Unicode::ICU::Collator" => 0,
    "YAML::XS" => 0
  },
  "recursive_test_files" => 1,
  "requires" => {
    "Carp" => 0,
    "Class::Factory" => 0,
    "Class::Load" => 0,
    "Class::MOP::Method::Inlined" => 0,
    "Class::XSAccessor" => 0,
    "Const::Fast" => 0,
    "DBD::SQLite" => 0,
    "DBI" => 0,
    "Devel::Pragma" => "0.60",
    "Digest::ED2K" => 0,
    "Encode" => 0,
    "Exporter" => 0,
    "File::Basename" => 0,
    "File::Copy" => 0,
    "File::Find" => 0,
    "File::HomeDir" => 0,
    "File::Spec::Functions" => 0,
    "File::Spec::Memoized" => 0,
    "FindBin" => 0,
    "Guard" => 0,
    "Hook::AfterRuntime" => 0,
    "IO::Socket" => 0,
    "IO::Uncompress::Inflate" => 0,
    "Lingua::EN::Inflect" => 0,
    "List::AllUtils" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "List::UtilsBy" => 0,
    "Method::Signatures" => 0,
    "Module::Find" => 0,
    "Mojo::EventEmitter" => 0,
    "Moose" => "1.9900",
    "Moose::Exporter" => 0,
    "Moose::Meta::Method" => 0,
    "Moose::Role" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::ABC" => 0,
    "MooseX::AlwaysCoerce" => 0,
    "MooseX::Attribute::Chained" => 0,
    "MooseX::AttributeShortcuts" => 0,
    "MooseX::Getopt" => 0,
    "MooseX::LazyRequire" => 0,
    "MooseX::NonMoose" => 0,
    "MooseX::RelatedClasses" => 0,
    "MooseX::Role::Parameterized" => 0,
    "MooseX::SimpleConfig" => 0,
    "MooseX::StrictConstructor" => "0.19",
    "MooseX::Types" => 0,
    "MooseX::Types::Common::Numeric" => 0,
    "MooseX::Types::Common::String" => 0,
    "MooseX::Types::LoadableClass" => 0,
    "MooseX::Types::Moose" => 0,
    "MooseX::Types::Stringlike" => 0,
    "POSIX" => 0,
    "Params::Util" => 0,
    "Path::Class::Dir" => 0,
    "Path::Class::File" => 0,
    "Scalar::Defer" => 0,
    "Scalar::Util" => 0,
    "Sub::Exporter" => 0,
    "Sub::Exporter::Progressive" => 0,
    "Text::Xslate" => 0,
    "Time::HiRes" => 0,
    "Unicode::Collate" => 0,
    "YAML" => 0,
    "aliased" => 0,
    "common::sense" => 0,
    "constant" => 0,
    "enum" => 0,
    "lib" => 0,
    "namespace::autoclean" => 0,
    "open" => 0,
    "overload" => 0,
    "parent" => 0,
    "perl" => "v5.14.0",
    "strict" => 0,
    "true" => 0,
    "warnings" => 0
  },
  "script_files" => [
    "bin/kadr",
    "bin/kadr-not-in-anidb"
  ],
  "share_dir" => {
    "dist" => "share"
  },
  "test_requires" => {
    "Eval::Closure" => 0,
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Test::Fatal" => 0,
    "Test::More" => "0.88",
    "Test::Trap" => 0
  }
);


my %fallback_build_requires = (
  "Eval::Closure" => 0,
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "Module::Build" => "0.3601",
  "Test::Fatal" => 0,
  "Test::More" => "0.88",
  "Test::Trap" => 0
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

if ( $^O eq 'MSWin32' ) {
	$module_build_args{requires}{'Win32'} = '0';
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
