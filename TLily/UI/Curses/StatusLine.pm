#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Curses/Attic/StatusLine.pm,v 1.7 1999/03/23 08:33:33 josh Exp $

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
    } else {
	croak "Unknown position: \"$type\".";
    }
}


sub build_string {
    my($self) = @_;
    
    foreach my $v (@{$self->{override}}) {
	next unless (defined $self->{var}->{$v});
	my $s = $self->{var}->{$v};
	my $x = int(($self->{cols} - length($s)) / 2);
	$x = 0 if $x < 0;
	$self->{str} = (' ' x $x) . $s;
	return;
    }
    
    my @l = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
		@{$self->{left}});
    my @r = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
		@{$self->{right}});
    
    my $l = join(" | ", @l);
    my $r = join(" | ", @r);
    
    my $mlen = $self->{cols} - (length($l) + length($r));
    $self->{str} = $l . (' ' x $mlen) . $r;
}


sub set {
    my($self, $name, $val) = @_;
    if (defined($self->{var}->{$name}) == defined($val)) {
	return if (!defined($val) || ($self->{var}->{$name} eq $val));
    }
    $self->{var}->{$name} = $val;
    $self->build_string();
    $self->redraw();
}


sub redraw {
    my($self) = @_;
    
    $self->{W}->clrtoeol(0, 0);
    $self->{W}->addstr($self->{str});
    $self->{W}->noutrefresh();
}
