# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/todeath.pl,v 1.1 2001/11/26 02:45:37 josh Exp $

use strict;

=head1 NAME

todeath.pl - Fix stupid political correctness.

=head1 DESCRIPTION

When loaded, this extension will change the "(idled off the server)" message
back to its rightful "(idled to death)".

=cut

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/off the server/to death/g;
    $event->{text}  =~ s/off the server/to death/g;

    return 0;
}

event_r(type  => 'disconnect',
	call  => \&handler,
	order => 'before');

