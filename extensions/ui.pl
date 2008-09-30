# -*- Perl -*-
# $Id$
use strict;

=head1 NAME

ui.pl - User Interface functions

=head1 DESCRIPTION

This extension contains %commands for dealing with the user interface.

=head1 COMMANDS

=over 10

=cut
#
# Keybindings.
#

=item %bind

Binds a key to a command.  See "%help bind" for details.

=cut

my $bind_help = qq{
Usage: %bind ["locally"] [key [command]]

%bind binds a key to a command.  The actual set of commands you can bind \
a key to is unfortunately poorly specified at this time.  If the \"locally\" \
argument is specified (or a substring thereof), the binding will apply only \
to the current UI; otherwise, it will be a global binding. \

If the command argument is not specified, the binding of the key in the \
current UI will be printed.

If the key argument is not specified, all bindings in the current UI \
will be printed, except for keys which do "insert-self".

(The 1 and 2 argument versions of %bind are currently only available with \
the Curses UI.)

(see also %keyname)
};

my $keyname_help = "
Usage: %keyname

Prints the name (suitable for use in %bind) of the next key pressed.

(see also %bind)
";

sub bind_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;
    my $local;

    if ($args[0] && index("locally", $args[0]) == 0 && length($args[0]) > 1) {
	shift @args;
	$local = 1;
    }

    if (@args < 2) {
        $local = 1;
    } elsif (@args > 2) {
	$ui->print("(%bind [locally] key command; type %help for help)\n");
	return;
    }

    $ui->print("(binding \"$args[0]\" to \"$args[1]\")\n") if @args > 1;
    if ($local) {
	$ui->bind(@args);
    } else {
	TLily::UI::bind(@args);
    }

    return;
}
command_r('bind' => \&bind_command);
shelp_r('bind' => "Bind a key to a command.");
help_r('bind' => $bind_help);


=item %key

Echos the key symbol of the next key pressed.  See "%help key" for details.

=cut

sub name_self {
    my($ui, $command, $key) = @_;
    $ui->intercept_u($command);
    $ui->print("(you pressed \"$key\")\n");
    return 1;
}
TLily::UI::command_r("name-self" => \&name_self);


sub keyname_command {
    my($ui, $args) = @_;

    if ($args) {
	$ui->print("(%keyname; type %help for help)\n");
	return;
    }

    if (!$ui->intercept_r(name => "name-self", order => 100)) {
        $ui->style("input_error");
	$ui->print("(sorry; a keyboard intercept is already in place)\n");
        $ui->style("normal");
	return;
    }

    $ui->print("Press any key.\n");
    return;
}
command_r(keyname => \&keyname_command);
shelp_r(keyname => "Print the name of the next key pressed.");
help_r(keyname => $keyname_help);


#
# Windows.
#

sub ui_command {
    my($ui, $args) = @_;
    my($cmd, @args) = split /\s+/, $args;

    #my $newui = TLily::UI::Curses->new(name => 'sub');
    #$newui->print("foo\n");
}
#command_r(ui => \&ui_command);

my $windows_help = "
Sometimes you want to split the screen and view different parts of your
scrollback in each one.  This can be done with the split-window (M-= by
default) command.  To cycle between windows, use the next-window (M-down)
and prev-window (M-up) commands.  To close a window, use the close-window
(M-q) command.

When multiple windows are open, the active window will be denoted by arrows
on the sides of the corresponding status bar.
";

TLily::UI::bind("M-down" => "next-window");
TLily::UI::bind("M-up" => "prev-window");
TLily::UI::bind("M-=" => "split-window");
TLily::UI::bind("M-q" => "close-window");
shelp_r("windows" => "Dealing with multiple windows.", "concepts");
help_r("windows" => $windows_help);
shelp_r("next-window" => "Cycle to next window (see %help windows)", "ui_commands");
shelp_r("prev-window" => "Cycle to previous window (see %help windows)", "ui_commands");
shelp_r("split-window" => "Split a window in two (see %help windows)", "ui_commands");
shelp_r("close-window" => "Close current window (see %help windows)", "ui_commands");


=item %page

Enables and disables output paging.  See "%help page" for details.

=cut

#
# Paging.
#

my $page_help = "
Usage: %page [on | off]

%page enables and disables output paging.
";

sub page_command {
    my($ui, $args) = @_;

    if ($args eq "") {
	if ($ui->page()) {
		$ui->print("(paging is currently enabled)\n");
	} else {
		$ui->print("(paging is currently disabled)\n");
	}
    } elsif ($args eq "on") {
	$config{page} = 1;
	$ui->page(1);
	$ui->print("(paging is now enabled)\n");
    } elsif ($args eq "off") {
	$config{page} = 0;
	$ui->page(0);
	$ui->print("(paging is now disabled)\n");
    } else {
	$ui->print("(%page on|off; type %help for help)\n");
    }

    return;
}
command_r(page => \&page_command);
shelp_r(page => "Turn output paging on and off.");
help_r(page => $page_help);

=item Input Contexts

Input cut buffers.  See "%help icontext" for details.

=cut

#
# Input contexts.
#

my $icontext_help = qq{
Have you ever typed in half of a very long send, when suddenly you want to \
make a quick send to someone else, or check if a person is on line?  Input \
contexts are designed to save the contents of the input buffer and return \
to it later.  If you press the next-input-context key (bound to C-x by \
default), your current input state is saved, and a new one opened.  Press \
the key again to move to the next input context.

An example may make this easier to understand.  Type "foo", and press C-x. \
The input line clears.  Press C-x again, and "foo" returns.  You can have \
more than one saved input context: Press C-x.  (The input line clears.)  \
Type "bar", and press C-x again.  The input line clears, as you move to a \
third input context.  Press C-x again, and you return to the first context
("foo").

(see also: %bind)
};

sub next_input_context {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    $ui->{input}->{_context} ||= [];
    my $context = $ui->{input}->{_context};

    my $cidx = $ui->{input}->{_context_idx} || 0;

    if (length $line) {
	$context->[$cidx] = [$pos, $line];
	$cidx++;
	$context->[$cidx] ||= [0, ""];
    }
    else {
	splice(@$context, $cidx, 1);
	$cidx = 0 if ($cidx >= @$context);
    }

    $ui->set_input(@{$context->[$cidx]});
    $ui->{input}->{_context_idx} = $cidx;
}
TLily::UI::command_r("next-input-context" => \&next_input_context);
TLily::UI::bind("C-x" => "next-input-context");
shelp_r("icontext" => "Input contexts let you defer sends until later.",
        "concepts");
help_r("icontext" => $icontext_help);
shelp_r("next-input-context" => "Cycle to next input context (see %help icontext)", "ui_commands");

#
# Input history searching
#

=item Input History Searching

Allows you to search your input buffer for a string, as in bash.
See "%help isearch" for details.

=cut

# XXXDCL should allow input context searching, at least the current
# input context.

my $isearch_help = qq{
You can search your input buffer history (but not input contexts) for \
a string.  After switching into search mode via isearch-backward or \
isearch-forward (C-r and C-s, respectively), each additional key will \
build a search string, and search backwards in your history buffer for that \
string.  If a character is typed that would cause the string not to be found, \
it is ignored, and tlily will beep.

Typing C-r when already searching backward, or C-s when already searching \
forward, will look for the next occurrence of the current search string. \
Typing C-r while searching forward or C-s while searching backward will \
change the direction of the search.  Typing C-r or C-s while there is no \
search string will search for the string used by the last isearch.

Typing C-g will restore your input buffer to its state prior to the start \
of the search.  C-l (or any key bound to "refresh") will redraw the screen.

Any other special characters will terminate search mode.

The configuration variable case_fold_search, if non-zero, will cause \
uppercase and lowercase letters to be matched equally.  Case folded \
searching is enabled by default.
};

sub input_search_mode {
    my($ui, $command, $key) = @_;

    # ASSERT().
    die "key is null in input_search_mode at "
        unless defined($key) && $key ne "";

    die "direction $ui->{_search_dir} is unknown at "
        unless $ui->{_search_dir} =~ /^(fwd|rev)$/;

    my $next_match;
    if ($ui->{bindings}->{$key} eq "isearch-backward") {
        if ($ui->{_search_dir} eq 'rev') {
            $next_match = 1;
        } else {
            $ui->{_search_dir} = 'rev';
        }
        $key = "";

    } elsif ($ui->{bindings}->{$key} eq "isearch-forward") {
        if ($ui->{_search_dir} eq 'fwd') {
            $next_match = 1;
        } else {
            $ui->{_search_dir} = 'fwd';
        }
        $key = "";
    }

    # If key is "", then it was originally C-r or C-s.
    # Thus if the search is not being extended to the next match, it
    # must be switching directions.  Also, if the C-r or C-s comes
    # while the search string is empty, set the search string to the last
    # searched string.
    my $switch_dir = 0;
    if ($key eq "") {
        $switch_dir = ! $next_match;
        $ui->{_search_text} = $ui->{_search_last}
            if $ui->{_search_text} eq "" && $next_match;
    }

    my $input = $ui->{input};
    my $dir = $ui->{_search_dir} eq 'fwd' ? 1 : -1;

    if (length($key) <= 1) {
        my $match = $input->search_history(string => $ui->{_search_text}.$key,
                                           dir => $dir,
                                           switch_dir => $switch_dir,
                                           next_match => $next_match);
        unless (length($match) > 0) {
            $ui->bell();
        } else {
            $ui->{_search_text} .= $key;
            $ui->prompt("($ui->{_search_dir}-i-search)'$ui->{_search_text}':");
        }
        return 1;

    } else {
        if ($ui->{bindings}->{$key} eq 'backward-delete-char') {
            return 1 if $ui->{_search_text} eq "";

            chop($ui->{_search_text});

            # If string is empty, go back to the save_excursion point,
            # and reset the search position so the next character typed will
            # start searching from where the original search started.
            if ($ui->{_search_text} eq "") {
                ($input->{text}, $input->{point}) = @{$ui->{save_excursion}};
                $input->search_history(reset => 1);
                $ui->prompt("($ui->{_search_dir}-i-search):");

            } else {
                # Find the first match for the shortened string, starting from
                # where the original search started.
                $input->search_history(string => $ui->{_search_text},
                                       reset => 1,
                                       dir => $dir);
                $ui->prompt("($ui->{_search_dir}-i-search)" .
                            "'$ui->{_search_text}':");
            }

            return 1;

        } elsif ($ui->{bindings}->{$key} eq 'refresh') {
            $ui->command("refresh");
            return 1;
        }

        # All other special keys terminate the search (regardless of whether
        # they are really bound to a command).
        search_stop($ui);

        # C-g terminates the search and restores the state from when
        # the search started.  Returns 1 so the key is not processed
        # when the function is returned.  There is currently no keyboard-quit
        # function, but there should be, and the existing C-g ("look") should
        # be remapped to M-g or something else.  When keyboard-quit exists,
        # paste-mode should probably use it too. XXDCL
        if ($key eq 'C-g') {
            ($input->{text}, $input->{point}) = @{$ui->{save_excursion}};
            $ui->bell();

            $input->update_style();
            $input->rationalize();
            $input->redraw();

            return 1;

        } else {
            # Set the history position to the entry where the search stopped.
            $input->{history_pos} = $input->{_search_pos};

            # Save the search text for next time.
            $ui->{_search_last} = $ui->{_search_text};
        }
    }
    return;
}

sub search_start {
    my ($ui, $dir) = @_;
    my $input = $ui->{input};

    unless ($ui->intercept_r(name => "input-search-mode", order => 100)) {
        # XXXDCL Perhaps there should be a different way to communicate this.
        # Or maybe still do the print, but with a different style.
        $ui->style("input_error");
        $ui->print("(can't start a search in current mode)\n");
        $ui->style("normal");
        return;
    }

    $ui->{_search_text} = "";
    $ui->{_search_last} = "" unless defined $ui->{_search_last};
    $ui->{_search_dir} = $dir;
    $ui->{save_excursion} = [$input->{text}, $input->{point}];
    $ui->{save_prefix} = $input->{prefix};

    $input->search_history(reset => 1);
    $input->{_search_anchor} = $input->{point};

    # Make the current input searchable by temporarily sticking it
    # into the history buffer.
    $input->save_history_excursion;

    $ui->prompt("($dir-i-search):");
}

sub search_stop {
    my ($ui) = @_;

    $ui->intercept_u("input-search-mode");
    $ui->prompt($ui->{save_prefix});
}

sub isearch_forward {
    my ($ui) = @_;

    search_start($ui, "fwd");
}

sub isearch_backward {
    my ($ui) = @_;

    search_start($ui, "rev");
}

TLily::UI::command_r("isearch-forward" => \&isearch_forward);
TLily::UI::command_r("isearch-backward" => \&isearch_backward);
TLily::UI::command_r("input-search-mode" => \&input_search_mode);
TLily::UI::bind("C-r" => "isearch-backward");
TLily::UI::bind("C-s" => "isearch-forward");
shelp_r("isearch" => "Search your input buffer for a string.", "concepts");
help_r("isearch" => $isearch_help);
shelp_r("isearch-forward" => "Search input buffer (see %help isearch)",
        "ui_commands");
shelp_r("isearch-backward" => "Search input buffer (see %help isearch)",
        "ui_commands");

#
# Input editing.
#
my $zap_help = qq(
zap-to-char will delete the input buffer up through the next character typed.
It is normally bound to M-z.  For example, if you had this pending buffer:
	Tale:You're ugly, and your mother dresses you funny.
Then typed C-a M-z and a comma, the resulting buffer would be:
        and your mother dresses you funny.
);

sub
zap_to_char {
    my ($ui, $command, $key) = @_;
    my $input = $ui->{input};

    if ($ui->intercept_u("zap-to-char")) {
        # Was already in zap-to-char mode, so do it with the key.
        my $found;

        $found = index($input->{text}, $key, $input->{point})
          if length($key) == 1;

        if ($found >= 0) {
            $input->kill_append($input->{point}, $found - $input->{point} + 1);
        } else {
            $ui->bell();
        }

        $ui->prompt($ui->{save_prefix});
    } else {
        if ($ui->intercept_r(name => "zap-to-char", order => 500)) {
            $ui->{save_prefix} = $input->{prefix};
            $ui->prompt("(zap-to-char):");
        } else {
            $ui->style("input_error");
            $ui->print("(sorry; a keyboard intercept is already in place)\n");
            $ui->style("normal");
        }
    }

    $input->update_style();
    $input->rationalize();
    $input->redraw();

    return 1;
}

TLily::UI::command_r("zap-to-char" => \&zap_to_char);
TLily::UI::bind("M-z" => "zap-to-char");
shelp_r("zap-to-char" => "Kill input through next char. (%help zap-to-char)",
        "ui_commands");
help_r("zap-to-char" => $zap_help);

sub
kill_sentence {
    my $ui = shift;
    my $input = $ui->{input};
    my $end = $input->end_of_sentence();

    $input->kill_append($input->{point}, $end - $input->{point});

    $input->update_style();
    $input->rationalize();
    $input->redraw();
}

TLily::UI::command_r("kill-sentence" => \&kill_sentence);
TLily::UI::bind("M-k" => "kill-sentence");
shelp_r("kill-sentence" => "Kill the remainder of the sentence.",
        "ui_commands");

#
# Styles.
#

=item %style

Allows you to redefine the attributes used to render text in monochrome
mode.
See "%help style" for details.

=cut

my $style_help = "
Usage: %style style attr ...
       %cstyle style fg bg attr ...

%style and %cstyle set the attributes to print a style in monochrome and \
color modes, respectively.

Valid attribute values are:
  normal, standout, underline, reverse, blink, dim, bold, altcharset

Valid color values are:
  black, red, green, yellow, blue, magenta, cyan, white

The actual rendering of these attributes and colors is very much up to the
specific UI in use.

(see also: styles)
";

sub style_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 2) {
	$ui->print("(%style style attr ...; type %help for help)\n");
	return;
    }

    my $style = shift @args;
    $config{mono_attrs}->{$style} = \@args;
    $ui->defstyle($style, @args);
    $ui->redraw();
    return;
}
command_r(style => \&style_command);
shelp_r(style => "Set the attributes of a text style.");
help_r(style => $style_help);

=item %cstyle

Allows you to redefine the colors and attributes used to render text
in color mode.
See "%help cstyle" for details.

=cut


sub cstyle_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 4) {
	$ui->print("(%cstyle style fg bg attr ...; type %help for help)\n");
	return;
    }

    my $style = shift @args;
    $config{color_attrs}->{$style} = \@args;
    $ui->defcstyle($style, @args);
    $ui->redraw();
    return;
}
command_r(cstyle => \&cstyle_command);
shelp_r(cstyle => "Set the color and attributes of a text style.");
help_r(cstyle => $style_help);

TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'color_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if(! $config{mono}) {
				  $ui->defcstyle(${$ev{Key}}, @{${$ev{Value}}});
 			          $ui->redraw();
			      }
		          });

my $styles_help = "
The currently available styles are:
status_window   The status line at the bottom of the screen.
input_window    The input line you are typing
input_error     Words not found by the spellchecker in your input line
text_window     The default characteristics of the window (background, etc.)
public_header   The text in the header of a public message
public_sender   The name of the sender of a public message
public_dest     The names of the recipients of a public message
public_body     The actual message of a public message
public_server   The name of the server a public message came from [1]
private_header  The text in the header of a private message
private_sender  The name of the sender of a private message
private_dest    The names of the recipients of a private message
private_body    The actual message of a private message
private_server  The name of the server a private message came from [1]
emote_body      The message text of an emote message
emote_dest      The names of the recipients of an emote message
emote_sender    The name of the sender of an emote message
emote_server    The name of the server an emote message came from [1]
review          (Currently unused)
slcp            SLCP status messages, indicating a user state change
user_input      User input lines shown in the output window.
mark_output     Line printed by the mark-output (default key: M-m) command
yellow          Used for the tlily logo
green           Used for the tlily logo
bwhite          Used for the tlily logo
normal          /info text, /memo text, non-SLCP server messages
default         Used for any style that is not explicitly set.

[1] Note that the *_server styles are only used when tlily is connected to
multiple servers at once.
";
shelp_r("styles" => "The various display styles.", "concepts");
help_r("styles" => $styles_help);


TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'mono_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if($config{mono}) {
				  $ui->defstyle(${$ev{Key}}, @{${$ev{Value}}});
  			          $ui->redraw();
			      }
		          });


TLily::Config::callback_r(Variable => 'mono',
			  List => 'config',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();
			      $ui->configure(color => !$ {$ev{Value}});
			      return;
		          });


sub load {
    # Set colors from what the config files read
    my($k,$v);
    my $ui = ui_name();
    while (($k,$v) = each %{$config{'mono_attrs'}}) {
	$ui->defstyle($k, @{$v});
    }

    while (($k,$v) = each %{$config{'color_attrs'}}) {
	$ui->defcstyle($k, @{$v});
    }
    $ui->redraw;
}

