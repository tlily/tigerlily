use strict;

my $dict;

sub spellcheck_input {
    my($text) = @_;

    my ($dest,$sep,$message) = ($text =~ /^([^\s;:]*)([;:])(.*)/);

    my @f;
    if ($text =~ /[;:]/) {
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
my %stop_list;
sub spelled_correctly {
    my ($word) = @_;

    return 1 if lookup_word($word);

    # try stripping some obvious suffixes
    $word =~ s/(?:s|ed|ing|\'s)$//g;
    return 1 if $1 && lookup_word($word);

    $word =~ s/([^ey]e)st$/$1/g;
    return 1 if $1 && lookup_word($word);

    $word =~ s/([^ey])er$/$1/g;
    return 1 if $1 && lookup_word($word);

    $word =~ s/([^ey])ed$/$1/g;
    return 1 if $1 && lookup_word($word);

    $word =~ s/([^e])ing$/$1/g;
    return 1 if $1 && lookup_word($word);
    
    # now try adding some things.
    # prefixes
    foreach (qw(re in un)) {
	return 1 if lookup_word("$_${word}");
    }
    
    # ispell also checks a bunch of suffixes.  They mostly have special rules 
    # though, so I don't implement them properly here.   We will support ispell
    # directly, and it will do a better job.  
    # here, we just make some guesses which may lead to false positives..

    return 1 if lookup_word("${word}s");
    return 1 if ($word =~ /e$/         && lookup_word("${word}d"));
    return 1 if ($word =~ /e$/         && lookup_word("${word}rs"));
    return 1 if ($word =~ /e$/         && lookup_word("${word}r"));
    return 1 if ($word =~ /[^ey]$/     && lookup_word("${word}ers"));
    return 1 if ($word =~ /[^ey]$/     && lookup_word("${word}er"));
    return 1 if ($word =~ /[^e]$/      && lookup_word("${word}ings"));
    return 1 if ($word =~ /[^e]$/      && lookup_word("${word}ing"));
    return 1 if ($word =~ /[^aeiou]y$/ && lookup_word("${word}ed"));
    return 1 if ($word =~ /[^ey]$/     && lookup_word("${word}ed"));
    return 1 if ($word =~ /[^aeiou]y$/ && lookup_word("${word}est"));
    return 1 if ($word =~ /[^ey]$/     && lookup_word("${word}est"));
    return 1 if ($word =~ /e$/         && lookup_word("${word}st"));
    
    return 0;
}

sub lookup_word {
    my ($word) = @_;
    $word = lc($word);

    $word =~ s/[^A-Za-z]//g;
    return 1 if ($word !~ /\S/);    
    if (scalar(keys %look_cache) > 500) { undef %look_cache; }
     
    return 1 if $stop_list{$word};   

    if (exists $look_cache{$word}) {
	return $look_cache{$word};
    }

    my $lookout;
    if ($dict) {
	look($dict, $word, 1, 1);
	$lookout = <$dict>;	
    } else {
	$lookout = `look -f $word`;
    }

    if ($lookout =~ m/\b${word}\b/i) {
       $look_cache{$word}=1;
    } else {
       $look_cache{$word}=0;	
    }

    return $look_cache{$word};
}

my $state;
sub spellcheck_cmd {
    my($ui, $command) = @_;

    if ($command =~ /on/i) {
	TLily::UI::istyle_fn_r(\&spellcheck_input);
	my $dictfile;
	if (%Search::Dict::) {       
            my @words = qw(/usr/dict/words /usr/share/dict/words);
	    unshift @words, $config{words} if ($config{words});
	    foreach (@words) {
		if ( -f $_ ) { $dictfile = $_; last; }
	    }

            local *DICT;
	    my $rc = open(DICT, "< $dictfile");
            $dict = $rc ? *DICT{IO} : undef;
	}
	if ($dict) {
	    $ui->print("(spellcheck enabled, using Search::Dict on $dictfile)\n");
	} else {
	    $ui->print("(spellcheck enabled, using \`look\`)\n");
	}
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

sub unload { undef $dict; }
sub load {    
    eval { use Search::Dict; };

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

NOTE: This extension requires that the \"look\" program be installed and
      functional on your system.

");


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
