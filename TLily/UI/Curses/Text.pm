#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Curses/Attic/Text.pm,v 1.23 2001/02/09 00:24:10 kazrak Exp $

package TLily::UI::Curses::Text;

use strict;
use vars qw(@ISA);
use Curses;
use TLily::UI::Util qw(next_line);
use TLily::UI::Curses::Generic;
use TLily::Event;
use TLily::Config qw(%config);

@ISA = qw(TLily::UI::Curses::Generic);

TLily::User::shelp_r('max_scrollback' => 'How many lines of scrollback to keep',
        'variables');
TLily::User::help_r('variables max_scrollback' => q(
The maximum number of lines of scrollback to keep at any time.  This number
may be exceeded under certain circumstances; nothing will be expired while
it is on-screen.
));

# These are handy in a couple of places.
sub max($$) { ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min($$) { ($_[0] < $_[1]) ? $_[0] : $_[1] }


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %a = @_;
    my $self  = $class->SUPER::new(bg => 'text_window', @_);

    # The contents of the text widget are stored in one big string.
    $self->{text}        = "";

    # Style and indentation information are stored in arrays.  The
    # style array is a list of (text position, style) pairs, and the
    # indentation array is a list of (text position, style, string)
    # pairs.  Using subarrays to store the entries would be simpler,
    # but consumes one hell of a lot more memory.  Each entry is
    # terminated with a text position which MUST be larger than the
    # size of the text buffer.  (It is used as a guard when searching
    # the array.)
    $self->{styles}      = [ 0, "default", 1 ];
    $self->{indents}     = [ 0, "default", "", 1];

    # Lines may be indexed by line number through 'indexes' (the
    # offset into the text buffer for the start of each line).
    $self->{indexes}     = [ 0 ];

    # The index of the bottommost line in the window (the 'anchor').
    $self->{idx_anchor}  = 0;

    # The index of the first line the user has not seen. (For paging.)
    $self->{idx_unseen}  = 0;

    # An associated status window, which will be used to display paging
    # information.
    $self->{status}      = $a{status};
    $self->{status}->define(t_more => 'override') if ($self->{status});

    # Is paging active?
    $self->{'page'}       = defined($config{page}) ? $config{page} : 1;

    bless($self, $class);
}


# Standard resize-handler.
sub size {
    my $self = shift;
    my $newc = $_[3];

    # If we are being resized, and our width changed, we need to
    # re-word-wrap the buffer.
    if ($newc && ($newc != $self->{cols})) {
	$self->{indexes}  = [ 0 ];
	pos($self->{text}) = 0;
	while (next_line($self->{text}, $self->{cols})) {
	    push @{$self->{indexes}}, pos($self->{text});
	}
	pop @{$self->{indexes}} if (@{$self->{indexes}} > 1);
    }

    return $self->SUPER::size(@_);
}


# Set whether paging is active.
sub page {
    my $self = shift;
    return $self->{'page'} if (@_ == 0);
    $self->{'page'} = $_[0];
}


# Internal function to set the more prompt in the status window.
sub set_pager {
    my($self, $handler) = @_;

    if ($handler) {
	TLily::Event::idle_u($handler);
	$self->{pager_on_idle} = undef;
    }

    return unless ($self->{status});
    my $r = $#{$self->{indexes}} - $self->{idx_anchor};
    if ($r <= 0) {
	$self->{status}->set(t_more => undef);
    } else {
	$self->{status}->set(t_more => "-- MORE ($r) --");
    }

    if ($handler) {
	TLily::UI::Curses::Generic::position_cursor();
	doupdate();
    }
}


# Update the pager when next idle.
sub set_pager_on_idle {
    my($self) = @_;
    return if ($self->{pager_on_idle});
    $self->{pager_on_idle} = TLily::Event::idle_r(obj => $self,
						  call => \&set_pager);
    return;
}


# Line formatting and output.  A number of the following functions
# operate on a "line" data structure.  Each such structure
# encapsulates the information needed to display a line.  A line
# structure is an arrayref containing:
#   The starting index in the text buffer.
#   The style to draw the indentation string in.
#   The indentation string.
#   A list of pairs:
#     A style to draw in.
#     An index in the text buffer.

# Generates a line data structure.  Takes:
#  $start, $end - Start and end indices of the text to print.
#  $sidx - Index into the style buffer.  Must be <= the index of the
#          first style to be used.
#  $iidx - Index into the indent buffer to use.
sub format_line {
    my($self, $start, $end, $sidx, $iidx) = @_;
    $sidx ||= 0;

    my $line = [$start];
    push @$line, $self->{indents}->[$iidx+1], $self->{indents}->[$iidx+2];

    my $pos  = $start;
    while ($pos < $end) {
	while ($self->{styles}->[$sidx] <= $pos) {
	    $sidx += 2;
	}

	push @$line, $self->{styles}->[$sidx-1];
	push @$line, (min($self->{styles}->[$sidx],$end) - $pos);
	$pos = $self->{styles}->[$sidx];
    }

    return $line;
}


# Writes a line to the screen at the given coordinates.
sub draw_line {
    my($self, $y, $x, $line) = @_;
    #print STDERR "=== draw_line(@_)\n";
    #print STDERR "=== draw_line: ", join(", ", @$line), "\n";

    $self->{W}->clrtoeol($y, $x);
    $self->draw_style($line->[1]);
    $self->{W}->addstr($line->[2]);
    my $start = $line->[0];
    for (my $i = 3; $i < @$line; $i+=2) {
	$self->draw_style($line->[$i]);
	$self->{W}->addstr(substr($self->{text},
				  $start, $line->[$i+1]));
	$start += $line->[$i+1];
    }
}

# dumps out the review buffer to a file :)
sub dump_to_file {
    my ($self, $filename) = @_;

    local(*FILE);
    open(FILE, ">$filename") ||
       $self->print("(Unable to open $filename for writing: $!)\n");

    my $count = 0;
    foreach my $line ($self->fetch_lines()) {
        my $start = $line->[0];   
        for (my $i = 3; $i < @$line; $i+=2) {
            print FILE (substr($self->{text}, $start, $line->[$i+1]));
            $start += $line->[$i+1];
        }        
        print FILE "\n";	
	$count++;
    }
    
    close(FILE);  
    return $count;
}


# Does a search through the style or indent array to find the index
# corresponding to a given offset in the text.  The $sz argument is
# the size of one entry in the array being searched: 2 for the style
# array, 3 for the indent array.
sub binary_index_search {
    my($aref, $offset, $sz) = @_;
    #print STDERR "bis: @_\n";
    #print STDERR "     ", join(", ",@$aref), "\n";
    my $min = 0;
    my $max = $#$aref/$sz;
    while (1) {
	my $pos = $min+int(($max-$min)/2);
	my $idx = $pos * $sz;
	#print STDERR " min=$min max=$max pos=$pos idx=$idx\n";
	if ($aref->[$idx] > $offset) {
	    $max = $pos;
	} elsif ($aref->[$idx+$sz] <= $offset) {
	    $min = $pos;
	} else {
	    #print STDERR " => $idx\n";
	    return $idx;
	}
    }
}


# Returns the next $count lines, starting at $offset in the text.
sub fetch_lines {
    my($self, $offset, $count) = @_;
    #print STDERR "*** fetch_lines @_ ***\n";

    my $st_idx = binary_index_search($self->{styles}, $offset, 2);
    my $in_idx = binary_index_search($self->{indents}, $offset, 3);

    my $len = $self->{cols} - length($self->{indents}->[$in_idx+2]);

    pos($self->{text}) = $offset;
    my @lines = ();
    while (!$count || @lines < $count) {
	my($b, $e) = next_line($self->{text}, $len);
	last if (!defined $e);
	push @lines, $self->format_line($b, $e, $st_idx, $in_idx);
	last if (pos($self->{text}) == length($self->{text}));

	while ($self->{styles}->[$st_idx+2] <= pos($self->{text})) {
	    $st_idx += 2;
	}

	while ($self->{indents}->[$in_idx+3] <= pos($self->{text})) {
	    $in_idx += 3;
	    $len = $self->{cols} -
	      length($self->{indents}->[$in_idx+2]);
	}

    }

    return @lines;
}


# Draws $count lines, starting at line index $idx, to the screen,
# starting at screen line $y.
sub draw_lines {
    my($self, $y, $idx, $count) = @_;
    #print STDERR "*** draw_lines @_ ***\n";

    # For lines which don't exist ($idx < 0), just clear the line.
    while ($idx < 0 && $count > 0) {
	$self->{W}->clrtoeol($y++, 0);
	$count--;
	$idx++;
    }
    return unless ($count > 0);

    # Fetch and draw lines.
    my @lines = $self->fetch_lines($self->{indexes}->[$idx], $count);
    while (@lines && $count > 0) {
	$self->draw_line($y++, 0, shift @lines);
	$count--;
    }

    # Clear any lines which remain.
    while ($count > 0) {
	$self->{W}->clrtoeol($y++, 0);
	$count--;
    }
}


# Redraw the entire window.
sub redraw {
    my($self) = @_;

    $self->{W}->erase;
    $self->draw_lines(0, $self->{idx_anchor} - $self->{lines} + 1,
		      $self->{lines});
    $self->{W}->noutrefresh;
}


# Send a line of text to the window.
sub print {
    my($self, $text) = @_;

    $self->{text} .= $text;
    $self->{styles}->[-1]  = length($self->{text}) + 1;
    $self->{indents}->[-1] = length($self->{text}) + 1;

    # rbj =-= Adding expiry here.  Check if we've passed our maximum
    # length; if so, expire the first line.
    while ($#{$self->{indexes}} > $config{max_scrollback} &&
           $config{max_scrollback} > 0 &&
           $self->{idx_anchor} > $self->{lines}) {
        $self->{idx_anchor}--;
        $self->{idx_unseen}--;
        my $linelen = $self->{indexes}->[1];
        $self->{text} = substr($self->{text}, $linelen);
        shift @{$self->{indexes}};
        my $style = undef;
        for (my $i = 0; $i < $#{$self->{styles}}; ) {
            $self->{styles}->[$i] -= $linelen;
            if ($self->{styles}->[$i] < 0) {
                shift @{$self->{styles}}; # Gets rid of the index
                $style = shift @{$self->{styles}}; # Gets rid of the style
            } else {
                if ($style && $self->{styles}->[$i] > 0) {
                    # Insert the last style with offset 0 when we otherwise
                    # wouldn't have a style that starts there.
                    unshift @{$self->{styles}}, (0, $style);
                    undef $style;
                    $i += 2;
                }
                $i += 2;
            }
        }
        if ($#{$self->{styles}} < 3) {
            $self -> {styles} = [ 0, "default", length($self->{text}) + 1];
        }
        my $indent = undef;
        $style = undef;
        for (my $i = 0; $i < $#{$self->{indents}}; ) {
            $self->{indents}->[$i] -= $linelen;
            if ($self->{indents}->[$i] < 0) {
                shift @{$self->{indents}}; # Gets rid of the index
                $style = shift @{$self->{indents}}; # Gets rid of the style
                $indent = shift @{$self->{indents}}; # Gets rid of the string
            } else {
                if ($style && $self->{indents}->[$i] > 0) {
                    # Insert the last style/indent with offset 0 when we
                    # otherwise wouldn't have a style/offset that starts there.
                    unshift @{$self->{indents}}, (0, $style, $indent);
                    undef $style;
                    undef $indent;
                    $i += 3;
                }
                $i += 3;
            }
        }
        if ($#{$self->{indents}} < 3) {
            $self->{indents} =
              [ 0, "default", "", length($self->{text}) + 1];
        }
        for (my $i = 0; $i <= $#{$self->{indexes}}; $i++) {
            $self->{indexes}->[$i] -= $linelen;
        }
    }

    my @lines = $self->fetch_lines($self->{indexes}->[-1]);
    for (my $i = 1; $i < @lines; $i++) {
	push @{$self->{indexes}}, $lines[$i]->[0];
    }

    if ($self->{idx_anchor} < $#{$self->{indexes}} - @lines + 1) {
	$self->set_pager_on_idle();
	return;
    }

    my $max_scroll = $self->{lines} - ($self->{idx_anchor} -
				       $self->{idx_unseen});
    $max_scroll = $self->{lines} unless ($self->{'page'});
    return if ($max_scroll <= 0);

    $self->{idx_anchor} = $#{$self->{indexes}};
    while (@lines > $max_scroll) {
	pop @lines;
	$self->{idx_anchor}--;
    }

    if (@lines >= $self->{lines}) {
	$self->{W}->erase();
	while (@lines > $self->{lines}) {
	    shift @lines;
	}
    }

    # Scroll the screen, if necessary.
    elsif (@lines > 1) {
	$self->{W}->scrollok(1);
	$self->{W}->scrl(@lines - 1);
	$self->{W}->scrollok(0);
    }

    my $base = $self->{lines} - @lines;
    for (my $i = 0; $i < @lines; $i++) {
	$self->draw_line($base + $i, 0, $lines[$i]);
    }

    $self->set_pager_on_idle();
    $self->{W}->noutrefresh;
};


# Scroll the window by $scroll lines.  Positive numbers scroll down,
# negative scroll up.
sub scroll {
    my($self, $scroll) = @_;
    my($idx, $mark);

    if ($scroll > 0) {
	$scroll = min($scroll, $#{$self->{indexes}} - $self->{idx_anchor});
	$idx = $self->{idx_anchor} + 1;
	$mark = $self->{lines} - $scroll;
    }

    elsif ($scroll < 0) {
	$scroll = max($scroll, -$self->{idx_anchor});
	$idx = $self->{idx_anchor} - $self->{lines} + 1 + $scroll;
	$mark = 0;
    }

    return if ($scroll == 0);

    $self->{idx_anchor} += $scroll;
    $self->{idx_unseen} = max($self->{idx_unseen}, $self->{idx_anchor} + 1);
    $self->set_pager();

    if ($scroll >= $self->{lines} || $scroll <= -$self->{lines}) {
	$self->redraw();
	return;
    }

    $self->{W}->scrollok(1);
    $self->{W}->scrl($scroll);
    $self->{W}->scrollok(0);

    $self->draw_lines($mark, $idx, max($scroll, -$scroll));
    $self->{W}->noutrefresh;
}


# Scroll the window by $scroll pages.  Positive numbers scroll down,
# negative scroll up.
sub scroll_page {
    my($self, $scroll) = @_;
    $self->scroll($scroll * $self->{lines});
}


# Scroll the window to the top of the text.
sub scroll_top {
    my($self) = @_;
    $self->{idx_anchor} = min($self->{lines}-1, $#{$self->{indexes}});
    $self->set_pager();
    $self->redraw();
    return;
}


# Scroll the window to the bottom of the text.
sub scroll_bottom {
    my($self) = @_;
    $self->{idx_anchor} = $#{$self->{indexes}};
    $self->set_pager();
    $self->redraw();
    return;
}


# Set the current output style.
sub style {
    my($self, $style) = @_;

    if ($self->{styles}->[-3] == length($self->{text})) {
	pop @{$self->{styles}};
	pop @{$self->{styles}};
    }
    $self->{styles}->[-1] = length($self->{text});

    push @{$self->{styles}}, $style, length($self->{text})+1;
}


# Set the current indentation string.
sub indent {
    my $self  = shift;
    my($style, $str) = @_;
    $style = (@_ > 1) ? shift : "default";
    $str   = (@_)     ? shift : "";
    $style = "default" if (!defined $style);
    $str   = ""        if (!defined $str);

    if ($self->{indents}->[-4] == length($self->{text})) {
	pop @{$self->{indents}};
	pop @{$self->{indents}};
	pop @{$self->{indents}};
    }
    $self->{indents}->[-1] = length($self->{text});

    push @{$self->{indents}}, $style, $str, length($self->{text})+1;
}


# Mark the current visible area as having been seen by the user.
sub seen {
    my($self) = @_;
    $self->{idx_unseen} = max($self->{idx_unseen}, $self->{idx_anchor} + 1);
}


# Return the number of lines remaining in the scroll buffer.
sub lines_remaining {
    my($self) = @_;
    my $r = $#{$self->{indexes}} - $self->{idx_anchor};
    return ($r <= 0) ? 0 : $r;
}


1;
