package App::KADR::AniDB::UDP::Message::Sugar;

use aliased 'App::KADR::AniDB::UDP::Meta::Attribute::Trait::Field';
use common::sense;
use List::AllUtils qw(uniq);
use Moose::Exporter ();
use Moose::Util ();

Moose::Exporter->setup_import_methods(
	with_meta => ['has_field'],
);

sub has_field {
	my ($meta, $name) = (shift, shift);

	Moose->throw_error('Usage: has_field \'name\' => (key => value, ...)')
		unless @_ % 2 == 0;

	my %options = (definition_context => Moose::Util::_caller_info(), @_);

	$options{traits} = [ uniq @{$options{traits}}, Field ];

	for (ref $name eq 'ARRAY' ? @$name : $name) {
		$meta->add_attribute($_, %options);
	}
}

1;
