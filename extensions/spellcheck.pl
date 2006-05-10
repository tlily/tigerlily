# -*- Perl -*-
# $Id$

use strict;
use IPC::Open2;

=head1 NAME

spellcheck.pl - Spellchecking extension

=head1 DESCRIPTION

Provides a spellcheck command, and a spellcheck mode in which misspelled
words in the input buffer are highlighted.

=head1 COMMANDS

=over 10

=item %spellcheck

Turns spellcheck mode on or off.  See "%help %spellcheck".

=head1 UI COMMANDS

=item look

Spellchecks the word underneath the cursor.  Bound to ^G by default.

=cut

my $state = "disabled";
my %stop_list;

sub spellcheck_input {
    my($text) = @_;

    my ($dest,$sep,$message) = ($text =~ /^([^\s;:]*)([;:])(.*)/);

    my @f;
    if ($sep ne "") {
	push @f, length("$dest$sep"), "input_window";
    } else {
	push @f, length($text), "input_window";
	return @f;
    }

    # strip off any partial words at the end, unless there's a space there.
    if ($message =~ /[^\s\.\?\!]$/) {
	$message =~ s/\S+\s*$//g;
    }

    my $m = $message;

    # strip out contractions (perl doesn't break them right)
    # just assume that they're spelled ok.
    $m =~ s/\S+\'\S+//g;

    my $word;
    foreach $word (split /\W/, $m) {
	if (!spelled_correctly($word)) {
	    $message =~ s/\0$word\0/$word/g;
	    $message =~ s/\b$word\b/\0${word}\0/g;
	}
    }

    # take the \0 markers around the misspelled words and generate the style
    # list
    while ($message =~ /\0[^\0]*\0/) {
	my ($norm,$err)= ($message =~ /^([^\0]*)\0([^\0]*)\0/);
	$message =~ s/^([^\0]*)\0([^\0]*)\0//;
	if (length($norm)) {
	    push @f, length($norm), "input_window";
        }
	push @f, length($err), "input_error";
    }
    push @f, length($message), "input_window" if length($message);

    return @f;
}


my %look_cache;
my $last_ispell_restart = 0;
sub spelled_correctly {
    my ($word) = @_;

    $word = lc($word);
    $word =~ s/[^A-Za-z]//g;

    return 1 if ($state ne "enabled");

    return 1 if ($word !~ /\S/);

    return 1 if (exists($stop_list{$word}));

    # clear the cache if it's grown too big.
    if (scalar(keys %look_cache) > 500) { undef %look_cache; }

    return $look_cache{$word} if (exists $look_cache{$word});

    # Talk to ispell
    print I_WRITE "^$word\n" or do {
        my $ui = TLily::UI::name();

        if (time - $last_ispell_restart < 60) {
            $ui->print("(ispell has died again.  giving up and disabling spellcheck)\n");
            $state="disabled";

            TLily::UI::istyle_fn_u(\&spellcheck_input);
            return 1;

        }

        $last_ispell_restart = time;

        $ui->print("(ispell seems to have died- restarting)");
        init_ispell();

        return;
    };
	
    my $resp  = <I_READ>;
    while (defined(my $blank = <I_READ>)) {
        last if $blank =~ /^$/;
    }
	
    if ($resp =~ /^[*+-]/) {
        $look_cache{$word}=1;
    } else {
        $look_cache{$word}=0;
    }

    return $look_cache{$word};
}

sub spellcheck_cmd {
    my($ui, $command) = @_;

    if ($command =~ /on/i && $state ne "enabled") {
	if (! init_ispell()) {
            $ui->print("('ispell' not available, spellcheck disabled)\n");
            $state="disabled";
            return;
        }

        TLily::UI::istyle_fn_r(\&spellcheck_input);

        $ui->print("(spellcheck enabled, using \'ispell\')\n");
        $state="enabled";

    } elsif ($command =~ /off/i) {
	TLily::UI::istyle_fn_u(\&spellcheck_input);
	$ui->print("(spellcheck disabled)\n");
	$state="disabled";
    } else {
	$state ||= "disabled";
    	$ui->print("(spellcheck is $state)\n");
    }
}

sub init_ispell {
    close I_WRITE;
    close I_READ;
    my $pid = open2(\*I_READ, \*I_WRITE, 'ispell', '-a') or return undef;
    my $banner = <I_READ>;
    $banner =~ /^\@/ or return 0; # "Couldn't sync with ispell"

    return $pid;
}

sub load {
    command_r("spellcheck" => \&spellcheck_cmd);

    TLily::UI::command_r("look" => \&look_cmd);
    TLily::UI::bind('C-g' => "look");

    foreach (qw(i a about an and are as at by for from in is of on or
		the to with ok foo bar baz perl tlily)) {
	$stop_list{$_}=1;
    }
    shelp_r("spellcheck" => "Enable or disable the spell checker");
    help_r("spellcheck" => "
Usage: %spellcheck [on|off]

Enables or disables highlighting of potentially misspelled words on the \
input line.

Once the spellchecker is enabled, words will be highlighted in red if they
might be misspelled.

NOTE: This feature requires that the \"ispell\" program be installed and
      functional on your system.

");
    shelp_r("look" => "Spellcheck the current word", "ui_commands");


}

sub look_cmd {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    my $ui_cols = 79;

    # First get the portion of the line from the beginning to the
    # character just before the cursor.
    $a = substr($line, 0, $pos);
    # Just keep the alphabetic characters at the end (if any).
    $a =~ s/.*?([A-Za-z]*)$/$1/;

    # The rest of the line, from the cursor to the end.
    $b = substr($line, $pos);
    # Just keep the alphabetic characters at the beginning (if any).
    $b =~ s/[^A-Za-z].*//;

    my $word = $a . $b;
    return if ($word eq '');

    my @res = `look $word`;
    chomp(@res);

    if (@res == 0) {
	$ui->print("(\"$word\" not found in dictionary)\n");
    } elsif (@res == 1 || grep m/^$word$/i, @res) {
	$ui->print("(\"$word\" is spelled correctly)\n");
    } else {
	$ui->print("(The following possible words were found:)\n");

        foreach (@{columnize_list($ui, \@res, 5)}) { $ui->print($_, "\n"); }
    }

    return;
}
