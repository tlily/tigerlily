#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Curses/Attic/Input.pm,v 1.24 2001/01/26 03:01:54 neild Exp $

package TLily::UI::Curses::Input;

use strict;
use vars qw(@ISA);
use Curses;
use TLily::UI::Curses::Generic;
use TLily::Config qw(%config);

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

# Return two character class regexps that will match or not match
# (respectively) a word character.
sub word_characters {
    my $wordchars = ($config{word_characters} ? $config{word_characters} : "")
                    . "A-Za-z0-9";
    return ("[$wordchars]", "[^$wordchars]");
}


# Returns the offset in the input string of the end of the current word.
sub end_of_word {
    my($self) = @_;
    my($word, $notword) = word_characters();

    if (substr($self->{text}, $self->{point}) =~ /^(.*?$word+)/) {
	return $self->{point} + length($1);
    } else {
	return length($self->{text});
    }
}


# Returns the offset in the input string of the start of the current word.
sub start_of_word {
    my($self) = @_;
    my($word, $notword) = word_characters();


    if (substr($self->{text}, 0, $self->{point}) =~ /^(.*$notword)$word/) {
	return length($1);
    } else {
	return 0;
    }
}

sub end_of_sentence {
    my($self) = @_;
    my $spaces = $config{doublespace_period} ? "  " : " ";

    if (substr($self->{text}, $self->{point}) =~
        /^(.*?[.!?][]\"')]*)($| $|\t|$spaces)/) {  # from Emacs
	return $self->{point} + length($1);
    } else {
	return length($self->{text});
    }
}

sub start_of_sentence {
    my($self) = @_;
    my $spaces = $config{doublespace_period} ? "  " : " ";

    if (substr($self->{text}, 0, $self->{point}) =~
        /^((.*[.!?][]\"')]*)($| $|\t|$spaces)[ \t]*)[^ \t]/) {
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

    foreach my $hist_idx (keys %{$self->{saved_history}}) {
        $self->{history}->[$hist_idx] = $self->{saved_history}->{$hist_idx};
        delete $self->{saved_history}->{$hist_idx};
    }

    if ($text ne "" && ! $self->{'password'} &&
        ($#{$self->{history}} == 0 || $text ne $self->{history}->[-2])) {
	$self->{history}->[-1] = $text;
	push @{$self->{history}}, "";
    }

    $self->{history_pos} = $#{$self->{history}};

    return $text;
}

# Save the current history entry and replace it with the current text.
# It will be restored after accept_line runs.
sub save_history_excursion {
    my ($self) = @_;

    # This function only has relevance if the text of current history
    # entry is different from the current input buffer.
    if ($self->{history}->[$self->{history_pos}] ne $self->{text}) {

        # Save the current history entry if it has not already been saved.
        if (! defined $self->{saved_history}->{$self->{history_pos}}) {
            $self->{saved_history}->{$self->{history_pos}} =
              $self->{history}->[$self->{history_pos}];
        }
    
        # Set the current history entry to the current input buffer.
        $self->{history}->[$self->{history_pos}] = $self->{text};
    }
}

=item search_history()

Executes a search through the input buffer for a given string, in a given
direction.  The search will start at the last position it reached during
a previous call, unless the saved position is reset.  It takes the
following arguments:

=over

string - The string being searched for.

dir    - What direction to search in buffer.
         -1 (default) for backwards, 1 for forwards.

reset  - Reset the saved position.

next_match - whether this search should find the next occurrence, in
         the same direction, for the string.

switch_dir - whether this search is for the same string as the last
         search, but going in the other direction.

=back

=cut

# Search through the history for a given string
sub search_history {
    my $self = shift;
    my %args = @_;
    my $string = $args{string};
    my $case_fold = defined($config{case_fold_search}) ?
                            $config{case_fold_search} : 1;

    # Reset the saved search position.
    $self->{_search_pos} = $self->{history_pos}
        if (!defined($self->{_search_pos}) || $args{"reset"});

    # If no string is passed, return.
    return unless defined($string) && length($string) > 0;

    # ASSERT().
    die "switch_dir and next_match are mutually exclusive at "
        if $args{switch_dir} && $args{next_match};

    # Normalize the direction; default to -1.
    my $dir = -1;
    $dir = ($args{dir} >= 0) ? 1 : -1 if defined $args{dir};

    my $hist_idx = $self->{_search_pos};
    my $length = length $self->{history}->[$hist_idx]
        if defined $self->{history}->[$hist_idx];

    # Prefix and suffix are used to block off parts of the line from
    # being viewed.  They are necessary when looking at the current entry
    # to either extend the search or change its direction. 
    my ($prefix, $suffix);

    if ($args{'next_match'}) {
        # The next match can't include the first character (when going forward)
        # or the last character (when going backward) of the current match.
        # The prefix thus needs to be masked off when going forward, and
        # the suffix masked when going backward.
        $prefix = $dir == 1 ? $self->{point} - length($string) + 1 : 0;
        $suffix = $dir == 1 ? 0 : $length - length($string) - $self->{point}+1;

    } elsif ($args{'switch_dir'}) {
        # Switching directions should just move point to the other side
        # of the existing match.  To ensure that another match is not found
        # in text that has not yet been examined, the prefix and suffix must
        # be masked.  (Consider:  "biz bang boom", and the reverse search for
        # "b" is at the start of "boom".  Just making it a forward search
        # without masking would first find the "b" in "biz".
        $prefix = $dir == 1 ? $self->{point} : 0;
        $suffix = $dir == 1 ? 0 : $length - $self->{point};

    } elsif ($self->{_search_pos} == $self->{history_pos} &&
             ($dir ==  1 && $self->{point} >= $self->{_search_anchor}) ||
             ($dir == -1 && $self->{point} <= $self->{_search_anchor})) {
        # The search is in the line it started at.  _search_anchor is where
        # point is when the search started, so it should bound the search.
        #
        # The shenanigans with checking to see whether the _search_anchor
        # is behind point for a forward search or ahead of it for a reverse
        # search are needed to detech when a search has left the line
        # but returned to it.  Consider:  two lines "bono" and "oooo".  Point
        # starts in the middle of "oooo" when a reverse search is done for "o"
        # and repeated until it is at the "o" following "n" in "bono".  Now
        # type C-s twice and then type another "o".  Without the additional
        # _search_anchor tests above, the search will stop at the end of "oooo"
        # rather than the middle, because the search for 'oo' is starting in
        # the same line that the whole search started in, and the
        # _search_anchor is set at the middle of the line.  
        #
        # XXXDCL BUG: Same starting scenario.  C-r o C-r C-r =>
        # now at "o" in "bono".  C-s o => now in middle of "oooo".
        # Press Delete (or whatever backward-delete-char you have) =>
        # now at third "o" in "oooo" instead of at end of "bono".
        # This happens in this case because point == _search_pos in the line
        # starting the search, but the overall problem is a bit deeper.
        # Arguably the _search_anchor should be set to the point where the
        # search changed direction, but (currently) that would also involve
        # changing the history_pos so that both "reset" and this block worked
        # correctly, but that could give quite unexpected results if the
        # search terminated as via C-g -- the history_pos would be wherever
        # the search direction switched instead of wherever the search was
        # started.
        #
        # I guess one way to *probably* fix this would be to have the
        # references to $ui->{save_excursion} in ui.pl also save/restore
        # $ui->{input}->{history_pos}, but frankly I'm kind of tired of working
        # on this, and this particular bug is not especially troubling to
        # me at the moment.  Feel Free(tm).
        $prefix = $dir == 1 ? $self->{_search_anchor} : 0;
        $suffix = $dir == 1 ? 0 : $length - $self->{_search_anchor};
    }

    # Greedy is used to tell whether the perl "*" operator should be greedy
    # or not; when looking for the last match on a line it should be, otherwise
    # it should not be.
    my $greedy = $dir == 1 ? "?" : "";
    my $regexp;

    # Do the actual search.
    while (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}) ) {
        $prefix = 0 unless defined $prefix;
        $suffix = 0 unless defined $suffix;

        $regexp = "^((.{$prefix})(.*$greedy))\Q$string\E.{$suffix,}\$";

        if ((  $case_fold && $self->{history}->[$hist_idx] =~ /$regexp/i) ||
            (! $case_fold && $self->{history}->[$hist_idx] =~ /$regexp/)) {

            # The scope of $1 is local to this block, so its value needs
            # to be saved here.  Set the cursor to the first character of the
            # matched string for a reverse search, or the last character for a
            # forward search.
            $self->{point} = length($1);
            $self->{point} += length($string) if $dir == 1;

            last;
        }

        undef $prefix;
        undef $suffix;

        $hist_idx += $dir;
    }
    return unless (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}));

    # Save the current position in the history for the next search.
    $self->{_search_pos} = $hist_idx;

    # Copy the text found to the current slot.
    $self->{text} = $self->{history}->[$hist_idx];

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
    $self->save_history_excursion;
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
    $self->save_history_excursion;
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

sub forward_sentence {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = $self->end_of_sentence();
    $self->rationalize();
}

sub backward_sentence {
    my($self) = @_;
    $self->{kill_reset} = 1;
    $self->{point} = $self->start_of_sentence();
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

# This is zsh-like, not Emacs-like.  zsh-like it more intuitive, I believe,
# because it allows you to transpose the last two words entered, while Emacs
# does not.
sub transpose_words {
    my($self) = @_;
    my($word, $notword) = word_characters();
    my($word1_start, $word2_start, $word2_end);
    my($point_in_word1, $point_in_word2);

    $self->{kill_reset} = 1;

    # First, identify where the cursor is with regard to surrounding words.
    # The first match will attempt to find the last two groups of word
    # characters before point.
    substr($self->{text}, 0, $self->{point}) =~
        /^(.*?)($word+)($notword*)($word*)($notword*)$/i;

    #print STDERR "1='$1', 2='$2', 3='$3', 4='$4', 5='$5'\n";

    # The length function is used to see whether a $word pattern matched so
    # that "0" can be identified as a word.  If just "if ($2)" were used,
    # then "0" would cause the test to fail.
    return if length($2) == 0;

    $word1_start = length($1);
    $point_in_word1 = ($3 ? 0 : 1);

    if (length($4) > 0) {
      $word2_start = length($1 . $2 . $3);
      $word2_end = $word2_start + length($4);
      $point_in_word2 = ($5 ? 0 : 1);
    }

    # Now match the word characters following point.
    substr($self->{text}, $self->{point}) =~
        /^($word*)($notword*)($word*)/i;

    # If point is wholly within word1 (not just at its end), then nothing
    # can be transposed.
    return if $point_in_word1 && length($1) > 0;

    # Adjust the start of word1 and end of word2 with regard to where point is.
    if ($point_in_word2 && length($1) > 0) {
        # point is wholly in word2 (not just at its end), so only the end
        # of the word2 needs to adjusted because word1_start already points
        # to the right place.
        $word2_end = $self->{point} + length($1);

    } elsif (length($1) > 0) {
        # point is right at the start of a word, but word1_start points to
        # two words back, and word2_start points to the prior word.
        $word1_start = $word2_start;
        $word2_end = $self->{point} + length($1);

    } elsif (length($3) > 0) {
        # point is between words, but word1_start points to
        # two words back, and word2_start points to the prior word.
        $word1_start = $word2_start;
        $word2_end = $self->{point} + length($2 . $3);
    }

    # With the bounds of the start of word1 and the end of word2, the rest
    # is easy.
    substr($self->{text}, $word1_start, $word2_end - $word1_start) =~
        s/^($word+)($notword+)($word+)$/$3$2$1/i;

    $self->{point} = $word2_end;

    $self->update_style();
    $self->rationalize();
    $self->redraw();
}

sub capitalize_word {
    my($self) = @_;
    my ($word, $notword) = word_characters();

    $self->{kill_reset} = 1;

    substr($self->{text}, $self->{point}) =~
        s/^([^a-z]*)([a-z]?)($word*)/$1\u$2\L$3/i;

    $self->{point} += length($1 . $2 . $3);

    $self->update_style();
    $self->rationalize();
    $self->redraw();
}

sub down_case_word {
    my($self) = @_;
    my ($word, $notword) = word_characters();

    $self->{kill_reset} = 1;

    substr($self->{text}, $self->{point}) =~
        s/^($notword*)($word*)/$1\L$2/;

    $self->{point} += length($1 . $2);

    $self->update_style();
    $self->rationalize();
    $self->redraw();
}

sub up_case_word {
    my($self) = @_;
    my ($word, $notword) = word_characters();

    $self->{kill_reset} = 1;

    substr($self->{text}, $self->{point}) =~
        s/^($notword*)($word*)/$1\U$2/;

    $self->{point} += length($1 . $2);

    $self->update_style();
    $self->rationalize();
    $self->redraw();
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
