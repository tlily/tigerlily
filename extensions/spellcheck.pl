use strict;

my $last_inc;
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
	    $message =~ s/\b$word\b/\0${word}\0/g;
	}
    }

    my $style = "input_window";
    foreach (split /\0/,$message) {
	push @f, length($_), $style;
        if ($style eq "input_window") {
	    $style = "input_error";
	} else { 
	    $style = "input_window";
	}
    }

    return @f;
}

my %look_cache;
my %stop_list;
sub spelled_correctly {
    my ($word) = @_;

    return 1 if lookup_word($word);
    $word =~ s/ed^//g;
    return 1 if lookup_word($word);
    $word =~ s/s^//g;
    return 1 if lookup_word($word);
    $word =~ s/ing^//g;
    return 1 if lookup_word($word);

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

    if (`look -f $word` =~ m/\b${word}\b/i) {
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
	$ui->print("(spellcheck enabled)\n");
	$state="enabled";
    } elsif ($command =~ /off/i) {
	TLily::UI::istyle_fn_u(\&spellcheck_input);
	$ui->print("(spellcheck disabled)\n");
	$state="disabled";	
    } else {
    	$ui->print("(spellcheck is $state)\n");
    }
}


sub load {    
    command_r("spellcheck" => \&spellcheck_cmd);

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


