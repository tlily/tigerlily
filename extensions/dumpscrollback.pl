# -*- Perl -*-
# $Id$

use strict;

=head1 NAME

dumpscrollback.pl - Dump scrollback buffer to a file.

=head1 DESCRIPTION

Provides the %dumpscrollback command, which allows you to dump your
scrollback buffer to file.

=head1 COMMANDS

=item %dumpscrollback

=over 10

Dump the entire scrollback buffer to a file.  See "%help %dumpscrollback".

=back

=cut

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

    TLily::Event::keepalive();
    my $count = $ui->dump_to_file($args);
    TLily::Event::keepalive(5);

    $ui->print("($count lines written to $args)\n");

    return;
}
command_r('dumpscrollback' => \&command);
shelp_r('dumpscrollback' => "Dump the scollback buffer to a file.");
help_r('dumpscrollback' => $help);

