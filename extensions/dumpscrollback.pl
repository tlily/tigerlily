# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/dumpscrollback.pl,v 1.1 2000/04/02 09:23:55 josh Exp $

use strict;

my $help = '
Usage: %dumpscrollback <filename>

Dump all scrollback from the current UI to a file.
';

sub command {
    my($ui, $args) = @_;

    if ($args !~ /\S/) {
        $ui->print("Usage: %dumpscrollback <file>\n");
	return;
    }

    my $count = $ui->dump_to_file($args);
    $ui->print("($count lines written to $args)");

    return;
}
command_r('dumpscrollback' => \&command);
shelp_r('dumpscrollback' => "Dump the scollback buffer to a file.");
help_r('dumpscrollback' => $help);

