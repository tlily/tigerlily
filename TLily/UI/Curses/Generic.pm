#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Curses/Attic/Generic.pm,v 1.14 1999/03/23 23:36:20 neild Exp $

package TLily::UI::Curses::Generic;

use strict;
use vars qw(%stylemap %cstylemap %cnamemap %snamemap %cpairmap %keycodemap);
	    
use Curses;


my $meta    = 0;
my @widgets = ();
my $active;

# The stylemap and cstylemap hashes map style names to Curses attributes.
%stylemap   = (default => A_NORMAL);
%cstylemap  = (default => A_NORMAL);

# The cnamemap hash maps English color names to Curses colors.
%cnamemap   =
  (
   '-'              => -1,
   mask             => -1,
   black            => COLOR_BLACK,
   red              => COLOR_RED,
   green            => COLOR_GREEN,
   yellow           => COLOR_YELLOW,
   blue             => COLOR_BLUE,
   magenta          => COLOR_MAGENTA,
   cyan             => COLOR_CYAN,
   white            => COLOR_WHITE,
  );

# The snamemap hash maps English style names to Curses styles.
%snamemap   =
  (
   '-'             => A_NORMAL,
   'normal'        => A_NORMAL,
   'standout'      => A_STANDOUT,
   'underline'     => A_UNDERLINE,
   'reverse'       => A_REVERSE,
   'blink'         => A_BLINK,
   'dim'           => A_DIM,
   'bold'          => A_BOLD,
   'altcharset'    => A_ALTCHARSET,
  );

# The cpairmap hash maps color pairs in the format "fg bg" to color pair
# IDs.  (fg and bg are Curses color IDs.)
%cpairmap   = (COLOR_WHITE . " " . COLOR_BLACK => 0);

# The keycodemap hash maps Curses keycodes to English names.
%keycodemap =
  (
   &KEY_DOWN        => 'down',
   &KEY_UP          => 'up',
   &KEY_LEFT        => 'left',
   &KEY_RIGHT       => 'right',
   &KEY_PPAGE       => 'pageup',
   &KEY_NPAGE       => 'pagedown',
   &KEY_BACKSPACE   => 'bs',
   &KEY_DC          => 'bs',
   &KEY_HOME        => 'home',
   &KEY_END         => 'end',
   "\n"             => 'nl'
  );


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
    $self->{stylemap} = ($args{color} ? \%cstylemap : \%stylemap);

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
	    $self->{stylemap} = ($val ? \%cstylemap : \%stylemap);
	    $self->{W}->bkgdset(ord(' ') | $self->get_style_attr($self->{bg}));
	}
    }
}


sub size {
    my $self = shift;

    if (@_) {
	($self->{begin_y}, $self->{begin_x},
	 $self->{lines},   $self->{cols})     = @_;
	$self->{W}->delwin() if ($self->{W});
	if ($self->{lines} && $self->{cols}) {
	    $self->{W} = newwin($self->{lines},
				$self->{cols},
				$self->{begin_y},
				$self->{begin_x});
	    $self->{W}->keypad(1);
	    $self->{W}->scrollok(0);
	    $self->{W}->nodelay(1);
	    $self->{W}->bkgdset
	      (ord(' ') | $self->get_style_attr($self->{bg}));
	} else {
	    undef $self->{W};
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
    $active->{W}->move($active->{Y}, $active->{X});
    $active->{W}->noutrefresh();
    return;
}


sub parsestyle {
    my $style = 0;
    foreach (@_) { $style |= $snamemap{$_} if $snamemap{$_} };
    return $style;
}


sub color_pair {
    my($fg, $bg) = @_;
    my $pair;

    return 0 unless (defined $fg && defined $bg);

    $fg = defined($cnamemap{$fg}) ? $cnamemap{$fg} : COLOR_WHITE;
    $bg = defined($cnamemap{$bg}) ? $cnamemap{$bg} : COLOR_BLACK;

    if (defined $cpairmap{"$fg $bg"}) {
	$pair = $cpairmap{"$fg $bg"};
    } else {
	$pair = scalar(keys %cpairmap);
	my $rc = init_pair($pair, $fg, $bg);
	return COLOR_PAIR(0) if ($rc == ERR);
	$cpairmap{"$fg $bg"} = $pair;
    }

    return COLOR_PAIR($pair);
}


sub defstyle {
    shift if (ref $_[0]);
    my($style, @attrs) = @_;
    $stylemap{$style} = parsestyle(@attrs);
    foreach my $w (@widgets) {
	if ($w->{bg} eq $style) {
	    $w->{W}->bkgdset
	      (ord(' ') | $w->get_style_attr($style));
	}
    }
}


sub defcstyle {
    shift if (ref $_[0]);
    my($style, $fg, $bg, @attrs) = @_;
    $cstylemap{$style} = parsestyle(@attrs) | color_pair($fg, $bg);
    foreach my $w (@widgets) {
	if ($w->{bg} eq $style) {
	    $w->{W}->bkgdset
	      (ord(' ') | $w->get_style_attr($style));
	}
    }
}


sub clearstyle {
    %stylemap  = (default => A_NORMAL);
    %cstylemap = (default => A_NORMAL);
}


sub get_style_attr {
    my($self, $style) = @_;
    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    return $self->{stylemap}->{$style};
}


sub draw_style {
    my($self, $style) = @_;
    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    $self->{W}->attrset($self->{stylemap}->{$style});
}


sub read_char {
    my($self) = @_;
    my $ctrl;

    my $c = $self->{W}->getch();
    return if ($c == -1 || !defined $c);

    #print STDERR "c: '$c' (", ord($c), ")\n";
    if (ord($c) == 27) {
	$meta = 1;
	return $self->read_char();
    }

    if ((ord($c) >= 128) && (ord($c) < 256)) {
	$c = chr(ord($c)-128);
	$meta = 1;
    }

    if (defined $keycodemap{$c}) {
	$c = $keycodemap{$c};
    } elsif (ord($c) <= 31) {
	$c = lc(chr(ord($c) + 64));
	$ctrl = 1;
    }

    my $r = ($ctrl ? "C-" : "") . ($meta ? "M-" : "") . $c;
    $ctrl = $meta = 0;

    #print STDERR "r=$r\n";
    return $r;
}


1;
