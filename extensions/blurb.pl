# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/blurb.pl,v 1.9 2000/12/14 16:30:21 coke Exp $

use strict;

# Author: Will "Coke" Coleda (will@coleda.com)

#
# It's possible that multiple compressions will render readability undef.
# Ping me if you think this is happening.
#

shelp_r("blurb_all" => "(boolean) update blurb on ALL cores or just local", "variables");
command_r('blurb', \&blurb_cmd);
shelp_r('blurb', "Format your blurb so it fits.");
help_r( 'blurb',"%blurb <blurb> will try to wedge your blurb into the available space
if it won't fit. There is, by default, a 35 character limit on the length
of your psuedo + the length of your blurb. (Toss in another 3 for the ' []',
and the total of 38 is what's allowed to satisfy those lame old telnet
clients.) 

The extension will use a variety of techniques to try to cut your blurb
down to size, and failing those, will lop off the end of your blurb.

The multi-core version of %blurb calculates things based on your current
psuedo. This might cause problems if you use psuedos of various lengths on
different cores.
");

$config{"blurb_all"} = 0 if !exists($config{"blurb_all"});

#
# Abbrs: a hash of regexen and their abbreviations.
#

my %abbr = (
	qr/fou?r/i => "4",
	qr/ate|eight/i => "8",
	qr/\b(too?|two)/i => "2",
	qr/and/i => "&",
);

#my %abbr_must = (
	#qr/fuck/i => "f***",
	#qr/shit/i => "sh*t",
#);

sub unload {
	## Nothing to do here right now.
}


my $max = 35;
my $psuedo;

#
# Is this blurb ok?
#
sub check_blurb {
        if (length($psuedo) + length($_[0]) <=$max) {
		return 1;
	}
	return 0;
}

#
# Apply a set of rules to reduce your blurb into something that will 
# fit into a smaller space. Apply this rules in order of readability.
#

sub blurb_cmd {
	my ($ui,$blurb) = @_;
	$psuedo = active_server()->user_name(); #psuedo can change..
	my $modified = 0;
	my @words;
	my $failed=1;

	if ($blurb eq "off") {
		my @servers=();
		if ($config{blurb_all}) {
			@servers = TLily::Server::find();
		} else {
			$servers[0] = TLily::Server->active();
		}
	
		foreach my $core (@servers) {	
			next if !defined $core;
			$core->cmd_process("/blurb off", sub {
				# I don't see how to get the output of the cmd back...
			});
		};
		return;
	}

	#Handle any -required- substitutions. (swear filter)

	#foreach my $re (keys %abbr_must) {
		#$blurb =~s /$re/$abbr_must{$re}/g;
	#}

	## strip off exterior braces/quotes.

	if ($blurb =~ /^"(.*)"$/) {
		$blurb = $1;
	} elsif ($blurb =~ /^\[(.*)\]$/) {
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

	#Handle any abbreviations;

	foreach my $re (keys %abbr) {
		while ($blurb =~s /$re/$abbr{$re}/) {
        		goto DONE if (check_blurb($blurb));
		}
	}

	#Remove all spaces.. convert to a list in the process,
        #since we need to keep track of words from this point out.

	@words = map {ucfirst $_} (split(' ',$blurb));
	$blurb = join('',@words);
        goto DONE if (check_blurb($blurb));

	#Remove punctuation

	if (0) {
	while (grep /\W/, @words) { #if -any- puncutation
		foreach my $word (@words) { # remove from each word in turn.
			if ($word =~ s/\W//) {
				$blurb=join('',@words);
				#$ui->print("TEST:" .$blurb. "\n");
        			goto DONE if (check_blurb($blurb));
			}
		}
	}
	}
	#Remove some vowels?

	my $vowelRE = qr/([^AEIOUaeiou])[aeiou]([^AEIOUaeiou])/;

	while (grep /$vowelRE/, @words) { #if -any- cases,
		foreach my $word (@words) { # remove from each word in turn.
			if ($word =~ s/$vowelRE/$1$2/) {
				$blurb=join('',@words);
				#$ui->print("TEST:" .$blurb. "\n");
        			goto DONE if (check_blurb($blurb));
			}
		}
	}

	FAIL:
	#$ui->print("FAIL\n");
	$failed=1;
	$blurb = substr(join('',@words),0,($max-length($psuedo)));
	#$ui->print("(your compressed blurb is is " . abs($max - length($psuedo) - length($blurb)) . " chars too long)\n");
	#return;
	
   	DONE:
	#$ui->print("K'PLA!\n");
	my @servers=();
	if ($config{blurb_all}) {
		@servers = TLily::Server::find();
	} else {
		$servers[0] = TLily::Server->active();
	}

	foreach my $core (@servers) {	
		next if !defined $core;
		$core->cmd_process("/blurb [" . $blurb . "]", sub {
			# I don't see how to get the output of the cmd back...
		});
	};
	#$ui->print("BLURB: " . $blurb . "\n");
}

#TRUE! They return TRUE!
1;
