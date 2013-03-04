package App::KADR::AniDB::UDP::Meta::Attribute::Trait::Field;

use App::KADR::Moose::Role;

before _process_options => sub {
	my ($class, $name, $options) = @_;

	unless ($options->{required}) {
		$options->{predicate} //= '_has_' . $name =~ s/^_//r;
	}

	return;
};
