package LC::UI::Curses::Proxy;

use strict;
use vars qw($AUTOLOAD);
use Curses;

sub new {
	my($proto, $ui, $win) = @_;
	my $class = ref($proto) || $proto;
	my $self  = [$ui, $win];
	bless($self, $class);
	return $self;
}

sub style {
	my($self, $style) = @_;
	$self->[0]->{text}->{$self->[1]}->{text}->style($style);
}


sub indent {
	my $self = shift;
	$self->[0]->{text}->{$self->[1]}->{text}->indent(@_);
}


sub print {
	my $self = shift;
	$self->[0]->{text}->{$self->[1]}->{text}->print(join('', @_));
	$self->[0]->{input}->position_cursor();
	doupdate();
}


sub seen {
	my($self) = @_;
	$self->[0]->{text}->{$self->[1]}->{text}->seen(); }


AUTOLOAD {
	my $self = shift;
	$AUTOLOAD =~ s/.*:://;
	$self->[0]->$AUTOLOAD(@_);
}


package LC::UI::Curses;

use strict;
use vars qw(@ISA %commandmap %bindmap);

use LC::UI;
use Curses;
use LC::UI::Curses::Text;
use LC::UI::Curses::StatusLine;
use LC::UI::Curses::Input;

@ISA = qw(LC::UI);


#
# Use Term::Size to determine the terminal size after a SIGWINCH, but don't
# actually require that it be installed.
#

my $termsize_installed;
my $sigwinch;
BEGIN {
	eval { require Term::Size; import Term::Size; };
	if ($@) {
		warn("*** WARNING: Unable to load Term::Size ***\n");
		$termsize_installed = 0;
	} else {
		$termsize_installed = 1;
	}
}


sub accept_line {
	my($ui) = @_;
	my $text = $ui->{input}->accept_line();
	$ui->{text}->{main}->{text}->seen();
	$ui->style("user_input");
	$ui->print($text, "\n");
	$ui->style("normal");
	$ui->{event}->send(type => 'user_input',
			   text => $text,
			   ui   => $ui);
}


# The default set of mappings from command names to functions.
%commandmap = 
  (
   'accept-line'          => \&accept_line,
   'previous-history'     => sub { $_[0]->{input}->previous_history(); },
   'next-history'         => sub { $_[0]->{input}->next_history(); },
   'insert-self'          => sub { $_[0]->{input}->addchar($_[2]) },
   'forward-char'         => sub { $_[0]->{input}->forward_char(); },
   'backward-char'        => sub { $_[0]->{input}->backward_char(); },
   'forward-word'         => sub { $_[0]->{input}->forward_word(); },
   'backward-word'        => sub { $_[0]->{input}->backward_word(); },
   'beginning-of-line'    => sub { $_[0]->{input}->beginning_of_line(); },
   'end-of-line'          => sub { $_[0]->{input}->end_of_line(); },
   'delete-char'          => sub { $_[0]->{input}->del(); },
   'backward-delete-char' => sub { $_[0]->{input}->bs(); },
   'transpose-chars'      => sub { $_[0]->{input}->transpose_chars(); },
   'kill-line'            => sub { $_[0]->{input}->kill_line(); },
   'backward-kill-line'   => sub { $_[0]->{input}->backward_kill_line(); },
   'kill-word'            => sub { $_[0]->{input}->kill_word(); },
   'backward-kill-word'   => sub { $_[0]->{input}->backward_kill_word(); },
   'yank'                 => sub { $_[0]->{input}->yank(); },
   'page-up'              => sub { $_[0]->{text}->{main}->{text}->scroll(-($LINES-1)); },
   'page-down'            => sub { $_[0]->{text}->{main}->{text}->scroll($LINES-1); },
   'line-up'              => sub { $_[0]->{text}->{main}->{text}->scroll(-1); },
   'line-down'            => sub { $_[0]->{text}->{main}->{text}->scroll(1); },
   'refresh'              => sub { $_[0]->redraw(); },
   'suspend'              => sub { kill 'TSTP', $$; },
  );

# The default set of keybindings.
%bindmap =
  (
   'right'      => 'forward-char',
   'C-F'        => 'forward-char',
   'left'       => 'backward-char',
   'C-B'        => 'backward-char',
   'M-f'        => 'forward-word',
   'M-b'        => 'backward-word',
   'C-A'        => 'beginning-of-line',
   'C-E'        => 'end-of-line',
   'C-P'        => 'previous-history',
   'up'         => 'previous-history',
   'C-N'        => 'next-history',
   'down'       => 'next-history',
   'C-D'        => 'delete-char',
   'del'        => 'delete-char',
   'bs'         => 'backward-delete-char',
   'C-H'        => 'backward-delete-char',
   'C-T'        => 'transpose-chars',
   'C-K'        => 'kill-line',
   'C-U'        => 'backward-kill-line',
   'M-d'        => 'kill-word',
   'C-W'        => 'backward-kill-word',
   'C-Y'        => 'yank',
   'nl'         => 'accept-line',
   'pageup'     => 'page-up',
   'C-B'        => 'page-up',
   'pagedown'   => 'page-down',
   'C-F'        => 'page-down',
   'C-Y'        => 'line-up',
   'C-E'        => 'line-down',
   'C-L'        => 'refresh',
   'C-Z'        => 'suspend',
  );


sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = $class->SUPER::new(@_);
	my %arg   = @_;
	bless($self, $class);

	$self->{want_color} = (defined($arg{color}) ? $arg{color} : 1);
	$self->{input_maxlines} = $arg{input_maxlines};
	start_curses($self);

	$self->{text}->{main}->{status} = LC::UI::Curses::StatusLine->new
	  (layout  => $self,
	   color   => $self->{color});

	$self->{text}->{main}->{text} = LC::UI::Curses::Text->new
	  (layout  => $self,
	   color   => $self->{color},
	   status  => $self->{text}->{main}->{status});

	$self->{input} = LC::UI::Curses::Input->new
	  (layout  => $self,
	   color   => $self->{color});

	$self->{command}  = { %commandmap };
	$self->{bindings} = { %bindmap };

	$self->layout();

	$self->{event}->io_r(handle => \*STDIN,
			     mode   => 'r',
			     call   => sub { $self->run; });

	return $self;
}


sub splitwin {
	my($self, $name) = @_;

	unless ($self->{text}->{$name}) {
		$self->{text}->{$name}->{status} = LC::UI::Curses::StatusLine->new
		  ( layout => $self, color => $self->{color} );

		$self->{text}->{$name}->{text} = LC::UI::Curses::Text->new
		  ( layout => $self, color => $self->{color},
		    status => $self->{text}->{$name}->{status} );

		$self->layout();
	}

	return LC::UI::Curses::Proxy->new($self, $name);
}


sub start_curses {
	my($self) = @_;

	initscr;

	$self->{color} = 0;
	if ($self->{want_color}) {
		$self->{color} = has_colors();
	}
	if ($self->{color}) {
		my $rc = start_color() if ($self->{color});
		$self->{color} = 0 if ($rc && $rc == ERR);
	}

	noecho();
	raw();
	idlok(1);
	idcok(1);
	typeahead(-1);

	$SIG{WINCH} = sub { $sigwinch = 1; };
}


sub stop_curses {
	my($self) = @_;
	endwin;
}


sub DESTROY {
	my($self) = @_;
	$self->stop_curses();
}


# Re-layout the widgets.
sub layout {
	my($self) = @_;

	my $tcount = scalar(keys %{$self->{text}});
	
	# Calculate the max height the input line is allowed to grow to.
	my $imax = $self->{input_imax} || ($LINES - (2 * $tcount));
	$imax = 1 if ($imax <= 0);

	# Find out how large the input line wants to be.
	my($ilines, $icols) = $self->{input}->req_size();
	$ilines = 1 if (!$ilines);
	$ilines = $imax if ($ilines > $imax);

	my $tlines = ($LINES - $ilines) / $tcount;
	my $trem   = ($LINES - $ilines) % $tcount;
	my $y      = 0;

	foreach my $tpair (values %{$self->{text}}) {
		my $l = $tlines;
		if ($trem) { $l++; $trem--; }

		$tpair->{text}->size($y, 0, $l-1, $COLS);
		$y += $l-1;

		$tpair->{status}->size($y, 0, 1, $COLS);
		$y++;
	}

	$self->{input}->size($LINES - $ilines, 0, $ilines, $COLS);

	$self->redraw();
}


sub size_request {
	my($self, $win, $lines, $cols) = @_;
	$self->layout();
}


sub run {
	my($self) = @_;

	while ($sigwinch) {
		$sigwinch = 0;
		if ($termsize_installed) {
			($ENV{'COLUMNS'}, $ENV{'LINES'}) = Term::Size::chars();
		}
		$self->stop_curses();
		$self->start_curses();
		$self->layout();
	}

	my $key = $self->{input}->read_char();
	return unless $key;
	#print STDERR "key='$key'\n";

	my $cmd = $self->{bindings}->{$key};
	if ($cmd && $self->{command}->{$cmd}) {
		$self->{command}->{$cmd}->($self, $cmd, $key);
	} elsif (length($key) == 1) {
		$self->{input}->addchar($key);
	}

	$self->{input}->position_cursor;
	doupdate;
}


sub needs_terminal {
	1;
}


sub suspend {
	my($self) = @_;
	endwin;
}


sub resume {
	my($self) = @_;
	doupdate;
}


sub defstyle {
	my($self, $style, @attrs) = @_;
	LC::UI::Curses::Generic::defstyle($style, @attrs);
}


sub defcstyle {
	my($self, $style, $fg, $bg, @attrs) = @_;
	LC::UI::Curses::Generic::defcstyle($style, $fg, $bg, @attrs);
}


sub clearstyle {
	my($self) = @_;
	LC::UI::Curses::Generic::clearstyle();
}


sub style {
	my($self, $style) = @_;
	$self->{text}->{main}->{text}->style($style);
}


sub indent {
	my $self = shift;
	$self->{text}->{main}->{text}->indent(@_);
}


sub print {
	my $self = shift;
	$self->{text}->{main}->{text}->print(join('', @_));
	$self->{input}->position_cursor();
	doupdate();
}


sub redraw {
	my($self) = @_;

	foreach my $tpair (values %{$self->{text}}) {
		$tpair->{text}->redraw();
		$tpair->{status}->redraw();
	}
	$self->{input}->redraw();
	$self->{input}->position_cursor();
	doupdate();
}


sub command_r {
	my($self, $command, $func) = @_;
	return if ($self->{command}->{$command});
	$self->{command}->{$command} = $func;
	return 1;
}


sub command_u {
	my($self, $command) = @_;
	return unless ($self->{command}->{$command});
	delete $self->{command}->{$command};
	return 1;
}


sub bind {
	my($self, $key, $command) = @_;
	$self->{bindings}->{$key} = $command;
	return 1;
}


sub command {
	my($self, $command, $key) = @_;
	$self->{command}->{$command}->($self, $command, $key);
}


sub prompt {
	my($self, $prompt) = @_;
	$self->{input}->prefix($prompt);
	doupdate;
}


sub define {
	my($self, $name, $pos) = @_;
	$self->{text}->{main}->{status}->define($name, $pos);
	doupdate;
}


sub set {
	my($self, $name, $val) = @_;
	$self->{text}->{main}->{status}->set($name, $val);
	doupdate;
}


sub get_input {
	my($self) = @_;
	return $self->{input}->get();
}


sub set_input {
	my $self = shift;
	return $self->{input}->set(@_);
}

1;
