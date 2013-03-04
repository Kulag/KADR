package App::KADR::AniDB::UDP::Meta::Class::Trait::Message;

use App::KADR::Moose::Role;
use Carp qw(croak);
use Class::Load qw(load_class);

# XXX: Can't require something from a role.
# XXX: I actually want to define it here and have the role set a default.
# requires qw(stringifier_class);

around _immutable_options => sub {
	my ($orig, $self) = (shift, shift);

	(
		inline_stringifier => 1,
		stringifier_class  => $self->stringifier_class,
		$self->$orig(@_),
	);
};

after _install_inlined_code => sub {
	my ($self, %args) = @_;

	$self->_inline_stringifier(%args) if $args{inline_stringifier};
};

sub _inline_stringifier {
	my ($self, %args) = @_;
	my $for_class = $self->name;
	my $stringifier_class = $args{stringifier_class};

	# Don't overwrite without permission.
	if ($self->has_method('stringify') && !$args{replace_stringifier}) {
		warn "Not inlining a stringifier for $for_class because"
			. ' it defines its own stringifier';
		return;
	}

	load_class $stringifier_class;

	my $stringifier = $stringifier_class->new(
		definition_context => {
			description => "stringifier ${for_class}::stringify",
			file => $args{file},
			line => $args{line},
		},
		is_inline    => 1,
		associated_metaclass => $self,
		name         => 'stringify',
		options      => \%args,
		package_name => $for_class,
		debug => 1,
	);

	if ($stringifier->can_be_inlined) {
		$self->add_method(stringify => $stringifier);
		$self->_add_inlined_method($stringifier);
	}
}
