#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Attic/Curses.pm,v 1.30 1999/04/13 00:27:56 josh Exp $

package TLily::UI::Curses::Proxy;

use strict;
use vars qw($AUTOLOAD @ISA); #) cperl mode is getting confused.
use Curses;
use Carp;

@ISA = qw(TLily::UI);

sub new {
    my($proto, $ui, $name) = @_;
    my $class       = ref($proto) || $proto;
    my $self        = $class->SUPER::new('name' => $name);
    $self->{ui}     = $ui;
    $self->{text}   = $ui->{win}->{$name}->{text};
    $self->{status} = $ui->{win}->{$name}->{status};
    $self->{input}  = $ui->{input};
    bless($self, $class);
}

sub style {
    my $self = shift;
    $self->{text}->style(@_);
}


sub indent {
    my $self = shift;
    $self->SUPER::indent(@_);
    $self->{text}->indent(@_);
}


sub page {
    my $self = shift;
    $self->{text}->page(@_);
}


sub print {
    my $self = shift;
    $self->SUPER::print(@_);
    $self->{text}->print(@_);
    $self->{input}->position_cursor();
    doupdate();
};


sub seen {
    my $self = shift;
    $self->{text}->seen(@_);
}


AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ s/.*:://;
    $self->{ui}->$AUTOLOAD(@_);
}


package TLily::UI::Curses;

use strict;
use vars qw(@ISA %commandmap %bindmap);

use Carp;
use TLily::UI;
use Curses;
use TLily::UI::Curses::Text;
use TLily::UI::Curses::StatusLine;
use TLily::UI::Curses::Input;
use TLily::Event;

@ISA = qw(TLily::UI); #) cperl mode is getting confused


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
    $ui->{text}->seen();

    if (@{$ui->{prompt}} > 0) {
	my $args = shift @{$ui->{prompt}};
	if (defined $args->{prompt}) {
	    $ui->prompt("");
	    $ui->print($args->{prompt});
	}

	if ($args->{password}) {
	    $ui->{input}->password(0);
	} else {
	    $ui->style("user_input");
	    $ui->print($text);
	    $ui->style("normal");
	}

	$ui->print("\n");
	$args->{call}->($ui, $text);

	if (@{$ui->{prompt}} > 0) {
	    $args = $ui->{prompt}->[0];
	    $ui->prompt($args->{prompt})
	      if (defined $args->{prompt});
	    $ui->{input}->password(1) if ($args->{password});
	}
    }

    elsif ($text eq "" && $ui->{text}->lines_remaining()) {
	$ui->command("page-down");
    }

    else {
	$ui->style("user_input");
	$ui->print($text, "\n");
	$ui->style("normal");

	TLily::Event::send(type => 'user_input',
			   text => $text,
			   ui   => $ui);
    }
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
   'page-up'              => sub { $_[0]->{text}->scroll_page(-1); },
   'page-down'            => sub { $_[0]->{text}->scroll_page(1); },
   'line-up'              => sub { $_[0]->{text}->scroll(-1); },
   'line-down'            => sub { $_[0]->{text}->scroll(1); },
   'scroll-to-top'        => sub { $_[0]->{text}->scroll_top(); },
   'scroll-to-bottom'     => sub { $_[0]->{text}->scroll_bottom(); },
   'refresh'              => sub { $_[0]->{input}->{W}->clearok(1); $_[0]->redraw(); },
   'suspend'              => sub { TLily::Event::keepalive(); kill 'TSTP', $$; },
  );

# The default set of keybindings.
%bindmap =
  (
   'right'      => 'forward-char',
   'C-f'        => 'forward-char',
   'left'       => 'backward-char',
   'C-b'        => 'backward-char',
   'M-f'        => 'forward-word',
   'M-b'        => 'backward-word',
   'C-a'        => 'beginning-of-line',
   'C-e'        => 'end-of-line',
   'C-p'        => 'previous-history',
   'up'         => 'previous-history',
   'C-n'        => 'next-history',
   'down'       => 'next-history',
   'C-d'        => 'delete-char',
   'del'        => 'delete-char',
   'bs'         => 'backward-delete-char',
   'C-h'        => 'backward-delete-char',
   'C-t'        => 'transpose-chars',
   'C-k'        => 'kill-line',
   'C-u'        => 'backward-kill-line',
   'M-d'        => 'kill-word',
   'C-w'        => 'backward-kill-word',
   'C-y'        => 'yank',
   'nl'         => 'accept-line',
   'C-m'        => 'accept-line',  
   'pageup'     => 'page-up',
   'M-v'        => 'page-up',
   'pagedown'   => 'page-down',
   'C-v'        => 'page-down',
   'M-['        => 'line-up',
   'M-]'        => 'line-down',
   'M-<'        => 'scroll-to-top',
   'M->'        => 'scroll-to-bottom',
   'C-l'        => 'refresh',
   'C-z'        => 'suspend',
  );


my $base_curses;
sub new {
    my $proto = shift;
    my %arg   = @_;

    return $base_curses->splitwin($arg{name}) if ($base_curses);

    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    bless($self, $class);

    $self->{want_color} = (defined($arg{color}) ? $arg{color} : 1);
    $self->{input_maxlines} = $arg{input_maxlines};
    start_curses($self);

    $self->{status} = TLily::UI::Curses::StatusLine->new
      (layout  => $self,
       color   => $self->{color});
    $self->{win}->{$arg{name}}->{status} = $self->{status};

    $self->{text} = TLily::UI::Curses::Text->new
      (layout  => $self,
       color   => $self->{color},
       status  => $self->{status});
    $self->{win}->{$arg{name}}->{text} = $self->{text};

    $self->{input} = TLily::UI::Curses::Input->new
      (layout  => $self,
       color   => $self->{color});

    $self->{input}->active();

    $self->{command}   = { %commandmap };
    $self->{bindings}  = { %bindmap };

    $self->{intercept} = undef;

    $self->{prompt}    = [];

    $self->layout();

    TLily::Event::io_r(handle => \*STDIN,
		       mode   => 'r',
		       call   => sub { $self->run; });

    $self->inherit_global_bindings();

    $base_curses = $self;
    return $self;
}


sub prompt_for {
    my($self, %args) = @_;
    croak("required parameter \"call\" missing.") unless ($args{call});

    push @{$self->{prompt}}, \%args;
    return if (@{$self->{prompt}} > 1);

    $self->prompt($args{prompt}) if (defined($args{prompt}));
    $self->{input}->password(1) if ($args{password});
    return;
}


sub splitwin {
    my($self, $name) = @_;

    unless ($self->{text}->{$name}) {
	$self->{win}->{$name}->{status} = TLily::UI::Curses::StatusLine->new
	  ( layout => $self, color => $self->{color} );

	$self->{win}->{$name}->{text} = TLily::UI::Curses::Text->new
	  ( layout => $self, color => $self->{color},
	    status => $self->{win}->{$name}->{status} );

	$self->layout();
    }

    return TLily::UI::Curses::Proxy->new($self, $name);
}


sub start_curses {
    my($self) = @_;

    initscr;

    $self->{color} = 0;
    if ($self->{want_color} && has_colors()) {
	my $rc = start_color();
	$self->{color} = ($rc == OK);
	if ($self->{color}) {
	    eval { use_default_colors(); };
	}
    }

    noecho();
    raw();
    idlok(1);
    # How odd.  Jordan doesn't have idcok().
    eval { idcok(1); };
    typeahead(-1);
    keypad(1);

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

    my $tcount = scalar(keys %{$self->{win}});

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

    foreach my $tpair (values %{$self->{win}}) {
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
    return unless defined($key);
    #print STDERR "key='$key'\n";

    if ($self->{intercept} && $self->{command}->{$self->{intercept}}) {
	my $rc = $self->command($self->{intercept}, $key);
	warn "Intercept function returned \"$rc\"\n" if ($rc && $rc != 1);
	return if ($rc);
    }

    my $cmd = $self->{bindings}->{$key};
    if ($cmd && $self->{command}->{$cmd}) {
	$self->command($cmd, $key);
    } elsif (length($key) == 1) {
	$self->{input}->addchar($key);
    }

    $self->{input}->position_cursor;
    doupdate;
}


sub configure {
    my $self = shift;

    if (@_ == 0) {
	return (color          => $self->{color},
		input_maxlines => $self->{input_maxlines});
    }

    while (@_) {
	my $opt = shift;
	my $val = shift;

	if ($opt eq 'color') {
	    return unless (has_colors());
	    print STDERR "val=$val\n";
	    $self->{color} = $val ? 1 : 0;
	    $self->{input}->configure(color => $val);
	    foreach my $tpair (values %{$self->{win}}) {
		$tpair->{text}->configure(color => $val);
		$tpair->{status}->configure(color => $val);
	    }
	    $self->redraw();
	}

	elsif ($opt eq 'input_maxlines') {
	    # Handle this.
	}

	else {
	    croak "Unknown UI option: $opt";
	}
    }
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
    TLily::UI::Curses::Generic::defstyle($style, @attrs);
}


sub defcstyle {
    my($self, $style, $fg, $bg, @attrs) = @_;
    TLily::UI::Curses::Generic::defcstyle($style, $fg, $bg, @attrs);
}


sub clearstyle {
    my($self) = @_;
    TLily::UI::Curses::Generic::clearstyle();
}


sub style {
    my($self, $style) = @_;
    $self->{text}->style($style);
}


sub indent {
    my $self = shift;
    $self->SUPER::indent(@_);
    $self->{text}->indent(@_);
}


sub print {
    my $self = shift;
    $self->SUPER::print(@_);
    $self->{text}->print(join('', @_));
    $self->{input}->position_cursor();
    doupdate();
};


sub redraw {
    my($self) = @_;

    foreach my $tpair (values %{$self->{win}}) {
	$tpair->{text}->redraw();
	$tpair->{status}->redraw();
    }
    $self->{input}->redraw();
    $self->{input}->position_cursor();
    doupdate();
    return 1;
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


sub intercept_r {
    my($self, $name) = @_;
    return if (defined($self->{intercept}) && $self->{intercept} ne $name);
    $self->{intercept} = $name;
    return 1;
}


sub intercept_u {
    my($self, $name) = @_;
    return unless (defined($self->{intercept}));
    return if ($name ne $self->{intercept});
    $self->{intercept} = undef;
    return 1;
}


sub command {
    my($self, $command, $key) = @_;
    my $rc = eval { $self->{command}->{$command}->($self, $command, $key); };
    warn "Command \"$command\" caused error: $@" if ($@);
    $self->{input}->position_cursor();
    doupdate;
    return $rc;
}


sub prompt {
    my($self, $prompt) = @_;
    $self->{input}->prefix($prompt);
    $self->{input}->position_cursor();
    doupdate;
}


sub page {
    my $self = shift;
    $self->{text}->page(@_);
}


sub define {
    my($self, $name, $pos) = @_;
    $self->{status}->define($name, $pos);
    $self->{input}->position_cursor();
    doupdate;
}


sub set {
    my($self, $name, $val) = @_;
    $self->{status}->set($name, $val);
    $self->{input}->position_cursor();
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


sub istyle_fn_r {
    my($self, $style_fn) = @_;
    return if ($self->{input}->style_fn());
    $self->{input}->style_fn($style_fn);
    return $style_fn;
}


sub istyle_fn_u {
    my($self, $style_fn) = @_;
    if ($style_fn) {
	my $cur = $self->{input}->style_fn();
	return unless ($cur && $cur == $style_fn);
    }
    $self->{input}->style_fn(undef);
    return 1;
}


sub bell {
    my($self) = @_;
    beep();
}

1;
