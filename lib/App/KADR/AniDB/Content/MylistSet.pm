package App::KADR::AniDB::Content::MylistSet;
# ABSTRACT: AniDB information about a set of mylist entries

use App::KADR::AniDB::Content;
use List::Util qw(min);
use Method::Signatures::Simple;

use aliased 'App::KADR::AniDB::EpisodeNumber';

has 'aid', isa => ID;
field [qw(anime_title episodes)];

field [qw(
	eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd
	eps_with_state_deleted watched_eps
)],
	isa => EpisodeNumber;

sub max_age {
	return $_[0]->{''} // 91 * 24 * 60 * 60 unless ref $_[0];

	$_[0]{max_age}{ ref $_[1] ? join '-', %{ $_[1] } : $_[1] } //= do {
		my $tags = $_[0]->_max_age_tags;

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
}

sub max_age_is_dynamic {1}

# TODO: MooseX::SingletonMethod
# TODO: Defaults that are less KADR-centric.
method _max_age_tags {
	$self->{_max_age_tags} //= do {
		my $watched = $self->watched_eps
			or return { unwatched => 12 * 60 * 60 };

		my $on_hdd = $self->eps_with_state_on_hdd;
		return { watched => 91 * 24 * 60 * 60 } if $on_hdd->in($watched);

		{ watching => 2 * 60 * 60 };
	};
}

=head1 DESCRIPTION

MylistSet lists the episodes and groups corresponding to a mylist query which
matches more than one entry.

Unfortunatly, it is still missing qualifying data such as file versions,
and trying to narrow down results via mylist queries can be impossible in many
cases. I recommend using File and FileSet to narrow down results instead.

It's most useful property is probably its aggregate information about the
overall state of all the files in a user's mylist that correspond to a
particular episode number.

=head1 SEE ALSO

L<http://wiki.anidb.info/w/UDP_API_Definition>
