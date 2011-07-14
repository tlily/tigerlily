#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003-2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

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

=cut

# The cnamemap hash maps English color names to Term::ScreenColor color attrs.
my %fg_cnamemap = (
    '-'        => "black",
    mask       => "black",
    black      => "black",
    red        => "red",
    green      => "green",
    yellow     => "yellow",
    blue       => "blue",
    magenta    => "magenta",
    cyan       => "cyan",
    white      => "white"
);

my %bg_cnamemap = (
    '-'     => "on_black",
    mask    => "on_black",
    black   => "on_black",
    red     => "on_red",
    green   => "on_green",
    yellow  => "on_yellow",
    blue    => "on_blue",
    magenta => "on_magenta",
    cyan    => "on_cyan",
    white   => "on_white"
);

# The snamemap hash maps English style names to Term::ScreenColor style attrs.
my %snamemap = (
   '-'             => "clear",
   'normal'        => "clear",
   'standout'      => "ansibold",
   'underline'     => "underline",
   'reverse'       => "inverse",
   'blink'         => "blink",
   'dim'           => "",
   'bold'          => "ansibold",
   'altcharset'    => ""
);


# The stylemap and cstylemap hashes map style names to color attributes
# Term::Screencolor can use.
my %stylemap   = (default => "white on black");
my %cstylemap  = (default => "white on black");

sub DEBUG {
    my ($self) = shift;

    my $method = (caller(1))[3];
    $method =~ s/TLily::FoiledAgain::TermScreen:://g;

    uidebug("[window #$self->{windownum}] $method(@_)\n");
}

sub uidebug {
    return unless $TLily::FoiledAgain::DEBUG;

    open my $f, '>>', 'uilog'  or die;
    print $f @_;
    close $f;
}

my $SCREEN;
my @windows;

sub start {
    # Physical screen
    $SCREEN = new Term::ScreenColor();

    # Term::ScreenColor's detection of whether a terminal supports color
    # is stupid.   Instead, we force it to always think it can, and then
    # allow tlily to control this via the want_color method below.

    $SCREEN->{is_colorizable} = 1;

    $SCREEN->clrscr();
    $SCREEN->at(0,0);
    $SCREEN->raw();
    $SCREEN->noecho();
}

sub stop {
    $SCREEN->cooked();
    $SCREEN->echo();
}


sub refresh { }
sub suspend {  }
sub resume  {  }
sub bell {
    print chr(7);
}

sub screen_width  { 80; }
sub screen_height { 24; }
sub has_resized { 0; }

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
    $self->{linecontents} = [];
    if ($SCREEN->dc_exists && $SCREEN->ic_exists) {
        $self->{need_linecontents} = 0;
    } else {
        $self->{need_linecontents} = 1;
    }

    $self->{cursor_x} = 0;
    $self->{cursor_y} = 0;

    $self->{begin_x} = $begin_x;
    $self->{begin_y} = $begin_y;

    $self->{cols} = $cols;
    $self->{lines} = $lines;

    $self->{stylemap} = ($SCREEN->colorizable() ? \%cstylemap : \%stylemap);

    bless($self, $class);

    push @windows, $self;
    $self->{windownum} = @windows;
    uidebug("[window #$self->{windownum}] allocated. (begin_y=$begin_y, lines=$lines)\n");

    $self->clear();

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

    uidebug("read_char cbuf=$cbuf (" . length($cbuf) . " bytes)\n");

    my $c = substr($cbuf, 0, 1);
    $cbuf = substr($cbuf, 1);

    uidebug("ord(c) = " . ord($c) . "\n");

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

    if (ord($c) == 127) {
        $c = "?";
        $ctrlflag = 1;
    }

    my $res = (($metaflag ? "M-" : "") . ($ctrlflag ? "C-" : "") . $c);

    $metaflag = 0;
    $ctrlflag = 0;

    uidebug("read_char returning $res\n");

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
    $self->set_style($style);

    for my $line (0..$self->{lines}) {
        $self->clear_line($line);
    }

    $self->move_point(0,0);
}


sub set_style {
    my($self, $style) = @_;
    DEBUG(@_);

    my $color = $self->{stylemap}{$style} || $self->{stylemap}{default};

    $self->_queue_event(undef,undef,'color',$color);

}


sub clear_line {
    my ($self, $y) = @_;
    DEBUG(@_);

    if ($self->{need_linecontents}) {
        $self->{linecontents}[$y] = (" " x $self->{cols} + 1);
    }

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

    if ($self->{need_linecontents}) {
        my $x = $self->{cursor_x};
        my $y = $self->{cursor_y};

        substr($self->{linecontents}[$y], $x) = $string;
    }

    $self->_queue_event(undef, undef, "puts", $string);
    $self->{cursor_x} += length($string);
}


sub addstr {
    my ($self, $y, $x, $string) = @_;
    DEBUG(@_);

    if ($self->{need_linecontents}) {
        substr($self->{linecontents}[$y], $x) = $string;
    }

    $self->_queue_event($x, $y, "puts", $string);
    $self->{cursor_x} = $x;
    $self->{cursor_y} = $y;
    $self->{cursor_x} += length($string);
}


sub insch {
    my ($self, $y, $x, $character) = @_;
    DEBUG(@_);

    if ($SCREEN->ic_exists) {
        $self->_queue_event($x, $y, "ic", $character);
    } else {
        die "linecontents not set up?" unless $self->{need_linecontents};

        # gah.  oh well, fall back on stupid behavior
        my $restofline = substr($self->{linecontents}[$y], $x, -1);
        substr($self->{linecontents}[$y], $x) = "$character$restofline";

        $self->_queue_event($x, $y, "puts", "$character$restofline");
    }
}


sub delch_at_point {
    my ($self) = @_;
    DEBUG(@_);

    if ($SCREEN->dc_exists) {
        $self->_queue_event(undef, undef, "dc");
    } else {
        my $x = $self->{cursor_x};
        my $y = $self->{cursor_y};

        my $restofline = substr($self->{linecontents}[$y], $x+1);
        $restofline .= " ";
        substr($self->{linecontents}[$y], $x) = $restofline;
        $self->_queue_event($x, $y, "puts", $restofline);
    }
}


sub scroll {
    my ($self, $numlines) = @_;
    DEBUG(@_);

    if ($numlines > 0) {
        # toss the scrolled-off line off the screen.

        $self->_queue_event(0, 0, 'dl');

    } else {
        # toss the scrolled-off line off the screen.

        $self->_queue_event(0, 0, 'il');
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
                uidebug("commit - at(" . ($y + $window->{begin_y}) . ",".
                                         ($x + $window->{begin_x}) . ")\n");
            }

            next unless defined($command);

            uidebug("commit - $command(@args)\n");
            $SCREEN->$command(@args);

            # stash the events in case we need to scroll the window.
            my $line = defined($y) ? $y : -1;

            if ($line == -1 && (@{$window->{lineevents}} == 0)) {
               $line = 0;
            }

            $window->{lineevents}[$line] ||= [];
            push @{$window->{lineevents}[$line]}, $event;
#            uidebug("lineevents[$line] = [ $x, $y, $command, @args ]\n");
        }
    }

}

sub want_color {
    my ($want_color) = @_;

    # This is a hack, see new() for details.
    $SCREEN->{is_colorizable} = $want_color;
}

sub reset_styles {
    DEBUG(@_);

    %stylemap   = ();
    %cstylemap  = ();
}


sub defstyle {
    my($style, @attrs) = @_;
    my @style;
    foreach (@attrs) { push @style, $snamemap{$_}; }

    if (grep { $_ eq "reverse" } @attrs) {
        push @style, $fg_cnamemap{'black'}, $bg_cnamemap{'white'};
    } else {
        push @style, $fg_cnamemap{'white'}, $bg_cnamemap{'black'};
    }
    $stylemap{$style} = join ' ', @style;

    uidebug("stylemap[$style] = $stylemap{$style}\n");
}


sub defcstyle {
    my($style, $fg, $bg, @attrs) = @_;
    uidebug("defcstyle(@_)");

    my @style;
    foreach (@attrs) { push @style, $snamemap{$_}; }

    if (grep { $_ eq "reverse" } @attrs) {
        my $oldfg = $fg;
        $fg = $bg; $bg = $oldfg;
    }

    push @style, $fg_cnamemap{$fg}, $bg_cnamemap{$bg};
    $cstylemap{$style} = join ' ', @style;

    uidebug("cstylemap[$style] = $cstylemap{$style}\n");
}

###############################################################################
# Private functions

sub _queue_event {
    my ($self, $x, $y, $command, @args) = @_;

    push @{$self->{events}}, [ $x, $y, $command, @args ];

    $self->{cursor_x} = $x if defined($x);
    $self->{cursor_y} = $y if defined($y);
}


1;
