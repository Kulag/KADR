package App::KADR::AniDB::Role::Content::DynamicMaxAge;
# ABSTRACT: Role for contents that have dynamic max ages based on their attrs

use List::Util qw(min);
use MooseX::Role::Parameterized;
use JSON::XS;

no warnings;
no strict;
use common::sense;

parameter 'calculate',     isa => 'CodeRef', required => 1;
parameter 'class_default', isa => 'Int',     required => 1;

my $serializer = JSON::XS->new->utf8->canonical;

role {
	my $p             = shift;
	my $calculate     = $p->calculate;
	my $class_default = $p->class_default;

	method max_age => sub {
		unless (ref $_[0]) {
			return ref $_[1] ? $_[1]->{''} : $_[1] // $class_default;
		}

		$_[0]{max_age}{ ref $_[1] ? $serializer->encode($_[1]) : $_[1] }
			//= do {
			my $tags = $_[0]{max_age_tags} //= $_[0]->$calculate;

			# Tagged overrides
			if (ref $_[1] eq 'HASH') {
				my $override = pop;
				min(@$override{ keys %$tags }) // min values %$tags;
			}

			# None or a general override
			else {
				$_[1] // min values %$tags;
			}
			};
	};

	method max_age_is_dynamic => sub {1};
}
