package LC::UI;

use strict;
use Carp;

use LC::Registrar;

# List of all UIs, indexed by name.
my %ui;

# Global commands, will be autoregistered into new UIs.
my %gcommand;

# Global bindings, will be autoregistered into new UIs.
my %gbind;

sub new {
	my($proto, %a) = @_;
	my $class = ref($proto) || $proto;

	croak "Required UI parameter \"event\" missing." unless ($a{event});
	croak "Required UI parameter \"name\" missing."  unless ($a{"name"});

	my $self        = {};
	$self->{event}  = $a{event};
	$self->{"name"} = $a{"name"};

	$ui{$a{"name"}} = $self;

	bless($self, $class);
}


sub inherit_global_bindings {
	my($self) = @_;

	while (my($command, $func) = each %gcommand) {
		$self->command_r($command, $func);
	}

	while (my($key, $command) = each %gbind) {
		$self->bind($key, $command);
	}
}


sub name {
	shift if (@_ > 1);
	my($a) = @_;
	if (ref($a)) {
		return $a->{"name"};
	} else {
		return $ui{$a} || $ui{"main"};
	}
}


sub DESTROY {
	my($self) = @_;
	delete $ui{$self->{"name"}};
}


sub needs_terminal {
	0;
}


sub suspend {
	my($self) = @_;
}


sub resume {
	my($self) = @_;
}


sub defstyle {
	my($self, $style, @attrs) = @_;
}


sub defcstyle {
	my($self, $style, $fg, $bg, @attrs) = @_;
}


sub clearstyle {
	my($self) = @_;
}


sub style {
	my($self, $style) = @_;
}


sub indent {
	my($self, $s) = @_;
}


sub print {
	my($self, $s) = @_;
}


sub printf {
	my($self, $s, @args) = @_;
	$self->print(sprintf($s, @args));
}


sub printt {
	my($self, $s) = @_;
}


sub command_r {
	return if (ref($_[0])); # Don't do anything as an object method.
	shift if (@_ > 2);      # Lose the package, if called as a class method.
	my($command, $func) = @_;

	$gcommand{$command} = $func;

	my $ui;
	foreach $ui (values %ui) {
		$ui->command_r($command, $func);
	}

	LC::Registrar::add("global_ui_command", $command);
	return;
}


sub command_u {
	return if (ref($_[0])); # Don't do anything as an object method.
	shift if (@_ > 2);      # Lose the package, if called as a class method.
	my($command) = @_;

	delete $gcommand{$command};

	my $ui;
	foreach $ui (values %ui) {
		$ui->command_u($command);
	}

	LC::Registrar::remove("global_ui_command", $command);
	return;
}


sub bind {
	return if (ref($_[0])); # Don't do anything as an object method.
	shift if (@_ > 2);      # Lose the package, if called as a class method.
	my($key, $command) = @_;

	$gbind{$key} = $command;

	my $ui;
	foreach $ui (values %ui) {
		$ui->bind($key, $command);
	}
}


sub command {
	my($self, $command, $key, $line, $pos) = @_;
}


LC::Registrar::class_r(global_ui_command => \&command_u);

1;
