# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/stripper.pl,v 1.1 2000/12/13 18:51:22 tale Exp $

# strip out leading spaces on sends.

use strict;

=head1 NAME

stripper.pl - Strip out leading spaces in messages you send

=head1 DESCRIPTION

When loaded, this extension will strip out any leading spaces in messages
that you send.

=cut

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/^\s+//g;
    return 0;
}

event_r(type  => 'input',
	call  => \&handler,
	order => 'after');
