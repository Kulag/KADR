package App::KADR::AniDB::Content::MylistEntry;
# ABSTRACT: AniDB's mylist entry information

use App::KADR::AniDB::Content -noclean => 1;
use Carp qw(croak);
use Const::Fast;

use enum qw(:STATE_=0 UNKNOWN HDD CD DELETED);

const my %STATE_NAMES => (
	STATE_UNKNOWN ,=> 'unknown',
	STATE_HDD     ,=> 'on HDD',
	STATE_CD      ,=> 'on removable media',
	STATE_DELETED ,=> 'deleted',
);

field [
	qw(lid fid eid aid gid date state viewdate storage source other filestate)
];

# File here will cause a reference loop. Not really fixable without async or
# some other way to weaken the ref after it's been returned to the caller.
refer anime => 'aid';
refer anime_mylist => 'aid', client_method => 'mylist_anime';
refer file  => 'fid';
refer group => 'gid';

sub state_name_for {
	my ($self, $state_id) = @_;
	$STATE_NAMES{$state_id} or croak 'No such mylist state: ' . $state_id;
}

=head1 REFERENCES

=head2 C<anime>
=head2 C<anime_mylist>
=head2 C<group>
=head2 C<mylist>

=head1 SEE ALSO

L<http://wiki.anidb.info/w/UDP_API_Definition>
