use strict;

my $last_inc;
sub spellcheck_input {
    my($ui, $command, $key) = @_;

    my ($point, $text) = $ui->get_input();

    my ($dest,$sep,$message) = ($text =~ /^([^\s;:]*)([;:])(.*)/);

    $last_inc = 0 if (length($message) <= 1);

    # strip off any partial words at the end.
    $message =~ s/\w+\s*$//g;

    my $m = $message;
    my $word;
    my $inc;
    foreach $word (split /\W+/, $m) {
	if (!spelled_correctly($word)) {
	    $inc++;
	    $message =~ s/\b$word\b/_${word}_/g;
	}
    }

    $last_inc = 0 if ($inc == 0);
    $ui->print("($message)\n") if ($inc != $last_inc);

    $last_inc = $inc;
    
    return;
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

}

sub lookup_word {
    my ($word) = @_;

    $word =~ s/[^A-Za-z]//g;
    return 1 if ($word !~ /\S/);    
    if (scalar(keys %look_cache) > 500) { undef %look_cache; }
    
    return 1 if $stop_list{$word};   

    if (exists $look_cache{$word}) {
	return $look_cache{$word};
    }
    my $ui = ui_name();
    if (`look -f $word` =~ m/\b${word}\b/i) {
       $look_cache{$word}=1;
    } else {
       $look_cache{$word}=0;	
    }

    return $look_cache{$word};
}

sub spellcheck_cmd {
    my($ui, $command) = @_;

    if ($command =~ /on/i) {
	$ui->intercept_r("spellcheck-input");
	$ui->print("(spellcheck enabled)\n");
    } else {
	$ui->intercept_u("spellcheck-input");
	$ui->print("(spellcheck disabled)\n");
    }
}


sub load {    
    TLily::UI::command_r("spellcheck-input"        => \&spellcheck_input);
    command_r("spellcheck" => \&spellcheck_cmd);

    foreach (qw(I a about an and are as at by for from in is of on or
		the to with)) {
	$stop_list{$_}=1;
    }
}



# This is just an example..  shrugga.

# Data Structure for input line:
# @input = (['a','normal'], ...);
my @input = ();
sub insert_char {
    my ($position,$newchar);

    my ($rstyle,$lstyle,$lchar,$rchar);

    if ($position < 0 || $position > $#input) {
	$rstyle = "normal"; 
	$rchar  = " ";
    } else {
	$rstyle = $input[$position][1];
	$rchar  = $input[$position][0];
    }

