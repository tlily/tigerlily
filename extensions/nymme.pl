# -*- Perl -*-
# $Id$

# strip out the copious whitespace that shows up whenever someone tries to
# send multiline sends. (Worst Offender: SDN)

use strict;

=head1 NAME

nymme.pl - Strip out leading spaces in received messages

=head1 DESCRIPTION

When loaded, this extension will strip out any extraneous spaces in any
messages you receive.

=cut

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/\s{1,}/ /g;
    return 0;
}

event_r(type  => 'public',
	call  => \&handler,
	order => 'before');

event_r(type  => 'private',
	call  => \&handler,
	order => 'before');

event_r(type  => 'emote',
	call  => \&handler,
	order => 'before');



