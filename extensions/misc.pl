# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/misc.pl,v 1.8 1999/02/26 22:45:38 josh Exp $ 

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
    $ui->print("(Tigerlily version $TLily::Version::TL_VERSION)\n");
    my $server = server_name();
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
    my($cmd, $ui, $text) = @_;
    $ui->print($text, "\n");
    return;
}

shelp_r('echo' => 'Echo text to the screen.');
help_r('echo' => '
Usage: %echo [-n] <text>
');
command_r('echo' => \&echo_handler);
