# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/bmw.pl,v 1.3 2002/05/30 15:59:20 coke Exp $

# strip out leading spaces on sends.

use strict;

=head1 NAME

bmw.pl - Strip out leading spaces in received messages

=head1 DESCRIPTION

When loaded, this extension will strip out any leading spaces in any public
or private messages you receive.

=cut

help_r( 'bmw', "Strip leading whitespace from incoming messages.

This extension was named its inspiration, bmw\@RPI.
");

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/^\s+//g;
    return 0;
}

event_r(type  => 'public',
	call  => \&handler,
	order => 'before');

event_r(type  => 'private',
	call  => \&handler,
	order => 'before');


