package TLily::UI::Curses::Input;

use strict;
use vars qw(@ISA);
use TLily::UI::Curses::Generic;

@ISA = qw(TLily::UI::Curses::Generic);


sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = $class->SUPER::new(@_);

	$self->{text}        = "";
	$self->{password}    = 0;
	$self->{point}       = 0;
	$self->{Y}           = 0;
	$self->{X}           = 0;
	$self->{topln}       = 0;
	$self->{kill_buffer} = "";
	$self->{kill_reset}  = 0;
	$self->{prefix}      = "";
	$self->{text_lines}  = 1;
	$self->{history}     = [ "" ];
	$self->{history_pos} = 0;

	bless($self, $class);
}


sub password {
	my($self, $v) = @_;
	$self->{password} = $v;
	$self->rationalize();
	$self->redraw();
}


sub find_coords {
	my($self, $point) = @_;
	$point = $self->{password} ? 0 : $self->{point}
		unless (defined($point));
	$point += length($self->{prefix});

	my $y = int($point / $self->{cols}) - $self->{topln};
	my $x =     $point % $self->{cols};
	return ($y, $x);
}


sub drawlines {
	my($self, $start, $count) = @_;
	$count = $self->{lines} if (!$count || $count > $self->{lines});

	my $text = $self->{prefix};
	$text   .= $self->{text} unless ($self->{password});
	my $i = ($start && $start > 0) ? $start : 0;
	my $ti = (($i + $self->{topln}) * $self->{cols});

	while (($ti < length($text)) &&
	       ($start - $i < $count)) {
		$self->{W}->clrtoeol($i, 0);
		$self->{W}->addstr(substr($text, $ti, $self->{cols}));
		$i++;
		$ti += $self->{cols};
	}
}


sub redraw {
	my($self) = @_;

	$self->{W}->erase();
	$self->drawlines(0, $self->{lines});
	$self->{W}->noutrefresh();
}


sub position_cursor {
	my($self) = @_;
	$self->{W}->move($self->{Y}, $self->{X});
	$self->{W}->noutrefresh();
}


sub rationalize {
	my($self) = @_;

	my $text_len  = length($self->{prefix});
	my $text_len += length($self->{text}) unless ($self->{password});

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


sub end_of_word {
	my($self) = @_;
	if (substr($self->{text}, $self->{point}) =~ /^(.*?\w+)/) {
		return $self->{point} + length($1);
	} else {
		return length($self->{text});
	}
}


sub start_of_word {
	my($self) = @_;
	if (substr($self->{text}, 0, $self->{point}) =~ /^(.*\W)\w/) {
		return length($1);
	}  else {
		return 0;
	}
}


sub prefix {
	my($self, $prefix) = @_;
	$self->{prefix} = $prefix;
	$self->rationalize();
	$self->redraw();
}


sub accept_line {
	my($self) = @_;
	my $text = $self->{text};

	$self->{text}  = "";
	$self->{point} = 0;
	$self->rationalize();
	$self->redraw();

	if ($text ne "" && $text ne $self->{history}->[-1]) {
		$self->{history}->[-1] = $text;
		push @{$self->{history}}, "";
		$self->{history_pos} = $#{$self->{history}};
	}

	return $text;
}


sub previous_history {
	my($self) = @_;
	return if ($self->{history_pos} <= 0);
	$self->{history}->[$self->{history_pos}] = $self->{text};
	$self->{history_pos}--;
	$self->{text} = $self->{history}->[$self->{history_pos}];
	$self->{point} = length $self->{text};
	$self->rationalize();
	$self->redraw();
}


sub next_history {
	my($self) = @_;
	return if ($self->{history_pos} >= $#{$self->{history}});
	$self->{history}->[$self->{history_pos}] = $self->{text};
	$self->{history_pos}++;
	$self->{text} = $self->{history}->[$self->{history_pos}];
	$self->{point} = length $self->{text};
	$self->rationalize();
	$self->redraw();
}


sub get {
	my($self) = @_;
	return($self->{point}, $self->{text});
}


sub set {
	my($self, $point, $text) = @_;
	$self->{point} = $point;
	if (defined $text) {
		$self->{text} = $text;
		$self->rationalize();
		$self->redraw();
	} else {
		$self->rationalize();
	}
}


sub addchar {
	my($self, $c) = @_;

	substr($self->{text}, $self->{point}, 0) = $c;
	$self->{point}++;

	$self->{kill_reset} = 1;
	return if ($self->{password});

	$self->{W}->insch($self->{Y}, $self->{X}, $c);

	for (my $i = $self->{Y}+1; $i < $self->{lines}; $i++) {
		my $start = ($self->{topln} + $i) * $self->{cols};
		last if ($start > length($self->{text}));
		$self->{W}->insch($i, 0, substr($self->{text}, $start, 1));
	}

	$self->rationalize();
}


sub del {
	my($self) = @_;
	return if ($self->{point} >= length($self->{text}));

	substr($self->{text}, $self->{point}, 1) = "";

	$self->{kill_reset} = 1;
	return if ($self->{password});

	$self->{W}->move($self->{Y}, $self->{X});
	for (my $i = $self->{Y}; $i < $self->{lines}; $i++) {
		$self->{W}->delch();
		my $start = ($self->{topln} + $i + 1) * $self->{cols} - 1;
		last if ($start >= length($self->{text}));
		$self->{W}->addch($i, $self->{cols}-1,
				  substr($self->{text}, $start, 1));
		$self->{W}->move($i + 1, 0);
	}

	$self->rationalize();
}


sub bs {
	my($self) = @_;
	return if ($self->{point} == 0);

	$self->{point}--;
	$self->rationalize();
	$self->del();
	$self->{kill_reset} = 1;
}


sub backward_char {
	my($self) = @_;
	$self->{point}-- unless ($self->{point} <= 0);
	$self->rationalize();
	$self->{kill_reset} = 1;
}


sub forward_char {
	my($self) = @_;
	$self->{point}++ unless ($self->{point} >= length($self->{text}));
	$self->rationalize();
	$self->{kill_reset} = 1;
}


sub beginning_of_line {
	my($self) = @_;
	$self->{kill_reset} = 1;
	$self->{point} = 0;
	$self->rationalize();
}


sub end_of_line {
	my($self) = @_;
	$self->{kill_reset} = 1;
	$self->{point} = length($self->{text});
	$self->rationalize();
}


sub forward_word {
	my($self) = @_;
	$self->{kill_reset} = 1;
	$self->{point} = $self->end_of_word();
	$self->rationalize();
}


sub backward_word {
	my($self) = @_;
	$self->{kill_reset} = 1;
	$self->{point} = $self->start_of_word();
	$self->rationalize();
}


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

	$self->{kill_reset} = 1;
	return if ($self->{password});

	for my $c ($c1, $c2) {
		my($y, $x) = $self->find_coords($c);
		next if ($y < 0);
		$self->{W}->addch($y, $x, substr($self->{text}, $c, 1));
	}

	$self->{W}->noutrefresh();
}


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


sub yank {
	my($self) = @_;
	substr($self->{text}, $self->{point}, 0) = $self->{kill_buffer};
	$self->{point} += length($self->{kill_buffer});
	$self->rationalize();
	$self->redraw();
}


sub kill_line {
	my($self) = @_;
	return if ($self->{point} >= length($self->{text}));
	$self->kill_append($self->{point});
	$self->rationalize();
	$self->redraw();
}


sub backward_kill_line {
	my($self) = @_;
	return if ($self->{point} == 0);
	$self->kill_prepend(0, $self->{point});
	$self->{point} = 0;
	$self->rationalize();
	$self->redraw();
}


sub kill_word {
	my($self) = @_;
	my $e = $self->end_of_word();
	$self->kill_append($self->{point}, $e - $self->{point});
	$self->rationalize();
	$self->redraw();
}


sub backward_kill_word {
	my($self) = @_;
	my $s = $self->start_of_word();
	$self->kill_prepend($s, $self->{point} - $s);
	$self->{point} = $s;
	$self->rationalize();
	$self->redraw();
}


1;
