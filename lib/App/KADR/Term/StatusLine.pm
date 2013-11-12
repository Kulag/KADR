package App::KADR::Term::StatusLine;
use v5.10;
use Class::Load ();
use Moose::Role;
use Time::HiRes;

use common::sense;
use constant DUMB => (!$ENV{TERM} || $ENV{TERM} eq 'dumb');

requires qw(_to_text update);

has 'child_separator' => (is => 'rw', isa => 'Str', default => ': ');
has 'label' => (is => 'rw', isa => 'Str', predicate => 'has_label', trigger => sub { $_[0]->update_term });
has 'label_separator' => (is => 'rw', isa => 'Str', default => ' ');
has 'log_lines' => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has 'parent' => (is => 'rw', does => __PACKAGE__, predicate => 'has_parent');

has '_last_line' => (is => 'rw', isa => 'Str', default => '');
has '_last_update',
	default => Time::HiRes::time,
	is => 'rw',
	reader => 'last_update';

sub child {
	my ($self, $type, %params) = @_;
	$type = __PACKAGE__ . '::' . $type;
	Class::Load::load_class($type);
	$type->new(parent => $self, %params);
}

sub log {
	my ($self, $line) = @_;
	push @{$self->log_lines}, $line;
	$self->update_term;
}

sub to_text {
	my $self = shift;
	join '',
		($self->has_parent ? $self->parent->to_text . $self->parent->child_separator : ()),
		($self->has_label ? $self->label . $self->label_separator : ()),
		$self->_to_text;
}

sub update_term {
	my $self = shift;

	my @log = $self->_pop_all_log_lines;
	my $line = $self->to_text;

	return if !@log && $line eq $self->_last_line;

	# First blank the last status line to prevent trailing garbage.
	my $out = $self->_blank_line;

	# Print any "log" lines since the last status line update.
	$out .= join("\n", @log) . "\n" if @log;

	print $out . $line;
	$self->_last_line($line);
	$self->_last_update(Time::HiRes::time);

	$self;
}

sub finalize {
	my $self = shift;

	if (@_) {
		my $msg = shift;
		my $parent = $self->has_parent ? $self->parent->to_text . $self->parent->child_separator : '';
		say $self->_blank_line . $parent . $msg;
	}
	else {
		print $self->_blank_line if $self->_last_line;
	}

	$self->_last_line('');
}

*finalize_and_log = *finalize;

sub _pop_all_log_lines {
	my $self = shift;

	my @lines = (@{$self->log_lines}, ($self->has_parent ? $self->parent->_pop_all_log_lines : ()));
	$self->log_lines([]);
	return @lines;
}

sub _blank_line {
	return "\r\e[K" unless DUMB;

	my $len = length($_[0]->_last_line);
	$len ? "\r" . (' ' x $len) . "\r" : '';
}

sub DEMOLISH { $_[0]->finalize }

1;