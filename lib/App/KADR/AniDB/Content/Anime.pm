package App::KADR::AniDB::Content::Anime;
# ABSTRACT: AniDB anime information

use App::KADR::AniDB::Content;

field [qw(
	aid dateflags year type
	romaji_name kanji_name english_name
	episode_count highest_episode_number air_date end_date
	rating vote_count temp_rating temp_vote_count review_rating review_count is_r18
	special_episode_count credits_episode_count other_episode_count trailer_episode_count parody_episode_count
)];

refer mylist => 'aid', client_method => 'mylist_anime';

sub parse {
	my $anime = shift->App::KADR::AniDB::Role::Content::parse(@_);
	for my $field (qw(rating temp_rating review_rating)) {
		$anime->{$field} = $anime->{$field} / 100.0 if $anime->{$field};
	}
	$anime;
}

=head1 REFERENCES

=head2 C<mylist>

This anime's mylist set information.

=head1 SEE ALSO

http://wiki.anidb.info/w/UDP_API_Definition
