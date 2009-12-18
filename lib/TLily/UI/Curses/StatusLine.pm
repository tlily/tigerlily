# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::UI::Curses::StatusLine;

use strict;
use vars qw(@ISA);
use TLily::UI::Curses::Generic;
use Carp;

@ISA = qw(TLily::UI::Curses::Generic);


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(bg => 'status_window', @_);
    
    $self->{left}     = [];
    $self->{right}    = [];
    $self->{override} = [];
    $self->{var}      = {};
    $self->{str}      = '';
    
    bless($self, $class);
}

sub make_active {
    my($self, $is_active) = @_;
    $self->{active} = $is_active;
    $self->redraw();
}

sub define {
    my($self, $name, $type) = @_;
    $type ||= 'right';
    
    # Remove this variable from the existing lists.
    @{$self->{left}}     = grep { $_ ne $name } @{$self->{left}};
    @{$self->{right}}    = grep { $_ ne $name } @{$self->{right}};
    @{$self->{override}} = grep { $_ ne $name } @{$self->{override}};
    
    if ($type eq 'left') {
	push @{$self->{left}}, $name;
    } elsif ($type eq 'right') {
	unshift @{$self->{right}}, $name;
    } elsif ($type eq 'override') {
	push @{$self->{override}}, $name;
    } elsif ($type eq 'nowhere') {
	;
    } else {
	croak "Unknown position: \"$type\".";
    }
}


sub build_string {
    my($self) = @_;

    my ($cols, $begin, $end);
    if ($self->{active}) {
        $cols = $self->{cols} - 6;
	$begin = "^^ ";
	$end = " ^^";
    } else {
        $cols = $self->{cols};
	$begin = "";
	$end = "";
    }
 
    foreach my $v (@{$self->{override}}) {
	next unless (defined $self->{var}->{$v});
	my $s = $self->{var}->{$v};
	my $x = int(($cols - length($s)) / 2);
	my $y = int(($cols - length($s) + 1) / 2);
	$x = 0 if $x < 0;
	$y = 0 if $y < 0;
	$self->{str} = $begin . (' ' x $x) . $s . (' ' x $y) . $end;
	return;
    }
    
    my @l = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
		@{$self->{left}});
    my @r = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
		@{$self->{right}});
    
    my $l = join(" | ", @l);
    my $r = join(" | ", @r);
    
    my $mlen = $cols - (length($l) + length($r));
    $self->{str} = $begin . $l . (' ' x $mlen) . $r . $end;
}


sub set {
    my($self, $name, $val) = @_;
    if (defined($self->{var}->{$name}) == defined($val)) {
	return if (!defined($val) || ($self->{var}->{$name} eq $val));
    }
    $self->{var}->{$name} = $val;
    $self->redraw();
}


sub redraw {
    my($self) = @_;
    
    $self->build_string();
    $self->{W}->clrtoeol(0, 0);
    $self->{W}->addstr($self->{str});
    $self->{W}->noutrefresh();
}
