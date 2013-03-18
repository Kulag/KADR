package App::KADR::Pid;
# ABSTRACT: Pid file manipulation

use App::KADR::Moose;
use File::Spec::Functions qw(catfile tmpdir);
use File::Basename 'basename';

# XXX: App::KADR::Moose loading common::sense is broken.
no warnings;
use common::sense;

has 'file',
	default  => catfile(tmpdir, basename($0) . '.pid'),
	is       => 'ro',
	required => 1;

has 'pid',
	builder => 1,
	is      => 'rwp',
	lazy    => 1;

sub import {
	if ($_[1] eq '-onlyone') {
		my $pid = $_[0]->new;

		if ($pid->is_running) {
			printf "Another instance of %s is already running. (pid: %d)\n",
				basename($0),
				$pid->pid;
			exit 1;
		}

		$pid->write;
	}
}

sub is_running {
	return unless my $pid = $_[0]->pid;
	kill(0, $pid) ? $pid : ();
}

sub remove {
	unlink $_[0]->file;
}

sub write {
	my ($self, $pid) = @_;
	$self->_set_pid($pid //= $$);
	open my $fh, '>', $self->file or die $!;
	$fh->print($pid);
	close $fh;
	return;
}

sub _build_pid {
	open my $fh, '<', $_[0]->file or return;
	chomp(my $pid = <$fh>);
	close $fh;
	$pid;
}

=head1 SYNOPSIS

	# Permit only one instance to run.
	use App::KADR::Pid -onlyone;

	# Similar
	use App::KADR::Pid;

	my $pid = App::KADR::Pid->new(file => "/tmp/$0.pid");
	die "already running!" if $pid->is_running;
	$pid->write;

=head1 ATTRIBUTES

L<App::KADR::Pid> implements the following attributes.

=head2 C<file>

	my $file = $pidfile->file;

Process ID file. Defaults to the application basename in /tmp.

=head2 C<pid>

	my $pid = $pidfile->pid;

The process ID in the file.

=head1 METHODS

=head2 C<is_running>

	my $pid = $pidfile->is_running;

Returns the pid is the process is running, otherwise undef.

=head2 C<remove>

	my $success = $pidfile->remove;

Delete the pid file.

=head2 C<write>

	$pidfile->write; # Current process ID.
	$pidfile->write($pid);

Write a process ID to the pidfile. Defaults to the current process' ID.
