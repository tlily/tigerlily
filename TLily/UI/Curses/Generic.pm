package LC::UI::Curses::Generic;

use strict;
use vars qw(%stylemap %cstylemap %cmap %cnamemap %cpairmap %keycodemap);
use Curses;


my $meta    = 0;
my @widgets = ();

# The stylemap and cstylemap hashes map style names to Curses attributes.
%stylemap   = (default => A_NORMAL);
%cstylemap  = (default => A_NORMAL);

# The cnamemap hash maps English color names to Curses colors.
%cnamemap   =
  (
   black            => COLOR_BLACK,
   red              => COLOR_RED,
   yellow           => COLOR_YELLOW,
   blue             => COLOR_BLUE,
   magenta          => COLOR_MAGENTA,
   white            => COLOR_WHITE,
  );

# The cpairmap hash maps color pairs in the format "fg bg" to color pair
# IDs.  (fg and bg are Curses color IDs.)
%cpairmap   = ();

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


sub parsestyle {
	my $style = 0;
	foreach my $attr (@_) {
		if ($attr eq 'normal') {
			$style |= A_NORMAL;
		} elsif ($attr eq 'standout') {
			$style |= A_STANDOUT;
		} elsif ($attr eq 'underline') {
			$style |= A_UNDERLINE;
		} elsif ($attr eq 'reverse') {
			$style |= A_REVERSE;
		} elsif ($attr eq 'blink') {
			$style |= A_BLINK;
		} elsif ($attr eq 'dim') {
			$style |= A_DIM;
		} elsif ($attr eq 'bold') {
			$style |= A_BOLD;
		} elsif ($attr eq 'altcharset') {
			$style |= A_ALTCHARSET;
		}
	}
	return $style;
}


sub color_pair {
	my($fg, $bg) = @_;
	my $pair;

	return 0 unless (defined $fg && defined $bg);

	$fg = defined($cnamemap{$fg}) ? $cnamemap{$fg} : $cmap{default}->[0];
	$bg = defined($cnamemap{$bg}) ? $cnamemap{$bg} : $cmap{default}->[1];

	if (defined $cpairmap{"$fg $bg"}) {
		$pair = $cpairmap{"$fg $bg"};
	} else {
		$pair = scalar(keys %cpairmap)+1;
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
			$w->redraw();
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
			$w->redraw();
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
	#print STDERR "c: '$c' (", ord($c), ")\n";
	if ($c eq chr(27)) {
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

	return $r;
}


1;
