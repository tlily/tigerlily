# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/log.pl,v 1.2 1999/03/23 08:33:50 josh Exp $

use strict;

my $log_help = '
Usage: %log [off | <filename>]

Echo all output to the current window to a file.  Without any arguments,
prints the current logging status.  "%log off" disables logging.
';

sub log_command {
    my($ui, $args) = @_;

    if ($args eq "") {
	my $f = $ui->log();
	if (defined $f) {
	    $ui->print("(currently logging to \"$f\")\n");
	} else {
	    $ui->print("(logging is not enabled)\n");
	}
    }
    elsif ($args eq "off") {
	$ui->log(undef);
	$ui->print("(logging has been turned off)\n");
    }
    else {
	eval {
	    $ui->log($args);
	};
	if ($@) {
	    $ui->print($@);
	} else {
	    $ui->print("(now logging to \"$args\")\n");
	}
    }

    return;
}
command_r('log' => \&log_command);
shelp_r('log' => "Log output to a file.");
help_r('log' => $log_help);

