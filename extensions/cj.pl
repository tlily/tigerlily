# -*- Perl -*-
# $Id$

use strict;
use CGI qw/escape unescape/;

# TODO:

# o Add in all previous CJ functionality.
# o Add in all acceptable requested functionality
# o need a way to modify chatty/quiet on a per discussion basis.
# o fix "STOP" processing so that it makes sense. (Currently it concats.)

# AUTHOR:

# Will "Coke" Coleda

# PURPOSE:

# this extension allows a login to act like a bot. It is designed to run
# as a standalone user, although modifications could be made to make
# it function as a cyborg.

# it provides several types of information:
# Unicast: Given user input, provide a response.
# Broadcast: Broadcast info as available.
# Multicast: Given user/moderator preferences, send selective info.

# Users (and Discussion moderators) may request broadcast information
# of any of the available types. The extension will record these preferences
# in a permanent location, so that state may be preserved if the user running
# the extension must logout (or reload the extension)

# HISTORY:

# CJ was a bot. He did a lot of things that some folks found useful,
# and did a lot of things that some folks thought was waaaaay too chatty.
# He began as a lily-server based magic 8-ball, was ported to a bot using
# tlily version 1. This brings CJ up to tlily version 2 as a fresh
# implementation. I was going to use Josh's Bot.pm to handle a good chunk 
# of the guts for me, but Bot.pm didn't really seem to meet my needs.
# This rewrite is intended as an exercize to (a) improve stability, (b) 
# improve maintainability, (c) prepare for a similar capability for Flow.
# Perhaps someone could remove most of the functionality here and make
# a ComplexBot module

#########################################################################
my %response; #Container for all response handlers. 
my %throttle; #Container for all throttling information. 
my $throttle_interval = 1; #seconds
my $throttle_safety   = 5; #seconds
my %prefs; #dbmopen'd hash of lily user prefs.
my $disc="cj-admin"; #where we keep our memos.

# some array refs of sayings...
my $sayings;   # pithy 8ball-isms.
my $overhear;  # listen for my name occasionally;
my $buzzwords; # random set of words.
my $unified;   # special handling for the unified discussion.

# we don't expect to be changing our name frequently, cache it.
my $name = active_server()->user_name();

# we'll use Eliza to handle any commands we don't understand, so set her up.
use Chatbot::Eliza;
my $eliza = new Chatbot::Eliza {name=>$name,prompts_on=>0};

use TLily::Server::HTTP;

### If someone is an admin, perform a task.
sub asAdmin {

#
# BUG: This still notifies the client running the code of the output.
#      It should (a) have notifies turned off, and (b) be sent back
#      to the originator of the command.
#
	my ($event,$sub) = @_;

  TLily::Server->active()->cmd_process("/what cj-admin", sub {
		my ($newevent) = @_;

		my $oldevent=$event;

		$newevent->{NOTIFY}=0;
		return if ($newevent->{type} eq "endcmd");
		return if ($newevent->{type} eq "begincmd");
		if ($newevent->{text} =~ s/^Permitted: //g) {
			if (grep(/^$oldevent->{SOURCE}$/,split(/, /,$newevent->{text}))) {
				$sub->();	
			}
		}
	});
}


### pick an element of a ref-list at random.
sub random { 
	my @list = @{$_[0]};
	return $list[int(rand(scalar(@list)))];
}

### Process stock requests

### XXX - for some reason, get_stock only works ONCE when loading cj.
###       subsequent loads show only a fraction of the appropriate HTML
###       are arriving!!!
### Reloading THIS EXTENSION fixes the problem. reloading http_parse 
### does NOT!!

my $wrapline = 76; # This is where we wrap lines...
sub get_stock {

	my ($event, @stock) = @_;
	my $url = 'http://finance.yahoo.com/q?s=' . join('+',@stock) . '&d=v1';
	dispatch($event,$url);
	TLily::Server::HTTP-> new(url => $url,
	                          ui_name => 'main',
                                  callback => sub { 
		my ($response) = @_;
		dispatch($event,length($response->{_content}) . " bytes");
		#foreach my $foo (split(/\n/, $response->{_content})) {
			#dispatch($event,$foo);
		#}
		my @chunks = ($response->{_content} =~ /^<td nowrap align=left>.*/mg);

		dispatch($event,scalar(@chunks). " chunks found");

		my (@retval, $cnt);
		$response->{_content} =~ s/\n/ /g;
		foreach (@chunks) {
			my ($time,$value,$frac,$perc,$volume) = (split(/<\/td>/,$_,))[1..5];

			if (/No such ticker symbol/) {
				push @retval, "$stock[$cnt]: Oops. No such ticker symbol. Try stock lookup .";
			} else {
				push @retval, "$stock[$cnt]: Last $time, $value: Change $frac ($perc): Vol $volume";
			}
			$cnt++;
		}


		my $retval;
		foreach my $tmp (@retval) {
			$tmp = cleanHTML($tmp);
			$tmp =~ s:(\d) / (\d):$1/$2:g;
			$tmp =~ s:\( :(:g;
			$tmp =~ s: \):):g;
			$tmp =~ s: ,:,:g;
			
			my $pad = " " x ($wrapline - ((length $tmp) % $wrapline)) ;
			$retval .= $tmp . $pad;
		}
		$retval =~ s/\s*$//;
		dispatch($event,$retval);
	});
}

#
# Setup Response configuration.
#
# Response handlers are hashrefs with the following fields:
#   <all CODE are passed the event as args>
#   <all HELP are passed the args, split, if any>
#   CODE=<coderef>, HELP=<coderef>,
#   TYPE=listof<private|public|emote>, POS=<-1|0|1>
#   STOP=<boolean> (do I stop processing the send at this point?)
#   RE {how do I match this command?} 
# There is no magical "default" handler. you must define one below if you 
#  desire. The default behavior is silence, because that's how Priz would
#  have wanted it.

$response{help} = {
	CODE   => sub { 
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*help\s*(.*)\s*$/$1/i)) {
			return "ERROR: Expected RE not matched!";
		}
		if ($args eq "") {		
			return "Hello. I'm a bot. I don't do much right now. Try 'help' followed by one of the following for more information: " . join (", ", sort grep {! /^help/} keys %response) . ". In general, commands can appear anywhere in private sends, but must begin public sends.";
		}
		my @help = split(/\s+/, $args);
		my $topic = shift @help;	
		if (exists ${response}{$topic}) {
			return &{$response{$topic}{HELP}}(@help);
		}
		return "ERROR: \'$args\' , unknown help topic.";
	},
	HELP   => sub { return "You're kidding, right?";},
	TYPE   => [qw/private/],
	POS    => '-1', 
	STOP   => 1,
	RE      => qr/\bhelp\b/i,
};

$response{"unset"} = {
	CODE   => sub {
	  my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/\bunset\s+(.*)$/$1/)) {
			return "ERROR: Expected RE not matched!";
		};

		my $handle = $event->{SHANDLE};
		my $key = $handle . "-" . $args;

		if (exists $prefs{$key}) {
			delete $prefs{$key};
			return "$args is now unset";
		} else {
			return "ERROR: invalid variable: $args";
		}
	},
	HELP   => sub { return "Purpose: provide a way to undo \"set\""; },
	TYPE   => [qw/private/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr(\bunset\b),
};

$response{"poll"} = {
	CODE   => sub {
	  my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/\bpoll\s?(.*)\s*$/$1/)) {
			return "ERROR: Expected RE not matched!";
		};
		$args =~ s/^\s+//;
		$args =~ s/\s+$//;
    my @args = split(/\s+/,$args,2);

		my $handle = $event->{SHANDLE};

		# This should be configable.
		my %polls = ( "pres"  => "2000 Presidential Campaign",
		              "ny"    => "2000 NYS Senate Campaign",
		              "spice" => "Your Favourite Spice Girl");

		if (scalar @args == 0) {
			my @tmp;
			foreach my $key (keys %polls) {
				push @tmp, $key . ", \'" . $polls{$key}. "\'";
			}
			return "The currently available polls are: " . join ("; ", @tmp);
		} elsif (scalar @args == 1) {
			if (exists $polls{$args[0]}) {
				# Get the current tally:
					my %results;
					foreach my $key (grep({/-\-*poll-/},(keys %prefs))) {
						$results{lc $prefs{$key}}++ if $key =~ /$args[0]$/;	
					}
				my $key = $handle  . "-*poll-" . $args[0];
				
				my $personal =  "You have not voted in this poll.";
				if (exists $prefs{$key}) {
					$personal = "You voted for '" . $prefs{$key} ."'";
				}
				return "Results: " . join (", ", map {$_ . ": " . $results{$_} . " vote" . (($results{$_}==1)?"":"s")} (keys %results)) . ". " . $personal;
			} else {
				return $args[0] . " is not an active poll";
			}
		} elsif (scalar @args == 2) {
			if (exists $polls{$args[0]}) {
				$prefs{$handle  . "-*poll-" . $args[0]} = $args[1];
				return "Your ballot has been cast.";
			} else {
				return $args[0] . " is not an active poll";
			}
		} else {
			return "ERROR: Expected RE not matched!";
		}
	},
	HELP   => sub { return "Similar to /vote. By itself, list current polls. given a poll name, return the current results. You can also specify a value to cast your ballot. Usage: poll [<poll> [<vote>]]";},
	TYPE   => [qw/private/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr(\bpoll\b),
};

$response{"set"} = {
	CODE   => sub {
	  my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/\bset(.*)$/$1/)) {
			return "ERROR: Expected RE not matched!";
		};
    my @args = split(' ',$args,2);

		my $handle = $event->{SHANDLE};

		if (scalar @args == 0) {
			my @tmp;
			if ($handle eq "#127") {
				foreach my $key (sort keys %prefs) {
				$key =~ /^(#\d+)-(.*)/;
				my ($user, $var) = ($1, $2);
				my $nick = TLily::Server->active()->get_name(HANDLE=>$user);
				push @tmp, "\$\{" . $nick ."\}\{$2\}=\'".$prefs{$key} . "\'";
				}
			} else {
			foreach my $key (grep {/^${handle}-/} (sort keys (%prefs))) {
				(my $var = $key) =~ s/^${handle}-//;
				push @tmp, "\$" . $var ."=\'".$prefs{$key} . "\'";
			} }
			return join (", ", @tmp);
		} elsif (scalar @args == 1) {
			return $prefs{$handle . "-" . $args[0]};
		} elsif (scalar @args == 2) {
			if ($args[0] =~ m:^\*:) {
				return "You may not modify " . $args[0] . " directly.";
			}
			$prefs{$handle . "-" . $args[0]} = $args[1];
			return "set \$" . $args[0] . "=\'" . $args[1] . "\'";
		} else {
			return "ERROR: Expected RE not matched!";
		}
	},
	HELP   => sub { return "Purpose: provide a generic mechanism for preference management. Usage: set [ <var> [ <value> ] ]. Only works in private. I should really limit what data can be set here."  },
	TYPE   => [qw/private/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr(\bset\b),
};

$response{"stomach pump"} = {
	CODE   => sub {
		return "Eeeek!";
	},
	HELP   => sub { return "stomach pump.";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/stomach pump/,
};

$response{grope} = {
	CODE   => sub { return "Me grope Good!"; },
	HELP   => sub { return "It's... groperific."; },
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 0,
	RE     => qr/\bgrope\b/,
};

$response{cmd} = {
	CODE   => sub {
		my ($event) = @_;
		(my $cmd = $event->{VALUE}) =~ s/.*\bcmd\b\s*(.*)/$1/;
		asAdmin($event,sub {
			my ($newevent) = @_;
			$newevent->{NOTIFY} = 0;
			my $server = TLily::Server->active();
			$server->cmd_process($cmd, sub {
				$_[0]->{NOTIFY} = 0;
			});
			dispatch($event,$newevent->{VALUE});
		});
	},
	HELP   => sub { return "If you are permitted to the admin discussion, you can use this command to boss me around.";},
	TYPE   => [qw/private/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\bcmd\b/,
};

$response{buzz} = {
	CODE   => sub {
		my ($event) = @_;
		my @tmp;
		foreach (1..3) {
	   push @tmp ,random($buzzwords);
		}
		return join (" ",@tmp) . "!";
	},
	HELP   => sub { return "random buzzword generator. Active with keyword \"buzz\"";},
	TYPE   => [qw/public emote/],
	POS    => '1', 
	STOP   => 1,
	RE     => qr/\bbuzz\b/,
};

$response{stock} = {
	CODE   => sub {
		my ($event) = @_;
		my $args=$event->{VALUE};
		if (! ($args =~ s/stock\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		} else {
			get_stock($event,split(/[, ]+/,$args));
			return "";
		}
	},
	HELP   => sub { return "Give a list of ticker symbols, I'll be your web proxy to finance.yahoo.com";},
	TYPE   => [qw/private/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\bstock\b/,
};

$response{kibo} = {
	CODE   => sub {
		my ($event) = @_;
		my $list = $sayings;
		if ($event->{RECIPS} eq "unified") {
			$list = $unified;
		}
		return sprintf(random($list),$event->{SOURCE});
	},
	HELP   => sub { return "I respond to public questions addressed to me.";},
	TYPE   => [qw/public emote/],
	POS    => '1', 
	STOP   => 1,
	RE     => qr/\b$name\b.*\?/,
};


$response{eliza} = {
	CODE   => sub {
		my ($event)= @_;
		return $eliza->transform($event->{VALUE});
	},
	HELP   => sub { return "I've been doing some research into psychotherapy, I'd be glad to help you work through your agression.";},
	TYPE   => ["private"],
	POS    => '1', 
	STOP   => 1,
	RE     => qr/.*/,
};

$response{foldoc} = {
	CODE   => sub {
		my ($event)= @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*foldoc\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};
		TLily::Server::HTTP-> new( url => 'http://www.nightflight.com/foldoc-bin/foldoc.cgi?query=' . $args , host => 'www.nightflight.com', ui_name => 'main', protocol=> 'http', callback => sub { 

			my ($response) = @_;

			my $tmp = cleanHTML((split("</FORM>",$response->{_content}))[0]);

			if ($tmp =~ /No match for/) {
				dispatch($event,"No match, sorry");
				return"";
			} else {
				#dispatch($event,"a match, sorry");
			}

			my @chunks = split("<HR>",$response->{_content});

			if (scalar(@chunks) == 3)  {
				my $tmp = cleanHTML((split("</FORM>",$chunks[0]))[1]);
				$tmp =~ s/Try this search on OneLook \/ Google//;
			
				dispatch($event,"According to FOLDOC: " . $tmp );
			} else {
				dispatch($event,"foldoc: Screen Scrape failed!");
			}
		});
		return;
	},
	HELP   => sub { return "Define things from the Free Online Dictionary of Computing";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/foldoc/,
};

$response{lynx} = {
	CODE   => sub {
		my ($event)= @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*lynx\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};
		TLily::Server::HTTP-> new( url => $args, host => 'www.cnn.com', ui_name => 'main', protocol=> 'http', callback => sub { 

			my ($response) = @_;
	    my $message;
			#$message = "keys: ". (join " ", (keys %$response));
			#$message = "status keys: ". (join " ", (keys %{$response->{_state}}));
			$message = "status: ". $response->{_state}{_msg};
			$message .= " url: ". $response->{url};
			$message .= " size: ". length( $response->{_content});
			#$response->{_content} =~ s/\s+/ /g;
			#$message = "content: ". $response->{_content};
			dispatch($event,$message);
		});
		return;
	},
	HELP   => sub { return "trying to find a nice way to suck down web pages.";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/lynx/,
};

my @ascii = qw/NUL SOH STX ETX EOT ENQ ACK BEL BS HT LF VT FF CR SO SI DLE DC1 DC2 DC3 DC4 NAK SYN ETB CAN EM SUB ESC FS GS RS US SPACE/;
my %ascii;

for my $cnt (0..$#ascii) {
  $ascii{$ascii[$cnt]} = $cnt;
}
$ascii{DEL} =0x7f;

sub format_ascii {
	my $val = @_[0];

	my $format = "%s => %d (dec); 0x%x (hex); 0%o (oct)";

	if ($val < 0 || $val > 255) {
		return "Ascii is 7 bit, silly!";
	}
	my $chr = "'" . chr($val) . "'";

	my $control="";
	if ($val >= 1 && $val <=26) {
		$control="; control-".chr($val+ord('A')-1);
	}

	if ($val < $#ascii) {
		$chr = $ascii[$val];
	}

	if ($val == 0x7f) {
		$chr = "DEL";
	}
	
	return sprintf($format,$chr,$val,$val,$val). $control;
}

$response{rot13} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*rot13\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};

		$args =~ tr/[A-Za-z]/[N-ZA-Mn-za-m]/;

		return $args;
	},
	HELP   => sub { return "Usage: rot13 <val>";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\brot13\b/i,
};

$response{urldecode} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*urldecode\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};

		return unescape $args;
	},
	HELP   => sub { return "Usage: urldecode <val>";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\burldecode\b/i,
};

$response{urlencode} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*urlencode\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};

		return escape $args;
	},
	HELP   => sub { return "Usage: urlencode <val>";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\burlencode\b/i,
};


$response{ascii} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*ascii\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};
		if ( $args =~ m/^'(.)'$/) {
			return format_ascii(ord($1));
		} elsif ($args =~ m/^0[Xx][0-9A-Fa-f]+$/) {
			return format_ascii(oct($args));
		} elsif ($args =~ m/^0[0-7]+$/) {
			return format_ascii(oct($args));
		} elsif ($args =~ m/^[1-9]\d*$/) {
			return format_ascii($args);
		} elsif ($args =~ m/^\\[Cc]([A-Z])$/) {
			return format_ascii(ord($1)-ord('A')+1);
		} elsif ($args =~ m/^\\[Cc]([a-z])$/) {
			return format_ascii(ord($1)-ord('a')+1);
		} elsif ($args =~ m/^[Cc]-([a-z])$/) {
			return format_ascii(ord($1)-ord('a')+1);
		} elsif ($args =~ m/^[Cc]-([A-Z])$/) {
			return format_ascii(ord($1)-ord('A')+1);
		} elsif (exists $ascii{uc $args}) {
			return format_ascii($ascii{uc $args});
		} else {
			return "Sorry, $args doesn't make any sense to me.";
		}
	},
	HELP   => sub { return "Usage: ascii <val>, where val can be a char ('a'), hex (0x1), octal (01), decimal (1) an emacs (C-A) or perl (\\cA) control sequence, or an ASCII control name (SOH).";},
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\bascii\b/i,
};

$response{country} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*country\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};
		if ( $args =~ m/^(..)$/) {
			
			my $a = `grep -i '\|$1\$' /home/wjc/research/CJ/countries.txt`;
			$a =~ m/^([^\|]*)/;
			return $1 unless ($1 eq "");
			return "No Match."
		} else {
			my @a = split(/\n/, `grep -i \'$args\' /home/wjc/research/CJ/countries.txt`);
			if (scalar(@a) > 10) {
				return "Your search found " . scalar(@a) . " characters. Be more specific.";
			} elsif (scalar(@a) > 0) {
				my $tmp = join ("\'; ", @a);
				$tmp =~ s/\|/=\'/g;
				return $tmp . "'";
			} else {
				return "Found no matches.";
			}
		}
	},
	HELP   => sub { return "Usage: country <val>, where val is either a 2 character country code, or a string to match against possible countries.";} ,
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\bcountry\b/i,
};
if(0) {
$response{utf8} = {
	CODE   => sub {
		my ($event) = @_;
		my $args = $event->{VALUE};
		if (! ($args =~ s/.*utf8\s+(.*)/$1/i)) {
			return "ERROR: Expected RE not matched!";
		};
		if ( $args =~ m/^[Uu]\+([0-9A-Fa-f]*)$/) {
			my $a = `grep -i '^$1\|' /home/wjc/research/CJ/unicode2.txt`;
			$a =~ s/^[^|]+\|(.*)/$1/;
			return $a;
		} else {
			my @a = split(/\n/, `grep -i \'\|\.\*$args\' /home/wjc/research/CJ/unicode2.txt`);
			if (scalar(@a) > 10) {
				return "Your search found " . scalar(@a) . " countries. Be more specific.";
			} elsif (scalar(@a) > 0) {
				my $tmp = join ("\'; ", @a);
				$tmp =~ s/\|/=\'/g;
				return $tmp . "'";
			} else {
				return "Found no matches.";
			}
		}
	},
	HELP   => sub { return "Usage: utf8 <val>, where val is either U+<hex> or a string to match against possible characters.";} ,
	TYPE   => [qw/private public emote/],
	POS    => '0', 
	STOP   => 1,
	RE     => qr/\butf8\b/i,
};
}
# This is already pretty unweidly.
#
sub cleanHTML {

  $a = join(" ",@_);

  $a =~ s/\n/ /;
  $a =~ s/<[^>]*>/ /g;
  $a =~ s/&lt;/</gi;
  $a =~ s/&gt;/>/gi;
  $a =~ s/&amp;/&/gi;
  $a =~ s/&#46;/./g;
  $a =~ s/&#039;/'/g;
  $a =~ s/&quot;/"/ig;
  $a =~ s/&nbsp;/ /ig;
  $a =~ s/&uuml;/u"/ig;
  $a =~ s/\s+/ /g;
  $a =~ s/^\s+//;

  return $a;
}

sub dispatch {

	my ($event,$message) = @_;

	return if ($message eq "");

	if ($event->{type} eq "emote") {
		$message = '"' . $message;
	}
	my $line = $event->{_recips} . ":" .$message;

	TLily::Server->active()->cmd_process($line, sub {$_[0]->{NOTIFY} = 0;});
};

sub cj_event {
	my($event, $handler) = @_;

	$event->{NOTIFY}=0;

	# I should never respond to myself. There be dragons!
	#  this is actually an issue with emotes, which automatically
	#  send the message back to the user.
	if ($event->{SOURCE} eq $name) {
		return;
	}

	# throttle:
	my $last = $throttle{$event->{SOURCE}}{last};
	my $status = $throttle{$event->{SOURCE}}{status}; #normal(0)|danger(1)
	$throttle{$event->{SOURCE}}{last} = time;


	if ( ($throttle{$event->{SOURCE}}{last} - $last) < $throttle_interval) {
		#TLily::UI->name("main")->print("$event->{SOURCE} tripped throttle!\n");
		$throttle{$event->{SOURCE}}{count} +=1;
	} elsif ( ($throttle{$event->{SOURCE}}{last} - $last) > $throttle_safety) {
		#TLily::UI->name("main")->print("$event->{SOURCE} is no longer dangerous!\n");
		$throttle{$event->{SOURCE}}{count} = 0;
		$throttle{$event->{SOURCE}}{status} = 0;
	}

	if ($throttle{$event->{SOURCE}}{count} > 3) {
		if ($status) {
			(my $offender = $event->{SOURCE}) =~ s/\s/_/g;
			TLily::Server->active()->cmd_process("/ignore $offender all", sub {$_[0]->{NOTIFY} = 0;});
		} else {
			#TLily::UI->name("main")->print("$event->{SOURCE} is now dangerous!\n");
			$throttle{$event->{SOURCE}}{status} = 1;
			$throttle{$event->{SOURCE}}{count} = 0;
		}
	}

	if ($status) {
		return; #They're dangerous. don't talk to them.
	}


	# Who should get a response? If it's private, the sender
	# and all recips. If public/emote, just the recips.
	
	my @recips = split(/, /,$event->{RECIPS});
	if ($event->{type} eq "private") {
		push @recips, $event->{SOURCE};
	}
	@recips = grep {!/^$name$/} @recips;
  my $recips = join (",", @recips);
	$recips =~ s/ /_/g;
	$event->{_recips} = $recips;

	# Workhorse for responses:
	my $message="";
	HANDLE_OUTER: foreach my $order (qw/-1 0 1/) {
		HANDLE_INNER: foreach my $handler (keys %response) {
			if ($response{$handler}->{POS} eq $order) {
				next if ! grep {/$event->{type}/} @{$response{$handler}{TYPE}};
				my $re = $response{$handler}->{RE};
				if ($event->{type} eq "public") {
					$re = '^\s*' . $re;
				}
				if ($event->{VALUE} =~ m/$re/) {
					$message .= &{$response{$handler}{CODE}}($event);
					if ($response{$handler}->{STOP}) {
						last HANDLE_OUTER;
					}
				}
			}	
		} 
	}

  dispatch($event, $message);
}

#
# Insert event handlers for everything we care about.
#
for (qw/public private emote/) {
	event_r(type => $_, order=>'before', call => \&cj_event);
}

my $once_a_minute;
sub load {
	my $server = TLily::Server->active();
#	TLily::Server->active()->cmd_process("/blurb HUP", sub {$_[0]->{NOTIFY} = 0;});
#	TLily::Server->active()->cmd_process("/blurb off", sub {$_[0]->{NOTIFY} = 0;});
	use DB_File;
	dbmopen(%prefs,"/home/wjc/private/CJ_prefs.db",0666) or die "couldn't open DBM file!";
	$server->fetch(call=>sub {my %event=@_;  $sayings = $event{text}}, type=>"memo", target=>$disc, name=>"sayings");
	$server->fetch(call=>sub {my %event=@_;  $overhear = $event{text}}, type=>"memo", target=>$disc, name=>"overhear");
	$server->fetch(call=>sub {my %event=@_;  $buzzwords = $event{text}}, type=>"memo", target=>$disc, name=>"buzzwords");
	$server->fetch(call=>sub {my %event=@_;  $unified= $event{text}}, type=>"memo", target=>$disc, name=>"-unified");

	#$once_a_minute= TLily::Event::time_r( call => sub { pointcast_stocks();} , interval => 60);
}


sub unload {
#	TLily::Server->active()->cmd_process("/blurb OFFLINE", sub {$_[0]->{NOTIFY} = 0;});
	dbmclose(%prefs);
	TLily::Event->time_u($once_a_minute);
}

TLily::UI->name("main")->print("(loaded)");
1;
