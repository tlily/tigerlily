package LC::User;

use strict;
use Carp;
use Text::Abbrev;

=head1 NAME

LC::User - User command manager.

=head1 DESCRIPTION

This module manages user commands (%commands), and help for these commands.

=head2 FUNCTIONS
=over 10
=cut


=item new()

Creates a new LC::User object.  Takes "ui" and "event" arguments.

  $ucmd = LC::User->new(ui    => $ui,
                        event => $event);

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};
	my %arg   = @_;

	$self->{event}    = $arg{event}
	  or croak "Required parameter \"event\" missing.";

	$self->{commands} = {};
	$self->{abbrevs}  = {};
	$self->{help}     = {};
	$self->{shelp}    = {};

	$self->{event}->event_r(type  => "user_input",
				order => "after",
				call  => sub { $self->input_handler(@_); });

	bless $self, $class;
}


=item command_r($name, $sub)

Registers a new %command.

  $user->command_r("quit" => sub { exit; });

=cut

sub command_r {
	my($self, $command, $sub) = @_;
	$self->{commands}->{$command} = $sub;
	%{$self->{abbrevs}} = abbrev keys %{$self->{commands}};
}


=item command_u($name)

Deregisters an existing %command.

  $user->command_u("quit");

=cut

sub command_u {
	my($self, $command) = @_;
	delete $self->{commands}->{$command};
	%{$self->{abbrevs}} = abbrev keys %{$self->{commands}};
}


sub input_handler {
	my($self, $e, $h) = @_;

	return unless ($e->{text} =~ /^\s*%(\w+)\s*(.*)/);
	my $command = $self->{abbrevs}->{$1};

	unless ($command) {
		$e->{ui}->print("(The \"$1\" command is unknown.)\n");
		return 1;
	}

	$self->{commands}->{$command}->($e->{ui}, $2);
	return 1;
}


=back
=cut

1;
