# -*- Perl -*-

# strip out leading spaces on sends.

use strict;
use warnings;

=head1 NAME

bmw.pl - Strip out leading spaces in received messages

=head1 DESCRIPTION

When loaded, this extension will strip out any leading spaces in any public
or private messages you receive.

=cut

help_r( 'bmw', << 'END_HELP');
Strip leading whitespace from incoming messages.

This extension was named its inspiration, bmw@RPI.
END_HELP

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
