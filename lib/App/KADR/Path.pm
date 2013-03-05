package App::KADR::Path;
# ABSTRACT: Path::Class for KADR

use common::sense;
use Class::Load ();
use File::Spec::Memoized;
use Sub::Exporter -setup => {
	exports => [
		dir => \&_build_dir,
		file => \&_build_file,
	],
};

for my $entity (qw(Dir File)) {
	*{'_build_' . lc $entity} = sub {
		my $class = $_[0] . '::' . $entity;
		Class::Load::load_class($class);
		sub { $class->new(@_) };
	};
}

0x6B63;
