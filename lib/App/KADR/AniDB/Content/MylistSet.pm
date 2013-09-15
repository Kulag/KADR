package App::KADR::AniDB::Content::MylistSet;
# ABSTRACT: AniDB information about a set of mylist entries

use App::KADR::AniDB::Content;

use aliased 'App::KADR::AniDB::EpisodeNumber';

has 'aid', isa => ID;
field [qw(anime_title episodes)];

field [qw(
	eps_with_state_unknown eps_with_state_on_hdd eps_with_state_on_cd
	eps_with_state_deleted watched_eps
)],
	isa => EpisodeNumber;

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
