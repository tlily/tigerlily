#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/FoiledAgain/Attic/Win32.pm,v 1.4 2003/02/14 00:30:07 josh Exp $

package TLily::FoiledAgain::Win32;

use vars qw(@ISA);

use TLily::Version;
use TLily::FoiledAgain;
@ISA = qw(TLily::FoiledAgain);

use strict;
use Carp;

use Win32::Console;
use Win32::Sound;

=head1 NAME

TLily::FoiledAgain::Win32 - Win32 implementation of the FoiledAgain interface

=cut;

sub DEBUG { 
    my ($self) = shift;

    my $method = (caller(1))[3];
    $method =~ s/TLily::FoiledAgain::Win32:://g;

    uidebug("[window #$self->{windownum}] $method(@_)\n");
}

sub uidebug {
    return unless $TLily::FoiledAgain::DEBUG;

    open(F, ">>uilog") || die;
    print F @_;
    close(F);
}

my ($SCREEN, $INPUT);
my @windows;

sub start {
    $SCREEN = new Win32::Console();    
    $SCREEN->Alloc();
    $SCREEN->Title("TigerLily $TLily::Version::VERSION");
    $SCREEN->Display();

    $INPUT = new Win32::Console(STD_INPUT_HANDLE);
    $INPUT->Mode(ENABLE_WINDOW_INPUT);  # notify us when the size changes
}

sub stop {
    $SCREEN->Free();
}


sub sanity_poll { }
sub suspend {  }
sub resume  {  }
sub bell { 
    Win32::Sound::Play('SystemDefault', SND_ASYNC);
}

sub screen_width  { ($SCREEN->Size())[0]; }
sub screen_height { ($SCREEN->Size())[1]; }
sub update_screen { 
    foreach my $window (@windows) {
        my ($width, $height) = ($window->{cols}, $window->{lines});

        # copy the windows' data into place on the main screen.
        my $rect = $window->{buffer}->ReadRect(0, 0, $width, $height);

        defined($SCREEN->WriteRect($rect, 
                                   $window->{begin_x},
                                   $window->{begin_y}, 
                                   $window->{begin_x} + $width,
                                   $window->{begin_y} + $height)) ||
            die "Error in WriteRect";
    }

    # place the cursor as it is in the last window.
    my ($col, $line) =  $windows[-1]->{buffer}->Cursor();
    $col  += $windows[-1]->{begin_x};
    $line += $windows[-1]->{begin_y};
    $SCREEN->Cursor($col, $line, 0, 0);
}


sub new {
    my($proto, $lines, $cols, $begin_y, $begin_x) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{buffer} = new Win32::Console;

    $self->{begin_x} = $begin_x;
    $self->{begin_y} = $begin_y;

    $self->{cols} = $cols;
    $self->{lines} = $lines;

    # this doesn't appear to do anything.  So we'll maintain $self->{cols}
    # and $self->{lines} ourselves (alas).
    $self->{buffer}->Size($cols, $lines);

    bless($self, $class);

    push @windows, $self;
    $self->{windownum} = @windows;
    uidebug("[window #$self->{windownum}] allocated.\n");

    return $self;
}


sub position_cursor {
    my ($self, $line, $col) = @_;
    DEBUG(@_);

    $self->{buffer}->Cursor($col,$line, 100, 1);
}


# The keycodemap hash maps windows keycodes to tlily's names.
my %keycodemap = (
    40 => 'down',
    38 => 'up',
    37 => 'left',
    39 => 'right',
    33 => 'pageup',
    34 => 'pagedown',
    8  => 'bs',
    45 => 'ins',
    46 => 'del',
    36 => 'home',
    35 => 'end',
    13 => 'nl'
);

sub read_char {
    my($self) = @_;
#   DEBUG(@_);

    # don't try to read an event unless there's one pending.
    unless ($INPUT->GetEvents()) {
        return undef;
    }

    my @event = $INPUT->Input();

    my ($event_type, $key_down, $repeat_count,
        $virtual_keycode, $virtual_scancode, 
        $char, $control_key_state) = @event;

    return undef unless ($event_type == 1);   # 1 = keyboard event
    return undef unless ($key_down);

    my $key = chr($char);

    # handle control keys
    if ($char <= 31) {
        $key = "C-" . lc(chr($char + 64));
    }

    if (exists($keycodemap{$virtual_keycode})) {
        $key = $keycodemap{$virtual_keycode};
    } else {
        # non-printable characters which we don't have in the keycode map-
        # ignore them.
        if ($char == 0) {    
            return undef;
        }
    }

    unless ($key =~ /^[MC]-/) {
        if ($control_key_state & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) {
            $key = "M-$key";
        }
        
        if ($control_key_state & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED)) {
            $key = "C-$key";
        }
    }

    return $key;
}


sub destroy {
    my ($self) = @_;
    DEBUG(@_);

    undef $self->{Buffer};
    
    # and remove this window from the list..
    @windows = grep { $_ ne $self } @windows;
}


sub clear {
    my ($self) = @_;
    DEBUG(@_);

    $self->{buffer}->Cls();
}


sub clear_background {
    my ($self, $style) = @_;
    DEBUG(@_);

    $self->{background_style} = $style;
    $self->{buffer}->Cls(get_attr_for_style($style));
}


sub set_style {
    my($self, $style) = @_;
    DEBUG(@_);

    $self->{buffer}->Attr(get_attr_for_style($style));
}


sub clear_line {
    my ($self, $y) = @_;
    DEBUG(@_);

    $self->{buffer}->FillChar(" ", $self->{cols}, 0, $y);
    
    $self->move_point($y, 0);
}


sub move_point {
    my ($self, $y, $x) = @_;
    DEBUG(@_);

    $self->{buffer}->Cursor($x, $y, 0, 0);
}


sub addstr_at_point {
    my ($self, $string) = @_;
    DEBUG(@_);

   defined($self->{buffer}->Write($string)) || 
       die "Error in Write";
}


sub addstr {
    my ($self, $y, $x, $string) = @_;
    DEBUG(@_);

    defined($self->{buffer}->WriteChar($string, $x, $y)) ||
        die "Error in WriteChar";
}


sub insch {
    my ($self, $y, $x, $character) = @_;
    DEBUG(@_);

    # figure out where we are and what's left of the line..
    my $charsleft = $self->{cols} - $x;

    # slide the line forward and add the character.
    my $str = $self->{buffer}->ReadChar($charsleft-1, $x, $y);
    $self->{buffer}->WriteChar($character . $str, $x, $y);
}


sub delch_at_point {
    my ($self) = @_;
    DEBUG(@_);

    # figure out where we are and what's left of the line..
    my ($x, $y) =  $self->{buffer}->Cursor();
    my $charsleft = $self->{cols} - $x;

    # slide the line back.
    my $str = $self->{buffer}->ReadChar($charsleft, $x+1, $y);
    $self->{buffer}->WriteChar($str . ' ', $x, $y);
}


sub scroll {
    my ($self, $numlines) = @_;
    DEBUG(@_);

    # what to fill the new line with..
    my $attr = $self->get_attr_for_style($self->{background_style});

    if ($numlines > 0) {

# Scroll() didn't work for me.
#        $self->{buffer}->Scroll(0, $numlines, 
#                                $self->{cols}, $self->{lines} - $numlines, 
#                                0, 0, 
#                                ' ', $attr) || die "Error scrolling window";
    
        # scroll up.
        my $rect = $self->{buffer}->ReadRect(0, $numlines,
	                                     $self->{cols}, $self->{lines});
	$self->{buffer}->WriteRect($rect, 
	                          0, 0,
				  $self->{cols}, $self->{lines} - $numlines);

        # blank out the area at the bottom.
        $self->{buffer}->WriteRect((" " x $numlines * $self->{cols}),
	                           0, $self->{lines} - $numlines,
				   $self->{cols}, $self->{lines});
				  
    } else {
    
# Scroll() didn't work for me.    
#        $self->{buffer}->Scroll(0, 0,
#                                $self->{cols}, $self->{lines},
#                                0, 0-$numlines, 
#                                ' ', $attr) || die "Error scrolling window";

        # scroll down.
        my $rect = $self->{buffer}->ReadRect(0, 0,
	                                     $self->{cols}, $self->{lines} - $numlines);
	$self->{buffer}->WriteRect($rect, 
	                          0, $numlines,
				  $self->{cols}, $self->{lines});
  
        # blank out the area at the top.
        $self->{buffer}->WriteRect((" " x $numlines * $self->{cols}),
	                           0, 0,
				   $self->{cols}, $numlines);
    }

    # and slap the cursor at the bottom.
    $self->move_point($self->{lines} - $numlines, 0);  
}


sub commit {
    my ($self) = @_;
    DEBUG(@_);

}


sub reset_styles {
    DEBUG(@_);

}


sub defstyle {
    my($style, @attrs) = @_;
    DEBUG(@_);

}


sub defcstyle {
    my($style, $fg, $bg, @attrs) = @_;
    DEBUG(@_);

}

###############################################################################
# Private functions

sub get_attr_for_style {
    my ($self) = @_;

    $main::ATTR_NORMAL;
}

1;
