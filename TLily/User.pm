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

	$self->command_r(help => \&help_command);
	$self->shelp_r(help => "Display help pages.");
	$self->help_r(commands => \&command_help);
	$self->help_r(help => '
Welcome to Tigerlily!

Tigerlily is a client for the lily CMC, written entirely in 100% pure Perl.

For a list of commands, try "/help commands".
');

	return $self;
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


sub shelp_r {
	my($self, $command, $help) = @_;
	$self->{shelp}->{$command} = $help;
}


sub help_r {
	my($self, $topic, $help) = @_;
	if (!ref($help)) {
		# Eliminate all leading newlines, and enforce only one trailing
		$help =~ s/^\n*//s; $help =~ s/\n*$/\n/s;
	}
	$self->{help}->{$topic} = $help;
}


sub input_handler {
	my($self, $e, $h) = @_;

	return unless ($e->{text} =~ /^\s*%(\w+)\s*(.*?)\s*$/);
	my $command = $self->{abbrevs}->{$1};

	unless ($command) {
		$e->{ui}->print("(The \"$1\" command is unknown.)\n");
		return 1;
	}

	$self->{commands}->{$command}->($self, $e->{ui}, $2);
	return 1;
}


sub command_help {
	my($self, $ui, $arg) = @_;

	$ui->indent("? ");
	$ui->print("Tigerlily client commands:\n");

	my $c;
	foreach $c (sort keys %{$self->{commands}}) {
		$ui->printf("  %%%-15s", $c);
		$ui->print($self->{shelp}->{$c}) if ($self->{shelp}->{$c});
		$ui->print("\n");
	}

	$ui->indent("");
}


sub help_command {
	my($self, $ui, $arg) = @_;
	$arg = "help" if ($arg eq "");

	unless ($self->{help}->{$arg}) {
		$ui->print("(there is no help on \"$arg\")\n");
	}

	elsif (ref($self->{help}->{$arg}) eq "CODE") {
		$self->{help}->{$arg}->($self, $ui, $arg);
	}

	else {
		$ui->indent("? ");
		$ui->print($self->{help}->{$arg});
		$ui->indent("");
	}
}


=back
=cut

1;
