#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Curses/Attic/Input.pm,v 1.19 2000/02/05 21:13:52 neild Exp $

package TLily::UI::Curses::Input;

use strict;
use vars qw(@ISA);
use Curses;
use TLily::UI::Curses::Generic;

@ISA = qw(TLily::UI::Curses::Generic);

# These are handy in a couple of places.
sub max($$) { ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min($$) { ($_[0] < $_[1]) ? $_[0] : $_[1] }

=head1 NAME

TLily::UI::Curses::Input - Curses input window

=head1 DESCRIPTION

=head1 FUNCTIONS

=over 10

=item TLily::UI::Curses::Input->new()

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(bg => "input_window", @_);

    # Point is the location of the input cursor.  Text is the input line.
    $self->{point}       = 0;
    $self->{text}        = "";

    # The current screen coordinates of point.
    $self->{Y}           = 0;
    $self->{X}           = 0;

    # A flag indicating if password mode is set.  The contents of the input
    # line are not drawn when in password mode.
    $self->{'password'}  = 0;

    $self->{topln}       = 0;
    $self->{text_lines}  = 1;

    # The current kill buffer.
    $self->{kill_buffer} = "";

    # If this is set, the next kill operation will replace the current
    # contents of the kill buffer.
    $self->{kill_reset}  = 0;

    # The prefix or prompt string.
    $self->{prefix}      = "";

    # The input history, and current position within it.
    $self->{history}     = [ "" ];
    $self->{history_pos} = 0;

    $self->{'style_fn'}  = undef;
    $self->{style}       = [1, "input_window"];

    bless($self, $class);
}



=item password()

=cut

# Set password mode on/off.  The contents of the input line are not drawn
# when in password mode.
sub password {
    my($self, $v) = @_;
    $self->{'password'} = $v;
    $self->rationalize();
    $self->redraw();
}


# Translates an offset into the input string into a y/x coordinate pair.
sub find_coords {
    my($self, $point) = @_;
    $point = $self->{'password'} ? 0 : $self->{point}
      unless (defined($point));
    $point += length($self->{prefix});

    my $y = int($point / $self->{cols}) - $self->{topln};
    my $x =     $point % $self->{cols};
    return ($y, $x);
}


# Update the style definition, using the style function.
sub update_style {
    my($self) = @_;

    # 5 foo 6 bar 2 baz
    # 5 foo 7 bar 2 baz

    my @f = (length($self->{prefix}), "input_prefix");
    push @f, $self->{'style_fn'}->($self->{text}) if ($self->{'style_fn'});
    push @f, (length($self->{text})), "input_window";
    $self->{style} = \@f;

    return;
}


# Set the style function.
sub style_fn {
    my $self = shift;
    $self->{'style_fn'} = shift if (@_);
    $self->update_style;
    return $self->{'style_fn'};
}


# Set the style as appropriate for a given character position.
sub char_style {
    my($self, $pos) = @_;

    my $c = 0;
    my $i = 0;
    while ($c < $pos) {
	$c += $self->{style}->[$i];
	$i += 2;
	die "input style meltdown!\n" if ($i > @{$self->{style}});
    }

    $self->draw_style($self->{style}->[$i+1] || $self->{bg});
    return;
}


# Writes lines from the input string onto the screen.
sub drawlines {
    my($self, $start, $count) = @_;
    $count = $self->{lines} if (!$count || $count > $self->{lines});

    my $text = $self->{prefix};
    $text   .= $self->{text} unless ($self->{'password'});
    my $i = ($start && $start > 0) ? $start : 0;
    my $ti = (($i + $self->{topln}) * $self->{cols});

    my @f = @{$self->{style}};
    $f[0] -= $ti;

    my $col = 0;
    $self->{W}->clrtoeol($i, 0);
    while (($ti < length($text)) &&
	   ($start - $i < $count)) {
	while ($f[0] <= 0) {
	    $f[2] += $f[0];
	    shift @f; shift @f;
	}

	my $c = min($self->{cols} - $col, $f[0]);

	$self->draw_style($f[1]);
	$self->{W}->addstr(substr($text, $ti, $c));

	$col += $c;
	$ti += $c;
	$f[0] -= $c;

	if ($col >= $self->{cols}) {
	    $i++;
	    $col -= $self->{cols};
	    $self->{W}->clrtoeol($i, 0) if ($i < $self->{lines});
	}
    }
}


# Standard widget redraw function.
sub redraw {
    my($self) = @_;

    $self->{W}->erase();
    $self->drawlines(0, $self->{lines});
    $self->{W}->noutrefresh();
}


# Ensures that the input cursor is located on-screen.
sub rationalize {
    my($self) = @_;

    my $text_len  = length($self->{prefix});
    $text_len += length($self->{text}) unless ($self->{'password'});

    my $text_lines = int($text_len / $self->{cols}) + 1;
    if ($text_lines != $self->{text_lines}) {
	$self->{text_lines} = $text_lines;
	$self->req_size($text_lines, $self->{cols});
    }

    my($y, $x) = $self->find_coords();

    if ($y >= $self->{lines}) {
	my $sc = $y - $self->{lines} + 1;
	$self->{topln} += $sc;

	$self->{W}->scrollok(1);
	$self->{W}->scrl($sc);
	$self->{W}->scrollok(0);

	$self->drawlines($self->{lines} - $sc, $sc);
	$y = $self->{lines} - 1;
    } elsif ($y < 0) {
	$self->{topln} += $y;

	$self->{W}->scrollok(1);
	$self->{W}->scrl($y);
	$self->{W}->scrollok(0);

	$self->drawlines(0, -$y);
	$y = 0;
    }

    $self->{Y} = $y;
    $self->{X} = $x;
    $self->{W}->noutrefresh();
}


# Returns the offset in the input string of the end of the current word.
sub end_of_word {
    my($self) = @_;
    if (substr($self->{text}, $self->{point}) =~ /^(.*?\w+)/) {
	return $self->{point} + length($1);
    } else {
	return length($self->{text});
    }
}


# Returns the offset in the input string of the start of the current word.
sub start_of_word {
    my($self) = @_;
    if (substr($self->{text}, 0, $self->{point}) =~ /^(.*\W)\w/) {
	return length($1);
    } else {
	return 0;
    }
}


# Sets the prefix (or prompt) string.
sub prefix {
    my($self, $prefix) = @_;
    $self->{prefix} = defined($prefix) ? $prefix : "";
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Clear the current input line and insert it into the history.
sub accept_line {
    my($self) = @_;
    my $text = $self->{text};

    $self->{text}  = "";
    $self->{point} = 0;
    $self->update_style();
    $self->rationalize();
    $self->redraw();

    if ($text ne "" && $text ne $self->{history}->[-1] && !$self->{'password'}) {
	$self->{history}->[-1] = $text;
	push @{$self->{history}}, "";
	$self->{history_pos} = $#{$self->{history}};
    }

    return $text;
}

=item search_history()

Executes a search through the input buffer for a given string, in a given
direction.  The search will start at the last position it reached during
a previous call, unless the saved position is reset.  It takes the
following arguments:

=over

string - The string being searched for.

dir    - What direction to search in buffer.  -1 (default) for backwards, 1 for
forwards.

reset  - Reset the saved position.

=back

=cut

# Search through the history for a given string
sub search_history {
    my $self = shift;
    my %args = @_;
    my $string = $args{string};

    # Reset the saved search position.
    $self->{_search_pos} = $self->{history_pos} if (!defined($self->{_search_pos}) || $args{reset});

    # If no string is passed, return.
    return unless ($string);

    # Normalize the direction; default to -1.
    my $dir = -1;
    $dir = ($args{dir} >= 0)?1:-1 if (defined $args{dir});

    my $hist_idx = $self->{_search_pos} + $dir;

    # Do the actual search.
    while (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}) ) {
        last if ($self->{history}->[$hist_idx] =~ /$string/);
        $hist_idx += $dir;
    }
    return unless (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}));

    # Save the current position in the history for the next search.
    $self->{_search_pos} = $hist_idx;

    # Copy the text found to the current slot.
    $self->{text} = $self->{history}->[$hist_idx];
    # And set the cursor to the first character of the matched string.
    $self->{point} = index($self->{text}, $string);

    $self->update_style();
    $self->rationalize();
    $self->redraw();

    # Return the text found to the caller.
    return $self->{text};
}

# Move back one entry in the history.
sub previous_history {
    my($self) = @_;
    return if ($self->{history_pos} <= 0);
    $self->{history}->[$self->{history_pos}] = $self->{text};
    $self->{history_pos}--;
    $self->{text} = $self->{history}->[$self->{history_pos}];
    $self->{point} = length $self->{text};
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Move forward one entry in the history.
sub next_history {
    my($self) = @_;
    return if ($self->{history_pos} >= $#{$self->{history}});
    $self->{history}->[$self->{history_pos}] = $self->{text};
    $self->{history_pos}++;
    $self->{text} = $self->{history}->[$self->{history_pos}];
    $self->{point} = length $self->{text};
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Return the current (point, text).
sub get {
    my($self) = @_;
    return wantarray ? ($self->{point}, $self->{text}) : $self->{point};
}


# Set the current (point, text).
sub set {
    my($self, $point, $text) = @_;
    $self->{point} = $point;
    if (defined $text) {
	$self->{text} = $text;
	$self->update_style();
	$self->rationalize();
	$self->redraw();
    } else {
	$self->rationalize();
    }
}


# Insert a character at the current point.
sub addchar {
    my($self, $c) = @_;

    substr($self->{text}, $self->{point}, 0) = $c;
    $self->{point}++;
    $self->update_style();

    $self->{kill_reset} = 1;
    return if ($self->{'password'});

    if ($self->{'style_fn'}) {
	$self->rationalize();
	$self->redraw();
	return;
    }

    $self->char_style($self->{point}-1);
    $self->{W}->insch($self->{Y}, $self->{X}, $c);

    for (my $i = $self->{Y}+1; $i < $self->{lines}; $i++) {
	my $start = ($self->{topln} + $i) * $self->{cols};
	last if ($start > length($self->{text}));
	$self->char_style($start);
	$self->{W}->insch($i, 0, substr($self->{text}, $start, 1));
    }

    $self->rationalize();
}


# Delete the character immediately after point.
sub del {
    my($self) = @_;
    return if ($self->{point} >= length($self->{text}));

    substr($self->{text}, $self->{point}, 1) = "";
    $self->update_style();

    $self->{kill_reset} = 1;
    return if ($self->{'password'});

    if ($self->{'style_fn'}) {
	$self->rationalize();
	$self->redraw();
	return;
    }

    $self->{W}->move($self->{Y}, $self->{X});
    for (my $i = $self->{Y}; $i < $self->{lines}; $i++) {
	$self->{W}->delch();
	my $start = ($self->{topln} + $i + 1) * $self->{cols} - 1;
	last if ($start >= length($self->{text}));
	$self->char_style($start);
	$self->{W}->addch($i, $self->{cols}-1,
			  substr($self->{text}, $start, 1));
	$self->{W}->move($i + 1, 0);
    }

    $self->rationalize();
}


# Delete the character immediately before point.
sub bs {
    my($self) = @_;
    return if ($self->{point} == 0);

    $self->{point}--;
    $self->rationalize();
    $self->del();
    $self->{kill_reset} = 1;
}


# Move point back one character.
sub backward_char {
    my($self) = @_;
    $self->{point}-- unless ($self->{point} <= 0);
    $self->rationalize();
    $self->{kill_reset} = 1;
}


# Move point forward one character.
sub forward_char {
    my($self) = @_;
    $self->{point}++ unless ($self->{point} >= length($self->{text}));
    $self->rationalize();
    $self->{kill_reset} = 1;
}


# Move point to the start of the line.
sub beginning_of_line {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = 0;
    $self->rationalize();
}


# Move point to the end of the line.
sub end_of_line {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = length($self->{text});
    $self->rationalize();
}


# Move point to the start of the next word.
sub forward_word {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = $self->end_of_word();
    $self->rationalize();
}


# Move point to the start of the current word.
sub backward_word {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = $self->start_of_word();
    $self->rationalize();
}


# Transpose the two characters before point.
sub transpose_chars {
    my($self) = @_;
    return if ($self->{point} == 0);

    my($c1, $c2);
    if ($self->{point} >= length($self->{text})) {
	($c1, $c2) = ($self->{point}-2, $self->{point}-1);
    } else {
	($c1, $c2) = ($self->{point}-1, $self->{point});
    }

    (substr($self->{text}, $c1, 1), substr($self->{text}, $c2, 1)) =
      (substr($self->{text}, $c2, 1), substr($self->{text}, $c1, 1));
    $self->update_style();

    $self->{kill_reset} = 1;
    return if ($self->{'password'});

    # Advance the character.
    $self->{point}++ unless $self->{point} >= length($self->{text});

    for my $c ($c1, $c2) {
	my($y, $x) = $self->find_coords($c);
	next if ($y < 0);
	$self->char_style($c);
	$self->{W}->addch($y, $x, substr($self->{text}, $c, 1));
    }

    $self->rationalize();
}

sub capitalize_word {
    my($self) = @_;

    substr($self->{text}, $self->{point}) =~
        s/^([^a-z0-9]*)([0-9]*)([a-z]?)([a-z]*)/$1$2\u$3\L$4/i;

    $self->{point} += length($1 . $2);

    for (my $i = 0; $i < length ($3 . $4); $i++) {
        my($y, $x) = $self->find_coords($self->{point});

        $self->char_style($self->{point});
        $self->{W}->addch($y, $x, substr($self->{text}, $self->{point}++, 1));
    }

    $self->rationalize();
}


# Kill a given range of text, and append it to the kill buffer.
sub kill_append {
    my($self, $start, $len) = @_;

    $self->{kill_buffer}  = "" if ($self->{kill_reset});
    $self->{kill_reset}   = 0;

    if ($len) {
	$self->{kill_buffer} .= substr($self->{text}, $start, $len);
	substr($self->{text}, $start, $len) = "";
    } else {
	$self->{kill_buffer} .= substr($self->{text}, $start);
	substr($self->{text}, $start) = "";
    }
}


# Kill a given range of text, and prepend it to the kill buffer.
sub kill_prepend {
    my($self, $start, $len) = @_;

    $self->{kill_buffer}  = "" if ($self->{kill_reset});
    $self->{kill_reset}   = 0;

    if ($len) {
	$self->{kill_buffer}  = (substr($self->{text}, $start, $len) .
				 $self->{kill_buffer});
	substr($self->{text}, $start, $len) = "";
    } else {
	$self->{kill_buffer}  = (substr($self->{text}, $start) .
				 $self->{kill_buffer});
	substr($self->{text}, $start) = "";
    }
}


# Copy the kill buffer to point.
sub yank {
    my($self) = @_;
    substr($self->{text}, $self->{point}, 0) = $self->{kill_buffer};
    $self->{point} += length($self->{kill_buffer});
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Kill from point to the end of the line.
sub kill_line {
    my($self) = @_;
    return if ($self->{point} >= length($self->{text}));
    $self->kill_append($self->{point});
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Kill from point to the start of the line.
sub backward_kill_line {
    my($self) = @_;
    return if ($self->{point} == 0);
    $self->kill_prepend(0, $self->{point});
    $self->{point} = 0;
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Kill to the end of the current word.
sub kill_word {
    my($self) = @_;
    my $e = $self->end_of_word();
    $self->kill_append($self->{point}, $e - $self->{point});
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


# Kill to the start of the current word.
sub backward_kill_word {
    my($self) = @_;
    my $s = $self->start_of_word();
    $self->kill_prepend($s, $self->{point} - $s);
    $self->{point} = $s;
    $self->update_style();
    $self->rationalize();
    $self->redraw();
}


1;
