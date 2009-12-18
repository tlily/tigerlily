# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# This is a super-cheezy UI module written by someone (me) who was too
# lazy to bother to actually understand how tlily UI's work :)
#
# Thus it sucks.
# 
# But it will suffice for botworkin' for now.

# $Id$

package TLily::UI::Text;

use strict;
use vars qw(@ISA);

use TLily::UI;
use TLily::UI::Util qw(wrap);
use TLily::Event;

@ISA = qw(TLily::UI); #) cperl mode is getting confused


#
# Use Term::Size to determine the terminal size after a SIGWINCH, but don't
# actually require that it be installed.
#

my $termsize_installed;
my $sigwinch;
my $cols;
my $lines;
BEGIN {
    eval { require Term::Size; import Term::Size; };
    if ($@) {
	warn("*** WARNING: Unable to load Term::Size ***\n");
	$termsize_installed = 0;
	($cols, $lines) = (80, 24);
    } else {
	($cols, $lines) = Term::Size::chars();
	$termsize_installed = 1;
    }

    system("stty cbreak");
}

END {
    system("stty sane");    
}

sub accept_line {
    my($self, $text) = @_;

    if (@{$self->{prompt}} > 0) {
	my $args = shift @{$self->{prompt}};
	$self->prompt("") if defined ($args->{prompt});

	$args->{call}->($self, $text);

	if (@{$self->{prompt}} > 0) {
	    $args = $self->{prompt}->[0];
	    $self->prompt($args->{prompt}) if defined ($args->{prompt});
	    $self->password(1) if ($args->{password});
	}

	return;
    }

    TLily::Event::send(type => 'user_input',
		       text => $text,
		       ui   => $self);

    return;
}


my $meta = 0;
sub run {
    my($self) = @_;

    while ($sigwinch) {
        $sigwinch = 0;
        if ($termsize_installed) {
	    ($cols, $lines) = Term::Size::chars();
        }
    }

    my $c;
    sysread(STDIN,$c,1);
    $self->{point}++;

    $c = ord($c);
    
    my $ctrl;
    my $key;
    if ($c == 27) {
	$meta = 1;
	return;
    }

    if ($c >= 128) {
	$c -= 128;
	$meta = 1;
    }

    if ($c <= 31) {
	$c += 96;
	$ctrl = 1;
    }

    $key = ($ctrl ? "C-" : "") . ($meta ? "M-" : "") . chr($c);

    if ($key eq "C-j") { 	
	$self->accept_line($self->{text});
	$self->{text} = "";
	$self->{point} = -1;
    } else {
	$self->{text} .= $key;
    }

    my $cmd = $self->{bindings}->{$key};
    if ($cmd && $self->{command}->{$cmd}) {
	$self->command($cmd, $key);
	return;
    }

    return;
}


sub new {
    my $proto = shift;
    my %arg   = @_;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    bless($self, $class);

    $| = 1;

    $self->{prompt}   = [];
    $self->{indent}   = "";
    $self->{command}  = {};
    $self->{bindings} = {};
    $self->{queued}   = "";

    TLily::Event::io_r(handle => \*STDIN,
		       mode   => 'r',
		       obj    => $self,
		       call   => \&run);

    $self->inherit_global_bindings();

    return $self;
}


sub prompt_for {
    my($self, %args) = @_;
    croak("required parameter \"call\" missing.") unless ($args{call});

    push @{$self->{prompt}}, \%args;
    return if (@{$self->{prompt}} > 1);

    $self->prompt($args{prompt}) if (defined $args{prompt});
    $self->password(1) if ($args{password});
    return;
}


sub needs_terminal {
    1;
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
    my($self, $indent) = @_;

    return;

}


sub print {
    my $self = shift;

    $self->SUPER::print(@_);
    $self->{queued} .= join('', @_);
    return unless ($self->{queued} =~ s/^(.*\n)//s);
    my $s = $1;
    foreach my $l (wrap($s, cols => 80, 'indent' => $self->{indent})) {
	print $l, "\n";
    }
};


sub redraw {
    my($self) = @_;
    return 1;
}


sub command_r {
    my($self, $command, $func) = @_;
    $self->{command}->{$command} = $func;
    return 1;
}


sub command_u {
    my($self, $command) = @_;
    delete $self->{command}->{$command};
    return 1;
}


sub bind {
    my($self, $key, $command) = @_;
    if ($command eq "insert-self") {
	delete $self->{bindings}->{$key};
    } else {
	$self->{bindings}->{$key} = $command;
    }
    return 1;
}


sub intercept_r {
    my($self, $name) = @_;
    return 1;
}


sub intercept_u {
    my($self, $name) = @_;
    return 1;
}


sub command {
    my($self, $command, $key) = @_;
    return unless ($self->{command}->{$command});

    my $rc = eval { $self->{command}->{$command}->($self, $command, $key); };
    warn "Command \"$command\" caused error: $@" if ($@);

    return $rc;
}


sub password {
    my($self, $password) = @_;
}


sub prompt {
    my($self, $prompt) = @_;

    print "$prompt";
}


sub page {
    my $self = shift;
}


sub define {
    my($self, $name, $pos) = @_;
}


sub set {
    my($self, $name, $val) = @_;
}


sub get_input {
    my($self) = @_;
    
    if (wantarray) {
	return(($self->{point}, $self->{text}));	
    } else { 
	return($self->{text});
    }
}


sub set_input {
    my($self, $point, $line) = @_;

    print "\n$line";
}


sub istyle_fn_r {
    my($self, $style_fn) = @_;
}


sub istyle_fn_u {
    my($self, $style_fn) = @_;
}


sub bell {
    my($self) = @_;

#    print "";
}

1;
