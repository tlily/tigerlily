package TLily::UI::Curses::Text;

use strict;
use vars qw(@ISA);
use TLily::UI::Curses::Generic;

@ISA = qw(TLily::UI::Curses::Generic);


# These are handy in a couple of places.
sub max($$) { ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min($$) { ($_[0] < $_[1]) ? $_[0] : $_[1] }


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %a = @_;
    my $self  = $class->SUPER::new(bg => 'textwin', @_);

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
	while ($self->next_line()) {
	    push @{$self->{indexes}}, pos($self->{text});
	}
	pop @{$self->{indexes}} if (@{$self->{indexes}} > 1);
    }

    return $self->SUPER::size(@_);
}


# Internal function to set the more prompt in the status window.
sub set_pager {
    my($self) = @_;

    return unless ($self->{status});
    my $r = $#{$self->{indexes}} - $self->{idx_anchor};
    if ($r <= 0) {
	$self->{status}->set(t_more => undef);
    } else {
	$self->{status}->set(t_more => "-- MORE ($r) --");
    }
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


# Returns the starting and ending indices of the next line in the text
# buffer.  The search starts at pos($self->{text}), and pos is updated
# by this function.  Returns undef if no lines remain.  $len, if
# supplied is the maximum line length to return; this defaults to the
# window width.
sub next_line {
    my($self, $len) = @_;
    $len = $self->{cols} if (!defined $len);

    # Bail if we are at the end of the buffer.
    return if (pos($self->{text}) &&
	       pos($self->{text}) == length($self->{text}));

    # Wordwrapping is in the lily style: words longer than N
    # (currently 10) characters will not be broken.  We consider the
    # string to find as containing two parts: the initial portion
    # which cannot be wordwrapped ($len - 10 here), and the remainder
    # which can.

    # The initial, non-breakable portion.
    my $imatch = $len - 10;
    $imatch = 0 if ($imatch < 0);

    # The remainder, less one.
    my $nmatch = $len - $imatch - 1;
    return if ($nmatch <= 0);

    # Here is the wordwrapper.
    my $mstart = pos($self->{text});
    $self->{text} =~ m(\G
                       # These need not be wrapped.
		       (?: .{0,$imatch})
		       (?:
                          # Either break on a space/newline...
                          (?: .{0,$nmatch} (?: \s | $ )) |
                          # Or none is available, so take what we can fit.
			  (?: ..{0,$nmatch})
		       )
		      )xg or return;
    my $mend = pos($self->{text});

    # I don't think this is strictly necessary, but why take chances?
    $mend-- if (substr($self->{text}, $mend-1, 1) eq "\n");

    #my $ll = substr($self->{text}, $mstart, $mend-$mstart);
    #$ll =~ s/\n/*/g;
    #print STDERR "  == $mstart $mend \"$ll\"\n";
    return ($mstart, $mend);
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
	my($b, $e) = $self->next_line($len);
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

    my @lines = $self->fetch_lines($self->{indexes}->[-1]);
    for (my $i = 1; $i < @lines; $i++) {
	push @{$self->{indexes}}, $lines[$i]->[0];
    }

    if ($self->{idx_anchor} < $#{$self->{indexes}} - @lines + 1) {
	$self->set_pager();
	return;
    }

    my $max_scroll = $self->{lines} - ($self->{idx_anchor} -
				       $self->{idx_unseen});
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

    $self->set_pager();
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
    my $style = (@_ > 1) ? shift : "default";
    my $str   = (@_)     ? shift : "";
    $style    = "default" if (!defined $style);
    $str      = ""        if (!defined $str);

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
