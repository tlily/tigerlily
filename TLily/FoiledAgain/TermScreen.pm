#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/FoiledAgain/Attic/TermScreen.pm,v 1.2 2003/10/18 22:25:52 josh Exp $

package TLily::FoiledAgain::TermScreen;

use vars qw(@ISA);

use TLily::Version;
use TLily::FoiledAgain;
@ISA = qw(TLily::FoiledAgain);

use strict;
use Carp;

use Term::ScreenColor;

my $USING_COLOR;

=head1 NAME

TLily::FoiledAgain::TermScreen - Term::Screen implementation of the FoiledAgain interface

=cut;

# The cnamemap hash maps English color names to Term::ScreenColor color attrs.
my %fg_cnamemap = (
   '-'              => -1,
   mask             => -1
);
$fg_cnamemap{$_}=$_ foreach qw(black red green yellow
                               blue magenta cyan white);

my %bg_cnamemap = (
   '-'              => -1,
   mask             => -1,
);
$bg_cnamemap{$_}="on_$_" foreach qw(black red green yellow 
                                    blue magenta cyan white);


# The snamemap hash maps English style names to Term::ScreenColor style attrs.
my %snamemap = (
   '-'             => 0,
   'normal'        => 'clear',
   'standout'      => 'ansibold',
   'underline'     => 'underline',
   'reverse'       => 'inverse',
   'blink'         => 'blink',
   'dim'           => 0,
   'bold'          => 'ansibold',
   'altcharset'    => 0
);


# The stylemap and cstylemap hashes map style names to color attributes
# Term::Screencolor can use.
my %stylemap   = (default => 'reset');
my %cstylemap  = (default => 'reset');

sub DEBUG { 
    my ($self) = shift;

    my $method = (caller(1))[3];
    $method =~ s/TLily::FoiledAgain::TermScreen:://g;

    uidebug("[window #$self->{windownum}] $method(@_)\n");
}

sub uidebug {
    return unless $TLily::FoiledAgain::DEBUG;

    open(F, ">>uilog") || die;
    print F @_;
    close(F);
}

my $SCREEN;
my @windows;

sub start {
    # Physical screen
    $SCREEN = new Term::ScreenColor();    
    $SCREEN->clrscr();
    $SCREEN->at(0,0);
    $SCREEN->raw();
    $SCREEN->noecho();

    $USING_COLOR = $SCREEN->colorizable();
}

sub stop {
    $SCREEN->cooked();
    $SCREEN->echo();
}


sub sanity_poll { }
sub suspend {  }
sub resume  {  }
sub bell {
    print chr(7);
}

sub screen_width  { 80; }
sub screen_height { 24; }
sub update_screen { 
    
    # place the cursor as it is in the last window.
    my $col  = $windows[-1]->{cursor_x};
    my $line = $windows[-1]->{cursor_y};
    $col  += $windows[-1]->{begin_x};
    $line += $windows[-1]->{begin_y};
    $SCREEN->at($line, $col);
}


sub new {
    my($proto, $lines, $cols, $begin_y, $begin_x) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{events} = [];
    $self->{lineevents} = [];    

    $self->{cursor_x} = 0;
    $self->{cursor_y} = 0;

    $self->{begin_x} = $begin_x;
    $self->{begin_y} = $begin_y;

    $self->{cols} = $cols;
    $self->{lines} = $lines;

    $self->{stylemap} = ($USING_COLOR ? \%cstylemap : \%stylemap);

    bless($self, $class);

    push @windows, $self;
    $self->{windownum} = @windows;
    uidebug("[window #$self->{windownum}] allocated.\n");

    return $self;
}


sub position_cursor {
    my ($self, $line, $col) = @_;
    DEBUG(@_);

    $self->{cursor_x} = $col;
    $self->{cursor_y} = $line;
}


# Returns a character if one is waiting, or undef otherwise.
my $cbuf = '';
my $metaflag = 0;
my $ctrlflag = 0;
sub read_char {
    my ($self) = @_;
    
    sysread(STDIN, $cbuf, 1024, length $cbuf);
    return undef unless (length $cbuf);
    my $c = substr($cbuf, 0, 1);
    $cbuf = substr($cbuf, 1);

    if (ord($c) == 27) {
        $metaflag = !$metaflag;
        return $self->read_char();
    }

    if ((ord($c) >= 128) && (ord($c) < 256)) {
        $c = chr(ord($c) - 128);
        $metaflag = 1;
    }

    if (($c eq "\n") || ($c eq "\r")) {
        $c = 'nl';
    }

    if (ord($c) <= 31) {
        $c = chr(ord($c) + ord('a') - 1);
        $ctrlflag = 1;
    }

    my $res = (($metaflag ? "M-" : "") . ($ctrlflag ? "C-" : "") . $c);

    $metaflag = 0;
    $ctrlflag = 0;

    return $res;
}


sub destroy {
    my ($self) = @_;
    DEBUG(@_);

    # and remove this window from the list..
    @windows = grep { $_ ne $self } @windows;
}


sub clear {
    my ($self) = @_;
    DEBUG(@_);

    $self->clear_background('normal');
}


sub clear_background {
    my ($self, $style) = @_;
    DEBUG(@_);

    $self->{background_style} = $style;
    $self->move_point(0, 0);

    for my $line (0..$self->{lines}) {
        $self->set_style($self->get_attr_for_style($style));
        $self->clear_line($line);
    }
    
    $self->move_point(0,0);
}


sub set_style {
    my($self, $style) = @_;
    DEBUG(@_);

    $self->_queue_event(undef,undef,'color', 
                          $self->get_attr_for_style($style));
}


sub clear_line {
    my ($self, $y) = @_;
    DEBUG(@_);

    $self->_queue_event(0, $y, 'clreol');
}


sub move_point {
    my ($self, $y, $x) = @_;
    DEBUG(@_);

    $self->{cursor_x} = $x;
    $self->{cursor_y} = $y;
}


sub addstr_at_point {
    my ($self, $string) = @_;
    DEBUG(@_);

    $self->_queue_event(undef, undef, "puts", $string);
    $self->{cursor_x} += length($string);
}


sub addstr {
    my ($self, $y, $x, $string) = @_;
    DEBUG(@_);

    $self->_queue_event($x, $y, "puts", $string);
    $self->{cursor_x} = $x;
    $self->{cursor_y} = $y;
    $self->{cursor_x} += length($string);
}


sub insch {
    my ($self, $y, $x, $character) = @_;
    DEBUG(@_);

    $self->_queue_event($x, $y, "ic", $character);
}


sub delch_at_point {
    my ($self) = @_;
    DEBUG(@_);

    $self->_queue_event(undef, undef, "dc");
}


sub scroll {
    my ($self, $numlines) = @_;
    DEBUG(@_);

    my @lineevents = @{$self->{lineevents}};
    $self->{lineevents} = [];
    
    if ($numlines > 0) {
        # toss the scrolled-off line off the screen.
        shift @lineevents for (1..$numlines);
	
	# reexecute the rest of the events, but tweak the line numbers.
	foreach my $line (@lineevents) {
	    next unless defined($line);
	    foreach my $event (@{$line}) {
                my ($x, $y, $command, @args) = @{$event};
	    
    		$y-- if defined($y);
                $self->_queue_event(0, $y, 'clreol');		
	        $self->_queue_event($x, $y, $command, @args);
	    }
	}
    } else {
        # toss the scrolled-off line off the screen.
        pop @lineevents for (1..-$numlines);
	
	# reexecute the rest of the events, but tweak the line numbers.
	foreach my $line (@lineevents) {
	    next unless defined($line);	
            foreach my $event (@{$line}) {
                my ($x, $y, $command, @args) = @{$event};
	    
                $y++ if defined($y);
                $self->_queue_event(0, $y, 'clreol');
                $self->_queue_event($x, $y, $command, @args);
            }		
	}
        
    }

    # and slap the cursor at the bottom.
    $self->move_point($self->{lines} - $numlines, 0);
}


sub commit {
    my ($self) = @_;
    DEBUG(@_);

    foreach my $window (@windows) {
        # replay the queued events...
        while (@{$window->{events}}) {
	    my $event = shift @{$window->{events}};
            my ($x, $y, $command, @args) = @{$event};

            if (defined($x)) {
                $SCREEN->at($y + $window->{begin_y},
                            $x + $window->{begin_x});
                uidebug("commit - at(" . $y + $window->{begin_y} . ",".
                                         $x + $window->{begin_x} . ")\n");
            }
	    uidebug("commit - $command(@args)\n");
            $SCREEN->$command(@args);
	    
	    # stash the events in case we need to scroll the window.
	    my $line = defined($y) ? $y : -1;
	    
	    if ($line == -1 && (@{$window->{lineevents}} == 0)) {
	       $line = 0;
	    }
	    
	    $window->{lineevents}[$line] ||= [];
	    push @{$window->{lineevents}[$line]}, $event;
#	    uidebug("lineevents[$line] = [ $x, $y, $command, @args ]\n");
        }
    }

}

sub want_color {
    ($USING_COLOR) = @_;
}

sub reset_styles {
    DEBUG(@_);

    %stylemap   = (default => $main::ATTR_NORMAL);
    %cstylemap  = (default => $main::ATTR_NORMAL);
}


sub defstyle {
    my($style, @attrs) = @_;
    
    if (grep { $_ eq "reverse" } @attrs) {
        $stylemap{$style} = parsestyle(@attrs) | $fg_cnamemap{black} | $bg_cnamemap{white};
    } else {
        $stylemap{$style} = parsestyle(@attrs) | $fg_cnamemap{white} | $bg_cnamemap{black};
    }
}


sub defcstyle {
    my($style, $fg, $bg, @attrs) = @_;

    if (grep { $_ eq "reverse" } @attrs) {
        my $oldfg = $fg;
        $fg = $bg; $bg = $oldfg;
    }

    $cstylemap{$style} = parsestyle(@attrs) | $fg_cnamemap{$fg} | $bg_cnamemap{$bg};
}

###############################################################################
# Private functions

sub get_attr_for_style {
    my ($self, $style) = @_;

    $self->{stylemap}{$style} || 'clear';
}

sub parsestyle {
    my $style = 0;
    foreach (@_) { $style |= $snamemap{$_} if $snamemap{$_} };
    return $style;
}

sub _queue_event {
    my ($self, $x, $y, $command, @args) = @_;

    push @{$self->{events}}, [ $x, $y, $command, @args ];

    $self->{cursor_x} = $x if defined($x);
    $self->{cursor_y} = $y if defined($y);
}
1;
