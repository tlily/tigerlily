# -*- Perl -*-

# strip out leading spaces on sends.

use strict;

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


