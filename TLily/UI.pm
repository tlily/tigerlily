package LC::UI;

use strict;
use Carp;

# List of all UIs, indexed by name.
my %ui;

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
	my($self, $command, $func) = @_;
}


sub command_u {
	my($self, $command) = @_;
}


sub bind {
	my($self, $key, $command) = @_;
}


sub command {
	my($self, $command, $key, $line, $pos) = @_;
}


1;
