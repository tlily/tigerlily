#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/UI/Attic/TextWindow.pm,v 1.8 2003/11/06 20:45:52 bwelling Exp $

package TLily::UI::TextWindow::Proxy;

use strict;
use vars qw($AUTOLOAD @ISA $a $b); #) cperl mode is getting confused.
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
    TLily::FoiledAgain::update_screen();
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


package TLily::UI::TextWindow;

use strict;
use vars qw(@ISA %commandmap %bindmap);

use Carp;

use TLily::UI;
use TLily::UI::TextWindow::Text;
use TLily::UI::TextWindow::StatusLine;
use TLily::UI::TextWindow::Input;
use TLily::Event;
use TLily::Config qw(%config);
use TLily::FoiledAgain;

@ISA = qw(TLily::UI); #) cperl mode is getting confused


sub accept_line {
    my($ui) = @_;
    my $text = $ui->{input}->accept_line();
    foreach my $tpair (values %{$ui->{win}}) {
        $tpair->{text}->seen();
    }

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

sub mark_output {
    my ($ui) = @_;

    my $clock = $ui->{status}->{var}->{clock} || "";

    my $center = (TLily::FoiledAgain::screen_width() - length($clock)) / 2;

    $ui->style("mark_output");
    $ui->print(' ' x $center . $clock . ' ' x $center . "\n");
    $ui->style("normal");
}

sub switch_window {
    my ($ui, $dir) = @_;

    my $tcount = scalar(keys %{$ui->{win}});
    return if ($tcount == 1);

    my (@keys, $pos, $active);
    @keys = sort(keys %{$ui->{win}});
    for (my $i = 0; $i < @keys; $i++) {
        my $tpair = $ui->{win}->{$keys[$i]};
	next if ($tpair->{text} != $ui->{text});
	if ($dir == 1) {
            $pos = ($i + 1) % @keys;
        } else {
            $pos = ($i + @keys - 1) % @keys;
        }
        last;
    }
    $active = $ui->{win}->{$keys[$pos]}->{text};
    $ui->{text}->{status}->make_active(0);
    $ui->{text} = $active;
    $ui->{text}->{status}->make_active(1);
}

sub split_window {
    my ($ui) = @_;

    my $tcount = scalar(keys %{$ui->{win}});

    # Don't allow more windows to be created than will fit.
    my $imax = $ui->{input_imax} || 2;
    return if ($imax + 2 * ($tcount + 1) > TLily::FoiledAgain::screen_height());

    $ui->{text}->{status}->make_active(1) if ($tcount == 1);

    $ui->clear_statusbar();

    my $name = sprintf("sub%05d", $ui->{winid}++);
    my $newui = TLily::UI::TextWindow->new(name => "$name");

    $ui->populate_statusbar();
}

sub close_window {
    my ($ui) = @_;

    my @keys = sort(keys %{$ui->{win}});
    return unless (@keys > 1);
    foreach my $key (@keys) {
        next if ($ui->{win}->{$key}->{text} != $ui->{text});
        $ui->switch_window(1);
        delete $ui->{win}->{$key};
	last;
    }
    my @keys = sort(keys %{$ui->{win}});
    $ui->{text}->{status}->make_active(0) if (@keys == 1);
    $ui->{status} = $ui->{win}->{@keys[@keys - 1]}->{status};
    $ui->populate_statusbar();
    $ui->layout();
}

# The default set of mappings from command names to functions.
%commandmap =
  (
   'accept-line'          => \&accept_line,
   'mark-output'          => \&mark_output,
   'previous-history'     => sub { $_[0]->{input}->previous_history(); },
   'next-history'         => sub { $_[0]->{input}->next_history(); },
   'intelligent-previous' => sub { $_[0]->{input}->intelligent_previous(); },
   'intelligent-next'     => sub { $_[0]->{input}->intelligent_next(); },
   'insert-self'          => sub { $_[0]->{input}->addchar($_[2]) },
   'forward-char'         => sub { $_[0]->{input}->forward_char(); },
   'backward-char'        => sub { $_[0]->{input}->backward_char(); },
   'forward-word'         => sub { $_[0]->{input}->forward_word(); },
   'backward-word'        => sub { $_[0]->{input}->backward_word(); },
   'beginning-of-line'    => sub { $_[0]->{input}->beginning_of_line(); },
   'end-of-line'          => sub { $_[0]->{input}->end_of_line(); },
   'forward-sentence'     => sub { $_[0]->{input}->forward_sentence(); },
   'backward-sentence'    => sub { $_[0]->{input}->backward_sentence(); },
   'delete-char'          => sub { $_[0]->{input}->del(); },
   'backward-delete-char' => sub { $_[0]->{input}->bs(); },
   'capitalize-word'      => sub { $_[0]->{input}->capitalize_word(); },
   'down-case-word'       => sub { $_[0]->{input}->down_case_word(); },
   'up-case-word'         => sub { $_[0]->{input}->up_case_word(); },
   'transpose-chars'      => sub { $_[0]->{input}->transpose_chars(); },
   'transpose-words'      => sub { $_[0]->{input}->transpose_words(); },
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
   'refresh'              => sub { $_[0]->force_redraw(); },
   'suspend'              => sub { TLily::Event::keepalive(); kill 'TSTP', $$; },
   'quoted-insert'        => sub { $_[0]->{input}->{quoted_insert} = 1 },
   'prev-window'          => sub { $_[0]->switch_window(-1); },
   'next-window'          => sub { $_[0]->switch_window(1); },
   'split-window'         => sub { $_[0]->split_window(); },
   'close-window'         => sub { $_[0]->close_window(); }
  );

# The default set of keybindings.
%bindmap =
  (
   'C-?'        => 'backward-delete-char',
   'C-a'        => 'beginning-of-line',
   'C-b'        => 'backward-char',
 # 'C-c'        is interrupt, TLily.PL
   'C-d'        => 'delete-char',
   'C-e'        => 'end-of-line',
   'C-f'        => 'forward-char',
 # 'C-g'        is look, extensions/spellcheck.pl
   'C-h'        => 'backward-delete-char',
 # 'C-i'        is complete-send, extensions/expand.pl
 # 'C-j'        is accept-line ('nl', below)
   'C-k'        => 'kill-line',
   'C-l'        => 'refresh',
   'C-m'        => 'accept-line',
   'C-n'        => 'next-history',
 # 'C-o'        is UNBOUND
   'C-p'        => 'previous-history',
   'C-q'        => 'quoted-insert',
 # 'C-r'        is 'isearch-backward', extensions/ui.pl
 # 'C-s'        is 'isearch-forward', extensions/ui.pl
   'C-t'        => 'transpose-chars',
   'C-u'        => 'backward-kill-line',
   'C-v'        => 'page-down',
   'C-w'        => 'backward-kill-word',
 # 'C-x'        is 'next-input-contex', extensions/ui.pl
   'C-y'        => 'yank',
   'C-z'        => 'suspend',
   'C-M-?'      => 'backward-kill-word',
   'M-,'        => 'line-up',
   'M-.'        => 'line-down',
   'M-<'        => 'scroll-to-top',
   'M->'        => 'scroll-to-bottom',
   'M-a'        => 'backward-sentence',
   'M-b'        => 'backward-word',
   'M-bs'       => 'backward-kill-word',
   'M-c'        => 'capitalize-word',
   'M-d'        => 'kill-word',
   'M-e'        => 'forward-sentence',
   'M-f'        => 'forward-word',
 # 'M-g'        is UNBOUND
 # 'M-h'        is UNBOUND
 # 'M-i'        is UNBOUND
 # 'M-j'        is UNBOUND
 # 'M-k'        is 'kill-sentence', extensions/ui.pl
   'M-l'        => 'down-case-word',
 # 'M-l'        is _also_ 'toggle-leet-mode', extensions/leet.pl
   'M-m'        => 'mark-output',
 # 'M-n'        is UNBOUND
 # 'M-o'        is UNBOUND
 # 'M-p'        is 'toggle-paste-mode', extensions/paste.pl
 # 'M-q'        is UNBOUND
 # 'M-r'        is UNBOUND
 # 'M-s'        is UNBOUND
   'M-t'        => 'transpose-words',
   'M-u'        => 'up-case-word',
   'M-v'        => 'page-up',
 # 'M-w'        is UNBOUND
 # 'M-x'        is UNBOUND
 # 'M-y'        is UNBOUND
 # 'M-z'        is 'zap-to-char', extensions/ui.pl
   'bs'         => 'backward-delete-char',
   'del'        => 'backward-delete-char',
   'down'       => 'next-history',
   'left'       => 'backward-char',
   'nl'         => 'accept-line',
   'pagedown'   => 'page-down',
   'pageup'     => 'page-up',
   'right'      => 'forward-char',
   'up'         => 'previous-history',
 # Many M-<punctuation> and all M-<digit> are also currently unbound,
 # but M-<digit> will probably become a prefix argument a la Emacs.
  );


my $base_curses;
sub new {
    my $proto = shift;
    my %arg   = @_;

    return $base_curses->splitwin($arg{name}) if ($base_curses);

    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    bless($self, $class);

    TLily::FoiledAgain::set_ui($config{'textwindow_ui'});
    TLily::FoiledAgain::want_color((defined($arg{color}) ? $arg{color} : 1));

    $self->{input_maxlines} = $arg{input_maxlines};
    start_curses($self);

    $self->{status} = TLily::UI::TextWindow::StatusLine->new
      (layout  => $self,
       color   => $self->{color});
    $self->{win}->{$arg{name}}->{status} = $self->{status};

    $self->{text} = TLily::UI::TextWindow::Text->new
      (layout  => $self,
       color   => $self->{color},
       status  => $self->{status});
    $self->{win}->{$arg{name}}->{text} = $self->{text};

    $self->{winid} = 0;

    # These are used to keep a record of entries added to the main status
    # bar, so they can be reapplied when new windows are created.
    $self->{statuspositions} = [];
    $self->{statusvalues} = {};

    $self->{input} = TLily::UI::TextWindow::Input->new
      (layout  => $self,
       color   => $self->{color});

    $self->{input}->active();

    $self->{command}   = { %commandmap };
    $self->{bindings}  = { %bindmap };

    $self->{intercept} = [];

    $self->{prompt}    = [];

    $self->layout();

    # xxx this should be moved into foiledagain land.
    if ($^O eq 'MSWin32') {
        # select() doesn't work on stdin with Win32::Console, apparently, so 
        # we poll for input during idle times instead.  Responsiveness 
        # can be tuned vs. CPU utilization in the idle timeout part of
        # Event.pm.
        TLily::Event::idle_r(call => sub { $self->run; });
    } else {
        TLily::Event::io_r(handle => \*STDIN,
                           mode   => 'r',
		           call   => sub { $self->run; });
    }

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
	$self->{win}->{$name}->{status} = TLily::UI::TextWindow::StatusLine->new
	  ( layout => $self, color => $self->{color} );

	$self->{win}->{$name}->{text} = TLily::UI::TextWindow::Text->new
	  ( layout => $self, color => $self->{color},
	    status => $self->{win}->{$name}->{status},
	    clone => $self->{text});

        $self->{status} = $self->{win}->{$name}->{status};
	$self->layout();
    }

    return TLily::UI::TextWindow::Proxy->new($self, $name);
}


sub start_curses {
    my($self) = @_;

    TLily::FoiledAgain::start();
}


sub stop_curses {
    my($self) = @_;

    TLily::FoiledAgain::stop();
}


sub DESTROY {
    my($self) = @_;
    $self->stop_curses();
}


# Re-layout the widgets.
sub layout {
    my($self) = @_;

    my $COLS  = TLily::FoiledAgain::screen_width();
    my $LINES = TLily::FoiledAgain::screen_height();

    my $tcount = scalar(keys %{$self->{win}});

    # Calculate the max height the input line is allowed to grow to.
    my $imax = $self->{input_imax} || ($LINES - (2 * $tcount));
    $imax = 1 if ($imax <= 0);

    # Find out how large the input line wants to be.
    my($ilines, $icols) = $self->{input}->req_size();
    $ilines = 1 if (!$ilines);
    $ilines = $imax if ($ilines > $imax);

    my $tlines = int(($LINES - $ilines) / $tcount);
    my $trem   = ($LINES - $ilines) % $tcount;
    my $y      = 0;

    foreach my $key (sort(keys %{$self->{win}})) {
        my $tpair = $self->{win}->{$key};
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

    TLily::FoiledAgain::sanity_poll();
    $self->layout();
    $self->force_redraw();

    my $key = $self->{input}->read_char();
    return unless defined($key);
    #print STDERR "key='$key'\n";

    # Note: the extra level of copy through an anonymous array is needed
    # in case one of the intercept handlers does its own intercept_u
    # intercept_r and thus changes $self->{intercept}.
    foreach my $i (@{[ @{$self->{intercept}}]}) {
        if ($self->{command}->{$i->{name}}) {
            my $rc = $self->command($i->{name}, $key);
            warn qq(Intercept $i->{name} returned "$rc"\n) if $rc && $rc != 1;
            return if $rc;
        }
    }

    my $cmd = $self->{bindings}->{$key};
    if ($cmd && $self->{command}->{$cmd}) {
	$self->command($cmd, $key);
    } elsif (length($key) == 1) {
	$self->{input}->addchar($key);
        $self->{input}->{quoted_insert} = 0;
        $self->command("scroll-to-bottom")
            if $config{scroll_to_bottom_on_input} &&
               $self->{status}->{var}->{t_more};
    }

    $self->{input}->position_cursor;
    TLily::FoiledAgain::update_screen();
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

    TLily::FoiledAgain::suspend();
}


sub resume {
    my($self) = @_;

    TLily::FoiledAgain::resume();
}


sub defstyle {
    my($self, $style, @attrs) = @_;
    TLily::UI::TextWindow::Generic::defstyle($style, @attrs);
}


sub defcstyle {
    my($self, $style, $fg, $bg, @attrs) = @_;
    TLily::UI::TextWindow::Generic::defcstyle($style, $fg, $bg, @attrs);
}


sub clearstyle {
    my($self) = @_;
    TLily::UI::TextWindow::Generic::clearstyle();
}


sub style {
    my($self, $style) = @_;
    foreach my $tpair (values %{$self->{win}}) {
        $tpair->{text}->style($style);
    }
}


sub indent {
    my $self = shift;
    $self->SUPER::indent(@_);
    foreach my $tpair (values %{$self->{win}}) {
        $tpair->{text}->indent(@_);
    }
}


sub print {
    my $self = shift;
    return if $config{quiet};
    $self->SUPER::print(@_);
    foreach my $tpair (values %{$self->{win}}) {
	$tpair->{text}->print(join('', @_));
    }
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
};


sub force_redraw {
    my ($self) = @_;

#    $self->{input}->{F}->{W}->clearok(1);  # XXX foiledagain
    $self->redraw();
}

sub redraw {
    my($self) = @_;

    foreach my $tpair (values %{$self->{win}}) {
	$tpair->{text}->redraw();
	$tpair->{status}->redraw();
    }
    $self->{input}->redraw();
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
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

    if (defined($key) && defined($command)) {
        $self->{bindings}->{$key} = $command;
    } elsif (! defined($key)) {
        # XXXDCL could use specialized sorting algorithm.
        foreach my $key (sort keys %{$self->{bindings}}) {
            $self->print(sprintf("%-16s%s\n", $key,
                                 $self->{bindings}->{$key}));
        }
    } elsif ($self->{bindings}->{$key}) {
        $self->print("$key is bound to $self->{bindings}->{$key}\n");
    } elsif (length($key) == 1) {
        $self->print("$key is bound to insert-self\n");
    } else {
        $self->print("$key is not bound\n");
    }

    return 1;
}

sub intercept_r {
    my $self = shift;
    my $i = (@_ == 1) ? shift : {@_};

    unless (defined($i->{name}) && defined($i->{order})) {
        # This is not meant to be a deeply meaningful message to the end
        # user, just a clue to the programmer that they don't quite
        # have their intercept_r right yet.
        $self->print("bad intercept handler registration\n");
        return 0;
    }

    $self->{intercept} = [ sort { $a->{order} <=> $b->{order} }
                           @{$self->{intercept}}, $i ];

    return 1;
}


sub intercept_u {
    my($self, $name) = @_;
    my $new = [];
    foreach my $i (@{$self->{intercept}}) {
        push(@{$new}, $i) unless $i->{name} eq $name;
    }
    if (@{$new} == @{$self->{intercept}}) {
        # No handler was found, but this is normal because various callers
        # do this to facilitate toggling state.  Silently return.
        return 0;
    } elsif (@{$new} != @{$self->{intercept}} - 1) {
        # Programmer warning; not really for end users.
        $self->print("intercept_u $name found multiple registrations\n");
    }

    $self->{intercept} = [ @{$new} ];

    return 1;
}


sub command {
    my($self, $command, $key) = @_;
    my $rc = eval { $self->{command}->{$command}->($self, $command, $key); };
    warn "Command \"$command\" caused error: $@" if ($@);
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
    return $rc;
}


sub prompt {
    my($self, $prompt) = @_;
    $self->{input}->prefix($prompt);
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
}


sub page {
    my $self = shift;
    foreach my $tpair (values %{$self->{win}}) {
      $tpair->{text}->page(@_);
    }
}


sub define {
    my($self, $name, $pos) = @_;
    $self->{status}->define($name, $pos);
    push (@{$self->{statuspositions}}, {name => $name, pos =>$pos});
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
}


sub set {
    my($self, $name, $val) = @_;
    $self->{status}->set($name, $val);
    $self->{statusvalues}->{$name} = $val;
    $self->{input}->position_cursor();
    TLily::FoiledAgain::update_screen();
}


sub get_input {
    my($self) = @_;
    return $self->{input}->get();
}


sub set_input {
    my $self = shift;
    $self->{input}->set(@_);

    $self->{input}->{F}->update_screen();
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

    TLily::FoiledAgain::bell();
}

sub dump_to_file {
    my $self = shift;
    $self->{text}->dump_to_file(@_);
}

sub populate_statusbar {
    my($self) = @_;
    foreach my $var (@{$self->{statuspositions}}) {
        $self->{status}->define($var->{name}, $var->{pos});
    }
    foreach my $key (keys(%{$self->{statusvalues}})) {
        $self->{status}->set($key, $self->{statusvalues}->{$key});
    }
}

sub clear_statusbar {
    my($self) = @_;
    foreach my $var (@{$self->{statuspositions}}) {
        $self->{status}->define($var->{name}, 'nowhere');
    }
}

1;
