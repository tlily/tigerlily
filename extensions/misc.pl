# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/misc.pl,v 1.2 1999/02/24 01:01:46 neild Exp $ 

use strict;
use LC::Global qw($event $user);


#
# !commands, %command
#

my $last_command = '';
sub shell_handler {
	my($user, $ui, $command) = @_;

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
		shell_handler(undef, $event->{ui}, $1);
		return 1;
	}
	return;
}

$user->shelp_r('shell' => 'run shell command');
$user->help_r('shell' => '
Usage: %shell <command>
       ! <command>
');
$event->event_r(type => 'user_input',
		call => \&bang_handler);
$user->command_r('shell' => \&shell_handler);


#
# %eval
#

sub eval_handler($) {
	my($user, $ui, $args) = @_;
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

$user->command_r('eval' => \&eval_handler);
$user->shelp_r('eval' => 'run perl code');
$user->help_r('eval' => '
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
	my($user, $ui, $args) = @_;
	#$ui->print("(Tigerlily version $TL_VERSION)\n");
	#server_send("/display version\r\n");
	return;
}

$user->shelp_r('version' => 'Display the Tigerlily and server versions');
$user->help_r('version' => '
Usage: %version

Displays the version of Tigerlily and the server.
');
$user->command_r('version' => \&version_handler);


#
# %echo
#

# %echo handler
sub echo_handler {
	my($cmd, $ui, $text) = @_;
	$ui->print($text, "\n");
	return;
}

$user->shelp_r('echo' => 'Echo text to the screen.');
$user->help_r('echo' => '
Usage: %echo [-n] <text>
');
$user->command_r('echo' => \&echo_handler);
