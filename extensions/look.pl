# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/Attic/look.pl,v 1.2 1999/03/02 19:51:57 neild Exp $
#
# "look" tlily extension
#

sub spellcheck {
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

    $word = $a . $b;
    return if ($word eq '');

    @res = `look $word`;
    chomp(@res);

    if (@res == 0) {
	$ui->print("(\"$word\" not found in dictionary)\n");
    } elsif (@res == 1) {
	$ui->print("(\"$word\" is spelled correctly)\n");
    } else {
	$ui->print("(The following possible words were found:)\n");

	my $clen = 0;
	foreach (@res) { $clen = length $_ if (length $_ > $clen); }
	$clen += 2;

	my $cols = int($ui_cols / $clen);
	my $rows = int(@res / $cols);
	$rows++ if (@res % $cols);

	$rows = 5 if ($rows > 5);

	my $i;
	for ($i = 0; $i < $rows; $i++) {
	    $ui->print(sprintf("%-${clen}s" x $cols,
			      map{$res[$i+$rows*$_]} 0..$cols));
	    $ui->print("\n");
	}

	if (@res > $rows * $cols) {
	    $ui->print("(" . (@res - ($rows * $cols)) . " more entries follow)\n");
	}
    }

    return;
}

TLily::UI::command_r("spellcheck" => \&spellcheck);
TLily::UI::bind('C-g' => "spellcheck");
