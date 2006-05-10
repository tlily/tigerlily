#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2005  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# BUGS:
# Login procedure needs work.  (should be able to read login/pw from a file or cmdline)
# globals really should be toned down. (move them into the registry sstuff)
# need to catch failure of the timed keepalive and re-login.
#
# Only one bot extension should be loaded at a time.   We can set a flag
#    in here, but i'll need a hook in the regular extension unloading thing
#    to clear that flag.   This is a nice way to allow bot extension reloading
#    to work right.
# bot_r should vomit if not in standard bot mode.
# bots are NOT multi-server safe.
# cmd's whose only output is a %NOTIFY don't respond. (i.e. /here, /away, /bl)


# $Id$

package TLily::Bot;

use TLily::Config qw(%config);
use TLily::Event qw(event_r);
use TLily::Extend;

use Text::Wrap;
use Safe;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

my ($username,$password);
my (%bot_handlers,$bhid);

@ISA = qw(Exporter);
@EXPORT_OK   =                 qw(&bot_r &bot_u &response &wrap_lines);
%EXPORT_TAGS = ( extension => [qw(&bot_r &bot_u &response &wrap_lines)] );


=head1 NAME

TLily::Bot - User command manager.

=head1 SYNOPSIS

 use TLily::Bot;

=head1 DESCRIPTION

=head1 FUNCTIONS

  TLily::Bot::init();

  $handle = bot_r(match => "grope",
                  respond => "Me grope good!");

  bot_u($handle);

=over 10

=cut

=item init

Initializes the bot subsystem.

  TLily::Bot::init();

=cut



=back

=cut

1;

sub init {

    return unless $config{'bot'};

    # if $config{bot} is set (i.e. tlily was invoked with the -bot=<foo>
    # argument, we set a few things up:

    # use the "text" UI by default, unless specified otherwise.
    $config{UI} ||= "Text";


    # avoid prompts by hitting enter at all of them.
    # (specific ones can be overridden)
    event_r(type  => 'prompt',
	    order => 'after',
	    call  => sub {
		my($event, $handler) = @_;

		if ($event->{text} =~ /^login:/) {
		    print "(sending username '$username')\n";
		    $event->{server}->sendln($username);
		    return 1;
		}
		
		if ($event->{text} =~ /^password:/) {
		    print "(sending password '$password')\n";
		    $event->{server}->sendln($password);
		    return 1;
		}

		# Try to avoid reviewing :)
		if ($event->{text} =~ /do you wish to review/) {
		    print "(review prompt, sending 'N')\n";
		    $event->{server}->sendln("N");
		    return 1;
		}
		
		# Fallback is to just hit enter at any prompt :)
		print "(sending enter at prompt)\n";
		$event->{server}->sendln("");
		return 1;
	    });

    event_r(type  => 'connected',
	    order => 'after',
	    call  => sub {
		my($event, $handler) = @_;

		# "keepalive" so we notice if we get disconnected.
		TLily::Event::time_r(interval => 120,
				     call => sub {
					     $event->{server}->cmd_process("/display time", sub {
					     my ($e) = @_;
					     # hide it from the user.
					     $e->{ui_name} = undef;
					 });
					 return 1;

			 } );
		return 1;
	    });
}



sub import {
    my ($module,@options) = @_;

    # If this is "use"'d from an extension file, it would be invoked as
    # use TLily::Bot <argument>
    # Here, I check to see if it was done that way.  If so, we can
    # do some special initialization stuff to get the bot extension
    # bootstrapped.

    my @a = ($module);
    #my @a;

    if (@options) {
	# this needs work ;)
	unless ($username =~ /\S/) {
	    print "Username: "; chomp($username=<STDIN>);
	    print "Password: "; chomp($password=<STDIN>);
        }

	foreach (@options) {
	    if ($_ eq "standard") {
		# a "standard" bot has a default message handler, and common
		# commands.  Unsurprisingly, it bears a striking resemblance
		# to mechajosh ;-)
		standard_bot_init();
		
	    } elsif ($_ eq "custom") {
		# a custom bot defines no message handlers for you- do your
		# own!
		
	    } else {
		die("Invalid TLily::Bot option: $_\n");
	    }
	}
	
    	push @a, ":extension";
    }

    # this passes control back to Exporter.pm's import function
    TLily::Bot->export_to_level(1, @a);
}



sub standard_bot_init {

    # set up the send handler
    foreach (qw(private public emote)) {
	event_r(order => 'after',
		type => $_,
		call => \&standard_bot_sendhandler);
    }

    # set up a handler for "help".
    bot_r(match => "help",
	  private => 1,
	  respond => "I know the following commands:
  cmd register [private] keyphase=response
  cmd deregister #
  cmd list
  cmd show #
  cmd <what you want me to do>

Note that a \"response\" can contain perl code prefixed by \"CODE:\".  Its return value will be sent to the sender.  The original send will be in \$send.");

}


sub standard_bot_sendhandler {
    my($event,$handler) = @_;

    my $ui = TLily::Server::ui_name();

    if ($event->{isuser}) {
	# it's a message to me- ignore it.

	return 1;
    }

    # bot commands all begin with the prefix "cmd".
    if ($event->{VALUE} =~ /cmd\s+(.*)/) {
	
	standard_bot_command($event,$1);
    }

    # ok, check for bot handlers that match this text..
    my $h;
    foreach $h (values %bot_handlers) {
	my $message = $event->{VALUE};

	if ($message =~ m/$h->{match}/i) {
	    next if (($event->{type} eq "public") && $h->{private});
	    my $pfx = ($event->{type} eq "emote") ? "\"" : "";

	    if (ref($h->{respond})) {
		my $response=&{$h->{respond}}($message);
		response($event,"$pfx$response\n") if $response;
	    } elsif ($h->{respond} =~ /^CODE: (.*)/) {
		my $code=$h->{respond};
		my $cpt=new Safe;
		my $send=$event->{VALUE}; $send=~s/[\r\n\']//g;
		my $response=$cpt->reval("\$send='$send'; $code");

		if ($@) {
		    response($event,"${pfx}Error in eval: $@\n");
		} else {
		    response($event,"${pfx}$response\n") if $response;
		}
	    } else {
		response($event,"$pfx$h->{respond}");
	    }
	}
    }
}


sub standard_bot_command {
    my ($event, $command) = @_;

    # only respond to "cmd" bot commands via private messages.
    return 1 unless ($event->{type} eq "private");

    if ($command =~ /^deregister (.*)/) {
	my $id=$1;
	if (bot_u($id)) {
	    response($event,"Deregistered handler $id.");
	} else {
	    response($event,"Unable to deregister handler $id.");
	}
	return 1;
    }

    if ($command =~ /^list/) {
	my $ret="The following keywords are known: ";
	foreach (sort keys %bot_handlers) {
	    if ($bot_handlers{$_}->{private}) {
		$ret .= "$_) $bot_handlers{$_}->{match} (private only) | ";
	    } else {
		$ret .= "$_) $bot_handlers{$_}->{match} | ";
	    }

	}
	response($event,$ret);
	return;
    }

    if ($command =~ /^show (\d+)/) {
	my $ret = "Handler $1 (matching $bot_handlers{$1}->{match}): ";
	$ret.=$bot_handlers{$1}->{respond};
	$ret=~s/[\n\r]/ /g;
	response($event,$ret);
	return 1;
    }

    if ($command =~ /^register private ([^\=]+)\=(.*)/) {
	my ($match,$respond)=($1,$2);
	
	bot_r(match => $match,
	      private => 1,
	      respond => $respond);
	
	response($event,"Registered handler to match \"$match\". (in private sends only)");
	return 1;
    }

    if ($command =~ /^register ([^\=]+)\=(.*)/) {
	my ($match,$respond)=($1,$2);
	
	#XXX
	response($event,"Registering public handlers is not supported at this time.  Try cmd register private.");
	return 1;
	#XXX
	bot_r(match => $match,
	      respond => $respond);
	
	response($event,"Registered handler to match \"$match\".");
	return 1;
    }


    # cmd <foo>: execute <foo>.
    $event->{server}->cmd_process($1, sub {
		    my ($e) = @_;

		    if ($e->{type} eq "begincmd") {
			$event->{cmd_result}="";
			return;
		    }

		    if ($e->{type} eq "endcmd") {
			response($event,$event->{cmd_result});
			$event->{cmd_result}="";
			return;
		    }

		    $event->{cmd_result} .= "$e->{text}\n";
		});

    return 1;
}


sub response {
    my ($event,$string,$nowrap)=@_;

    my $respond_to = $event->{SOURCE};
    if ($event->{type} ne "private") {
	$respond_to = $event->{RECIPS};
    }
    $respond_to=~ s/\s/_/g;

    if ($nowrap) {
        $string = "$respond_to;$string";
    } else {
        $string = "$respond_to;" . wrap_lines($string);
    }

    print "(sending \"$string\" to server)\n";

    $event->{server}->sendln($string);
}


sub bot_r {
    my (%hdl)=@_;

    $bhid++;
    $bot_handlers{$bhid}=\%hdl;
}

sub bot_u {
    my ($bhid)=@_;

    if ($bot_handlers{$bhid}) {
	delete $bot_handlers{$bhid};
	return 1;
    } else {
	return 0;
    }
}

# format messages with space so a multi-line send looks ok on a normal 80
# column client.
sub wrap_lines {
    my ($str) = @_;
    my $ret;

    my $wrap_to = 75;

    return $str unless ($str =~ /\n/);

    $Text::Wrap::columns = 77;
    my $str = wrap('','',$str);

    my @lines;
    $str =~ s/\n$//g;
    foreach my $line (split /\n/, $str) {
	$ret .= $line;
        my $len = length($line);

        my $spaces_needed = $wrap_to - ($len % $wrap_to);

        $ret .= " " x $spaces_needed;
    }

    return($ret);
}


# die!
sub realdie {
    print "@_\n";
    exit(1);
}
