package App::KADR::AniDB::Content::File;
# ABSTRACT: AniDB's file information

use App::KADR::AniDB::Content;
use Method::Signatures;

use aliased 'App::KADR::AniDB::EpisodeNumber';

use constant {
	STATUS_CRCOK  => 0x01,
	STATUS_CRCERR => 0x02,
	STATUS_ISV2   => 0x04,
	STATUS_ISV3   => 0x08,
	STATUS_ISV4   => 0x10,
	STATUS_ISV5   => 0x20,
	STATUS_UNC    => 0x40,
	STATUS_CEN    => 0x80,
};

field [qw(fid aid eid gid)];
field 'lid', isa => MaybeID, coerce => 1;
field [qw(
	other_episodes is_deprecated status
	size ed2k md5 sha1 crc32
	quality source audio_codec audio_bitrate video_codec video_bitrate video_resolution file_type
	dub_language sub_language length description air_date
)];
field 'episode_number', isa => EpisodeNumber;
field [qw(
	episode_english_name episode_romaji_name episode_kanji_name episode_rating episode_vote_count
	group_name group_short_name
)];

refer anime        => 'aid';
refer anime_mylist => 'aid', client_method => 'mylist_anime';
refer group        => 'gid';
refer mylist       => [ 'lid', 'fid' ], client_method => 'mylist_file';

sub crc_is_checked {
	my $status = $_[0]->status;
	!(($status & STATUS_CRCOK) || ($status & STATUS_CRCERR));
}

sub crc_is_bad { $_[0]->status & STATUS_CRCERR }
sub crc_is_ok  { $_[0]->status & STATUS_CRCOK }

for (
	[ is_unlocated => 'eps_with_state_unknown' ],
	[ is_on_hdd    => 'eps_with_state_on_hdd' ],
	[ is_on_cd     => 'eps_with_state_on_cd' ],
	[ is_deleted   => 'eps_with_state_deleted' ],
	[ watched      => 'watched_eps' ],
	)
{
	my ($suffix, $mylist_attr) = @$_;

	__PACKAGE__->meta->add_method("episode_$suffix", method {

		# Note: Mylist anime data is broken server-side,
		# only the min is provided.
		return unless my $ml = $self->anime_mylist;
		$self->episode_number->in_ignore_max($ml->$mylist_attr);
	});
}

method episode_number_padded {
	my $anime = $self->anime;
	my $epcount = $anime->episode_count || $anime->highest_episode_number;

	$self->episode_number->padded({ '' => length $epcount });
}

sub is_censored   { $_[0]->status & STATUS_CEN }
sub is_uncensored { $_[0]->status & STATUS_UNC }

method is_primary_episode {
	my $anime = $self->anime;

	# This is the only episode.
	$anime->episode_count == 1 && $self->episode_number eq 1

	# And this file contains the entire episode.
	# XXX: Handle files that span all episodes.
	&& !$self->other_episodes

	# And it has a generic episode name.
	# Usually equal to the anime_type except for movies where multiple
	# episodes may exist for split releases.
	&& do {
		my $epname = $self->episode_english_name;
		$epname eq $anime->type || $epname eq 'Complete Movie';
	};
}

sub parse {
	my $file = shift->App::KADR::AniDB::Role::Content::parse(@_);

	# XXX: Do this properly somewhere.
	$file->{video_codec} =~ s/H264\/AVC/H.264/g;
	$file->{audio_codec} =~ s/Vorbis \(Ogg Vorbis\)/Vorbis/g;

	$file;
}

sub version {
	my $status = $_[0]->status;
	  $status & STATUS_ISV2 ? 2
	: $status & STATUS_ISV3 ? 3
	: $status & STATUS_ISV4 ? 4
	: $status & STATUS_ISV5 ? 5
	:                         1;
}

=head1 METHODS

=head2 C<crc_is_bad>

Check if the CRC32 does not match the official source.

=head2 C<crc_is_checked>

Check if the CRC32 has been checked against the official source.

=head2 C<crc_is_ok>

Check if the CRC32 matches the official source.

=head2 C<episode_is_deleted>

Check if this file's episodes are deleted.

=head2 C<episode_is_external>

Check if this file's episodes are on external storage (CD, USB memory, etc).

=head2 C<episode_is_internal>

Check if this file's episodes are on internal storage (HDD, SSD, etc).

=head2 C<episode_watched>

Check if this file's episodes are watched.

=head2 C<episode_is_unlocated>

Check if this file's episodes' storage is unknown.

=head2 C<episode_number_padded>

File's episode number, with the numbers of normal episodes padded to match
length with the last episode.

=head2 C<is_censored>

Check if this file is censored.

=head2 C<is_primary_episode>

Check if this is the primary episode of the anime. An entire movie, or one-shot
OVA, for example.

=head2 C<is_uncensored>

Check if this episode was originally censored, but had decensoring applied.

=head2 C<version>

File version number.

=head1 REFERENCES

=head2 C<anime>
=head2 C<anime_mylist>
=head2 C<group>
=head2 C<mylist>

=head1 SEE ALSO

L<http://wiki.anidb.info/w/UDP_API_Definition>
