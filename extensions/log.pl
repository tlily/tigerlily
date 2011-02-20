# -*- Perl -*-

use strict;

=head1 NAME

log.pl - Log session to a file

=head1 DESCRIPTION

Allows you to log the current session to a file.

=head1 COMMANDS

=over 10

=item %log

Turns logging on or off, or prints the current logging status.  See
"%help %log" for details.

=cut

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

