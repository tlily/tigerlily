# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/todeath.pl,v 1.2 2001/11/26 19:51:38 josh Exp $

use strict;

=head1 NAME

todeath.pl - Fix stupid political correctness.

=head1 DESCRIPTION

When loaded, this extension will change the "(idled off the server)" message
back to its rightful "(idled to death)" (or whatever the 'todeath_message'
config variable is set to).

=cut

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/off the server/$config{todeath_message}/g;
    $event->{text}  =~ s/off the server/$config{todeath_message}/g;

    return 0;
}

$config{todeath_message} ||= "idled to death";

event_r(type  => 'disconnect',
	call  => \&handler,
	order => 'before');

