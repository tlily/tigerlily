#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/TextWindow/Attic/Generic.pm,v 1.4 2003/02/14 02:11:43 josh Exp $

package TLily::UI::TextWindow::Generic;

use TLily::FoiledAgain;

use strict;

my $active;
my @widgets;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    my %args  = @_;

    $self->{begin_y}  = $args{begin_y} || 0;
    $self->{begin_x}  = $args{begin_x} || 0;
    $self->{Y}        = 0;
    $self->{X}        = 0;
    $self->{lines}    = $args{lines} || 0;
    $self->{cols}     = $args{cols} || 0;
    $self->{rlines}   = undef;
    $self->{rcols}    = undef;
    $self->{layout}   = $args{layout};
    $self->{bg}       = $args{bg} || "default";
    $self->{keymap}   = {};

    if ($self->{lines} && $self->{cols}) {
	size($self,
	     $self->{begin_y}, $self->{begin_x},
	     $self->{lines}, $self->{cols});
    }

    push @widgets, $self;

    bless($self, $class);
}

sub configure {
    my $self = shift;

    while (@_) {
	my $opt = shift;
	my $val = shift;

	if ($opt eq 'color') {

            # XXX  this doesn't work.  Currently we can't turn color 
            #      off or on once it's initially been set up.

            TLily::FoiledAgain::want_color($val);
            $self->{F}->clear_background($self->{bg});
	}
    }
}


sub size {
    my $self = shift;

    if (@_) {
	($self->{begin_y}, $self->{begin_x},
	 $self->{lines},   $self->{cols})     = @_;

        $self->{F}->destroy() if ($self->{F});

	if ($self->{lines} && $self->{cols}) {
	    $self->{F} = new TLily::FoiledAgain(
                $self->{lines},   $self->{cols},
                $self->{begin_y}, $self->{begin_x});

            $self->{F}->clear_background($self->{bg});
	} else {
	    undef $self->{F};
	}
    } else {
	return($self->{begin_y}, $self->{begin_x},
	       $self->{lines},   $self->{cols});
    }
}


sub req_size {
    my $self = shift;
    if (@_) {
	($self->{rlines}, $self->{rcols}) = @_;
	$self->{layout}->size_request($self, @_);
    }
    return ($self->{rlines}, $self->{rcols});
}


sub active {
    my($self) = @_;
    $active = $self if (ref $self);
    return $active;
}


sub position_cursor {
    return unless $active;

    $active->{F}->position_cursor($active->{Y}, $active->{X});
    return;
}


sub defstyle {
    shift if (ref $_[0]);
    my($style, @attrs) = @_;

    TLily::FoiledAgain::defstyle(@_);

    foreach my $w (@widgets) {
	if ($w->{bg} eq $style) {
            $w->{F}->clear_background($style);
	}
    }
}


sub defcstyle {
    shift if (ref $_[0]);
    my($style, $fg, $bg, @attrs) = @_;

    TLily::FoiledAgain::defcstyle(@_);

    foreach my $w (@widgets) {
	if ($w->{bg} eq $style) {
            $w->{F}->clear_background($style);
	}
    }
}


sub clearstyle {
    my ($self) = @_;

    $self->{F}->default_styles();
}


sub draw_style {
    my($self, $style) = @_;

    $self->{F}->set_style($style);
}


sub read_char {
    my($self) = @_;

    $self->{F}->read_char();
}


1;
