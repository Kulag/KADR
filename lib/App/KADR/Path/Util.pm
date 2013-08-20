package App::KADR::Path::Util;

use common::sense;
use File::HomeDir;
use Sub::Exporter::Progressive -setup => { exports => ['expand_user'] };

sub expand_user {
	my ($spec, $path) = @_;

	return $path unless $path =~ /^~/;

	my @parts = $spec->splitdir($path);
	my $user  = shift @parts;
	my $home
		= $user eq '~'
		? File::HomeDir->my_home
		: File::HomeDir->users_home($user =~ s/^~//r)
		or die "No homedir for user: $user";

	$spec->catdir($home, @parts);
}

0x6B63;
