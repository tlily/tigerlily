package LC::UI::Curses::Text;

use strict;
use vars qw(@ISA);
use LC::UI::Curses::Generic;

@ISA = qw(LC::UI::Curses::Generic);


sub max($$) { ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min($$) { ($_[0] < $_[1]) ? $_[0] : $_[1] }


sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my %a = @_;
	my $self  = $class->SUPER::new(bg => 'textwin', @_);

	# The contents of the text widget are stored in one big string.
	$self->{text}        = "";

	# Style information is stored in an array.  This array contains
	# a list of { text position, style } entries.  These entries are
	# not stored as subarrays for memory efficiency.  The last entry
	# in this array is the size of the text buffer.  (This makes
	# a couple operations simpler to implement.)
	$self->{styles}      = [ 0, "default", 0 ];
	$self->{indents}     = [ 0, "default", "", 0];

	# Lines may be indexed by line number through 'indexes' (the
	# offset into the text buffer for the start of each line).
	$self->{indexes}     = [ 0 ];

	# The index of the bottommost line in the window (the 'anchor').
	$self->{idx_anchor}  = 0;

	# The index of the first line the user has not seen. (For paging.)
	$self->{idx_unseen}  = 0;

	$self->{status}      = $a{status};
	$self->{status}->define(t_more => 'override') if ($self->{status});

	bless($self, $class);
}


sub size {
	my $self = shift;
	my $newl = $_[3];

	if ($newl && ($newl != $self->{lines})) {
		$self->{indexes}  = [ 0 ];
		pos($self->{text}) = 0;
		while ($self->next_line()) {
			push @{$self->{indexes}}, pos($self->{text});
		}
		pop @{$self->{indexes}} if (@{$self->{indexes}} > 1);
	}

	return $self->SUPER::size(@_);
}


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


sub next_line {
	my($self, $len) = @_;
	$len = $self->{cols} if (!defined $len);

	return if (pos($self->{text}) &&
		   pos($self->{text}) == length($self->{text}));

	my $imatch = $len - 10;
	$imatch = 0 if ($imatch < 0);
	my $nmatch = $len - $imatch;

	my $mstart = pos($self->{text});
	$self->{text} =~ m(\G
			   (?:
			    (?: .{0,$imatch})
			    (?: 
			     (?: .{0,$nmatch} (?= \s | $ )) |
			     (?: .{0,$nmatch})
			    )
			   )
			  )xg or return;

	my $mend = pos($self->{text});
	if (pos($self->{text}) < length($self->{text})) {
		my $rmatch = max(0, $len - ($mend - $mstart));
		my $rc = ($self->{text} =~ m/(\G {0,$rmatch})\n?/gs);
		$mend += length $1;
	}

	#my $ll = substr($self->{text}, $mstart, $mend-$mstart);
	#$ll =~ s/\n/*/g;
	#print STDERR "  == $mstart $mend \"$ll\"\n";
	return ($mstart, $mend);
}


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
		} elsif ($aref->[$idx+$sz] < $offset) {
			$min = $pos;
		} else {
			#print STDERR " => $idx\n";
			return $idx;
		}
	}
}


sub fetch_lines {
	my($self, $offset, $count) = @_;

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


sub draw_lines {
	my($self, $y, $idx, $count) = @_;
	#print STDERR "*** draw_lines @_ ***\n";

	while ($idx < 0 && $count > 0) {
		$self->{W}->clrtoeol($y++, 0);
		$count--;
		$idx++;
	}
	return unless ($count > 0);

	#print STDERR "  y=$y idx=$idx count=$count\n";

	my @lines = $self->fetch_lines($self->{indexes}->[$idx], $count);
	#print STDERR "  found ", scalar(@lines), " lines.\n";
	while (@lines && $count > 0) {
		$self->draw_line($y++, 0, shift @lines);
		$count--;
	}

	#print STDERR "  y=$y idx=$idx count=$count\n";
	while ($count > 0) {
		$self->{W}->clrtoeol($y++, 0);
		$count--;
	}
}


sub redraw {
	my($self) = @_;

	$self->{W}->erase;
	$self->draw_lines(0, $self->{idx_anchor} - $self->{lines} + 1,
			  $self->{lines});
	$self->{W}->noutrefresh;
}


sub print {
	my($self, $text) = @_;

	$self->{text} .= $text;
	$self->{styles}->[-1]  = length($self->{text});
	$self->{indents}->[-1] = length($self->{text});

	my @lines = $self->fetch_lines($self->{indexes}->[-1]);
	for (my $i = 1; $i < @lines; $i++) {
		push @{$self->{indexes}}, $lines[$i]->[0];
	}

	if ($self->{idx_anchor} < $#{$self->{indexes}} - @lines + 1) {
		$self->set_pager();
		return;
	}

	$self->{idx_anchor} = $#{$self->{indexes}};

	my $max_scroll = $self->{lines} - ($self->{idx_anchor} -
					   $self->{idx_unseen});
	return if ($max_scroll <= 0);
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
}


sub scroll {
	my($self, $scroll) = @_;
	my($idx, $mark);

	if ($scroll > 0) {
		$scroll = min($scroll,
			      $#{$self->{indexes}} - $self->{idx_anchor});
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


sub style {
	my($self, $style) = @_;
	push @{$self->{styles}}, $style, length($self->{text});
}


sub indent {
	my($self) = @_;
	my($style, $str);
	if (@_ == 2) {
		push @{$self->{indents}}, "default", $_[1];
	} else {
		push @{$self->{indents}}, $_[1], $_[2];
	}
	push @{$self->{indents}}, length($self->{text});
}


sub seen {
	my($self) = @_;
	$self->{idx_unseen} = @{$self->{indexes}} + 1;
}


1;
