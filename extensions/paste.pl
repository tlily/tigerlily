# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/paste.pl,v 1.3 1999/04/21 20:09:58 neild Exp $

use strict;

sub paste_mode {
    my($ui, $command, $key) = @_;
    return 1 if ($ui->{_paste_nl_flag} && ($key eq "nl" || $key eq " "));
    if ($key eq "nl") {
	$ui->{_paste_nl_flag} = 1;
	$ui->command("insert-self", " ");
	return 1;
    }
    $ui->{_paste_nl_flag} = 0;
    return;
}

sub toggle_paste_mode {
    my($ui, $command) = @_;
    $ui->{_paste_nl_flag} = 0;
    if ($ui->intercept_u("paste-mode")) {
	$ui->prompt("");
    }
    elsif ($ui->intercept_r("paste-mode")) {
	$ui->prompt("Paste:");
    }
}

my $paste_help = "
Sometimes you want to paste several lines of text into a send.  Pasting
each line one at a time is tedious, and prone to error.  (What happens
if you accidentally paste a newline?)  Paste mode provides a better way.

When paste mode is enabled (it can be toggled with the toggle-paste-mode
key, bound to M-p by default), newlines are translated into spaces.  To
help with occasions when several lines of text are indented, any spaces
following a newline are not entered.
";

TLily::UI::command_r("paste-mode"        => \&paste_mode);
TLily::UI::command_r("toggle-paste-mode" => \&toggle_paste_mode);
TLily::UI::bind("M-p" => "toggle-paste-mode");
TLily::User::shelp_r("paste" => "Pasting multi-line text.", "concepts");
TLily::User::help_r("paste" => $paste_help);
