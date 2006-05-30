# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003-2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::FoiledAgain::Curses;

use vars qw(@ISA $sigwinch $COLS $LINES);

use TLily::FoiledAgain;
@ISA = qw(TLily::FoiledAgain);

my ($STTY_LNEXT, $WANT_COLOR, $USING_COLOR);

use strict;
use Carp;

use Curses;

=head1 NAME

TLily::FoiledAgain::Curses - Curses implementation of the FoiledAgain interface

=cut

# The keycodemap hash maps Curses keycodes to English names.
my %keycodemap =
  (
   &KEY_DOWN        => 'down',
   &KEY_UP          => 'up',
   &KEY_LEFT        => 'left',
   &KEY_RIGHT       => 'right',
   &KEY_PPAGE       => 'pageup',
   &KEY_NPAGE       => 'pagedown',
   &KEY_BACKSPACE   => 'bs',
   &KEY_IC          => 'ins',
   &KEY_DC          => 'del',
   &KEY_HOME        => 'home',
   &KEY_END         => 'end',
   "\n"             => 'nl'
  );

# The stylemap and cstylemap hashes map style names to Curses attributes.
my %stylemap   = (default => A_NORMAL);
my %cstylemap  = (default => A_NORMAL);


# The cnamemap hash maps English color names to Curses colors.
my %cnamemap   =
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
my %snamemap   =
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
my %cpairmap   = ("-1 -1" => 0);

sub start {
    # Work around a bug in certain curses implementations where raw() does
    # not appear to clear the "lnext" setting.
    ($STTY_LNEXT) = (`stty -a 2> /dev/null` =~ /lnext = (\S+);/);
    $STTY_LNEXT =~ s/<undef>/undef/g;
    system("stty lnext undef") if ($STTY_LNEXT);

    initscr;

    $USING_COLOR = 0;
    if ($WANT_COLOR && has_colors()) {
	my $rc = start_color();
	$USING_COLOR = ($rc == OK);
	if ($USING_COLOR) {
	    eval { use_default_colors(); };
	}
    }

    noecho();
    raw();
    idlok(1);

    # How odd.  Jordan doesn't have idcok().
    eval { idcok(1); };

    typeahead(-1);
    keypad(1);

    $SIG{WINCH} = sub { $sigwinch = 1; };

    while (my($pair, $id) = each %cpairmap) {
	my($fg, $bg) = split / /, $pair, 2;
	init_pair($id, $fg, $bg);
    }
}

sub stop {
    endwin;
    #refresh;
    system("stty lnext $STTY_LNEXT") if ($STTY_LNEXT);
}

sub refresh {
    endwin();
    doupdate();
}


#
# Use Term::Size to determine the terminal size after a SIGWINCH, but don't
# actually require that it be installed.
#

my $termsize_installed;
my $have_ioctl_ph;
BEGIN {
    eval { require Term::Size; import Term::Size; };
    if ($@) {
        $termsize_installed = 0;
    } else {
        $termsize_installed = 1;
    }

    eval { require qw(sys/ioctl.ph); };
    if ($@) {
        $have_ioctl_ph = 0;
    } else {
        $have_ioctl_ph = 1;
    }

    if (!$termsize_installed && !$have_ioctl_ph) {
        warn("*** WARNING: Unable to load Term::Size or ioctl.ph ***\n");
        warn("*** resizes will probably not work ***\n");
        sleep(2);
    }
}

sub has_resized {
    my $resized;

    while ($sigwinch) {
        $resized = 1;
        $sigwinch = 0;
        if ($termsize_installed) {
            ($ENV{'COLUMNS'}, $ENV{'LINES'}) = Term::Size::chars();
        } elsif ($have_ioctl_ph) {
            ioctl(0, &TIOCGWINSZ, my $winsize);
            return 0 if (!defined($winsize));
            my ($row, $col, $xpixel, $ypixel) = unpack('S4', $winsize);
            return 0 if (!defined($row));
            ($ENV{'COLUMNS'}, $ENV{'LINES'}) = ($col, $row);
        }
        stop();
        refresh;
        start();
    }

    return $resized;
}

sub suspend { endwin; }
sub resume  { doupdate; }

sub screen_width  { $COLS; }
sub screen_height { $LINES; }
sub update_screen { doupdate; }
sub bell { beep; }

sub new {
    my($proto, $lines, $cols, $begin_y, $begin_x) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};
    bless($self, $class);

    $self->{W} = newwin($lines, $cols, $begin_y, $begin_x);
    $self->{W}->keypad(1);
    $self->{W}->scrollok(0);
    $self->{W}->nodelay(1);

    $self->{stylemap} = ($USING_COLOR ? \%cstylemap : \%stylemap);

    return $self;
}


sub position_cursor {
    my ($self, $line, $col) = @_;

    $self->{W}->move($line, $col);
    $self->{W}->noutrefresh();
}


my $meta = 0;
sub read_char {
    my($self) = @_;

    my $ctrl;

    my $c = $self->{W}->getch();
    return if ($c eq "-1" || !defined $c);

    #print STDERR "c: '$c' (", ord($c), ")\n";
    return $c if $self->{quoted_insert};

    if (ord($c) == 27) {
	$meta = 1;
	return $self->read_char();
    }

    if ((ord($c) >= 128) && (ord($c) < 256)) {
	$c = chr(ord($c)-128);
	$meta = 1;
    } elsif (ord($c) == 127) {
	$c = '?';
	$ctrl = 1;
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


sub destroy {
    my ($self) = @_;

    $self->{W}->delwin() if ($self->{W});
    $self->{W} = undef;
}


sub clear {
    my ($self) = @_;

    $self->{W}->erase();
}


sub clear_background {
    my ($self, $style) = @_;    

    $self->{W}->bkgdset
        (ord(' ') | $self->get_style_attr($style));
}

sub set_style {
    my($self, $style) = @_;

    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    $self->{W}->attrset($self->{stylemap}->{$style});
}


sub clear_line {
    my ($self, $y) = @_;

    $self->{W}->clrtoeol($y, 0);
}


sub move_point {
    my ($self, $y, $x) = @_;

    $self->{W}->move($y, $x);
}


sub addstr_at_point {
    my ($self, $string) = @_;

    $self->{W}->addstr($string);
}


sub addstr {
    my ($self, $y, $x, $string) = @_;

    $self->{W}->addstr($y, $x, $string);
}

sub insch {
    my ($self, $y, $x, $character) = @_;

    $self->{W}->insstr($y, $x, $character);
}

sub delch_at_point {
    my ($self, $y, $x) = @_;

    $self->{W}->delch();
}

sub scroll {
    my ($self, $numlines) = @_;

    $self->{W}->scrollok(1);
    $self->{W}->scrl($numlines);
    $self->{W}->scrollok(0);
}

sub commit {
    my ($self) = @_;

    $self->{W}->noutrefresh();
}

sub want_color {
    ($WANT_COLOR) = @_;
}

sub reset_styles {
    %stylemap  = (default => A_NORMAL);
    %cstylemap = (default => A_NORMAL);
}

sub defstyle {
    my($style, @attrs) = @_;
    $stylemap{$style} = parsestyle(@attrs);
}


sub defcstyle {
    my($style, $fg, $bg, @attrs) = @_;
    $cstylemap{$style} = parsestyle(@attrs) | color_pair($fg, $bg);
}

##############################################################################
# Private Functions
sub get_style_attr {
    my($self, $style) = @_;
    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    return $self->{stylemap}->{$style};
}


sub parsestyle {
    my $style = 0;
    foreach (@_) { $style |= $snamemap{$_} if $snamemap{$_} };
    return $style;
}


sub colorid {
	my($col) = @_;

	if (defined($cnamemap{$col})) {
		return $cnamemap{$col}
	} elsif ($col =~ /^gr[ae]y(\d+)$/) {
		$col = $1 + 232;
		return undef if ($col > 255);
		return $col;
	} elsif ($col =~ /^(\d+),(\d+),(\d+)$/) {
		$col = (16 + $1 * 36 + $2 * 6 + $3);
		return undef if ($col < 16 || $col > 231);
		return $col;
	} else {
		return undef;
	}
}


sub color_pair {
    my($fg, $bg) = @_;
    my $pair;

    return 0 unless (defined $fg && defined $bg);

    $fg = colorid($fg);
    $fg = COLOR_WHITE unless defined($fg);
    $bg = colorid($bg);
    $bg = COLOR_BLACK unless defined($bg);

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


1;
