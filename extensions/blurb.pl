# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/blurb.pl,v 1.2 2000/11/22 14:53:30 coke Exp $

use strict;

# Author: Will "Coke" Coleda

command_r('blurb', \&blurb_cmd);
shelp_r('blurb', "Format your blurb so it fits.");
help_r( 'blurb',"%blurb <blurb> will try to wedge your blurb into the available space
if it won't fit. There is, by default, a 35 character limit on the length
of your psuedo + the length of your blurb. (Toss in another 3 for the ' []',
and the total of 38 is what's allowed to satisfy those lame old telnet
clients. 

The extension will use a variety of techniques to try to cut your blurb
down to size, and failing those, will lop off the end of your blurb.");

sub unload {
## Nothing to do here right now.
}


my $max = 35;
my $psuedo;

sub check_blurb {
        if (length($psuedo) + length($_[0]) <=$max) {
		return 1;
	}
	return 0;
}

sub blurb_cmd {
	my ($ui,$blurb) = @_;
	$psuedo = active_server()->user_name(); #psuedo can change..
	my $modified = 0;

	## strip off exterior braces/quotes.

	if ($blurb =~ /^"(.*)"$/) {
		$blurb = $1;
	} elsif ($blurb =~ /^[(.*)]$/) {
		$blurb = $1;
	}

        goto DONE if (check_blurb($blurb));

	$modified = 1;

	#Trim any left/right spaces...

	$blurb =~ s/^(\s*)//;
	$blurb =~ s/(\s*)$//;

        goto DONE if (check_blurb($blurb));

	#Reduce any multiple spaces to singletons.

	$blurb =~ s/(\s+)/ /g;

        goto DONE if (check_blurb($blurb));

	#Remove ALL spaces...

	1 while ($blurb =~ s/ (.)/uc $1/e);

        goto DONE if (check_blurb($blurb));

	FAIL:

	$blurb = substr($blurb,0,($max-length($psuedo)));

	#$ui->print("(your compressed blurb is is " . abs($max - length($psuedo) - length($blurb)) . " chars too long)\n");
	#return;
	
   	DONE:
	TLily::Server->active()->cmd_process("/blurb [" . $blurb . "]", sub {
		# I don't see how to get the output of the cmd back...
	});
}



#TRUE! They return TRUE!
1;
