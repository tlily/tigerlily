# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/misc.pl,v 1.19 1999/10/02 02:45:20 mjr Exp $ 

use strict;
use TLily::Version;


#
# !commands, %command
#

my $last_command = '';
sub shell_handler {
    my($ui, $command) = @_;
    
    $command = $last_command if ($command =~ /^\!/);
    $last_command = $command;
    
    $ui->print("[beginning of command output]\n");
    
    local *FD;
    open(FD, "$command 2>&1 |");
    $ui->print(<FD>);
    close(FD);
    
    $ui->print("[end of command output]\n");
    
    return;
}

sub bang_handler {
    my($event, $handler) = @_;
    if ($event->{text} =~ /^\!(.*?)\s*$/) {
	shell_handler($event->{ui}, $1);
	return 1;
    }
    return;
}

shelp_r('shell' => 'run shell command');
help_r('shell' => '
Usage: %shell <command>
       ! <command>
');
event_r(type => 'user_input',
		      call => \&bang_handler);
command_r('shell' => \&shell_handler);


#
# %eval
#

sub eval_handler {
    my($ui, $args) = @_;
    if ($args =~ /^(?:list|l|array|a)\s+(.*)/) {
	$args = $1;
	my @rc = eval($args);
	if ($@) {
	    $ui->print("* Error: $@") if ($@);
	}
	if (@rc) {
	    $ui->print("-> (", join(", ", @rc), ")\n");
	}
    } else {
	my $rc = eval($args);
	if ($@) {
	    $ui->print("* Error: $@") if ($@);
	}
	if ($rc) {
	    $ui->print("-> ", $rc, "\n");
	}
    }
    return;
}
	     
command_r('eval' => \&eval_handler);
shelp_r('eval' => 'run perl code');
help_r('eval' => '
Usage: %eval [list] <code>

Evaluates the given perl code.  The code is evaluated in a scalar context,
unless the "list" parameter is given, in which case it is evaluated in a
list context.

The results of the eval, if any, will be printed.
');
		 

#
# %version
#

sub version_handler {
    my($ui, $args) = @_;
    $ui->print("(Tigerlily version $TLily::Version::VERSION)\n");
    my $server = TLily::Server::active();
    $server->sendln("/display version");
    return;
}

shelp_r('version' => 'Display the Tigerlily and server versions');
help_r('version' => '
Usage: %version

Displays the version of Tigerlily and the server.
');
command_r('version' => \&version_handler);


#
# %echo
#

# %echo handler
sub echo_handler {
    my($ui, $text) = @_;
    $ui->print($text, "\n");
    return;
}

shelp_r('echo' => 'Echo text to the screen.');
help_r('echo' => '
Usage: %echo [-n] <text>
');
command_r('echo' => \&echo_handler);

#
# %exit
#

shelp_r('exit' => 'Exit TigerLily');
help_r('exit' => 'Usage: %exit');
command_r('exit' => sub { TLily::Event::keepalive(); exit; });

#
# %sync
#

shelp_r('sync' => 'Resync with SLCP');
help_r('sync' => 'Usage: %sync');
command_r('sync' => sub { 
	      my ($e) = @_;
	      TLily::Event::send({type => 'user_input',
				  ui   => $e->{ui},
				  text => "#\$# slcp-sync\n"});
	  });
	      

#
# Credits.
#

my $credits = qq{
Steve "Steve" Czetty       HTTP, CTC.
Damien "damien" Neil       UI(, UI, UI), event loop, design
Matt "Silent Bob" Ryan     Biff.
Chris "Albert" Stevens     Configuration; Build.PL/Makefile.PL.
Josh "Josh" Wilmes         Parser (classic and SLCP), extensions, subclient.
};
shelp_r("credits" => "The people who brought you tlily.", "concepts");
help_r("credits" => $credits);

my $history = qq{
Tigerlily began sometime around September 1997, when Chris "Albert" Stevens, \
Damien "damien" Neil, Jon "jamah" Mah, and Josh "Josh" Wilmes were eating \
dinner at Chevy's.  Damien mentioned that Perl was the only logical language \
to write an intelligent Lily client in.  When he went on to mention that he \
had worked up the beginnings of a Curses UI in Perl, Josh promptly fell in \
love with the idea.  The next weekend produced some very scary code, and most \
of a working client.

Josh wrote the first Lily parser, an evil beast spawned from the depths of \
hell.  (That was a compliment, Josh.)  He is also responsible for extensions, \
one of tlily's most useful features.  Damien wrote the first UI, and is \
responsible for the event loop.  Chris wrote the configuration module, and \
has maintained the build-and-distribution code from the beginning.  Other \
contributors of note include Matt "Silent Bob" Ryan and Steve "Steve" Czetty.

The first recorded release date is 0.2c, October 28, 1997.  1.0 was released \
on June 11, 1998.

Sometime around the start of 1999, Josh rewrote the parser to support the \
new SLCP protocol.  Damien rewrote the UI (again) to make it faster and \
cleaner.  With momentum gathering, most of the rest of tlily was redesigned. \
The result is Tigerlily 2.0.
};
shelp_r("history" => "A brief history of tlily.", "concepts");
help_r("history" => $history);


# NOTE:  HIDESEND DOES NOT WORK.  WE DON'T CARE ENOUGH TO FIX IT AT PRESENT.
#
# This will hide your own sends if the hidesend option is turned on.
# %set hidesend 1
# %set hidesend 0
#
#event_r(type => 'user_input',
#	call => sub {
#	    my($e, $h) = @_;
#	    $e->{NOTIFY} = 0 if ($config{hidesend} && 
#				 $e->{text} =~ /^\S*[;:]/);
#	    
#	    return 0;
#	});
