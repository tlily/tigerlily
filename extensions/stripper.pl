# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/stripper.pl,v 1.2 2000/12/14 21:49:25 tale Exp $

# strip out leading spaces on sends.

use strict;

=head1 NAME

stripper.pl - Strip out leading spaces in messages you send

=head1 DESCRIPTION

When loaded, this extension will strip out any leading spaces in messages
that you send.  On input lines that have a sequence of non-whitespace
characters up to the first colon or semi-colon, any whitespace immediately
following the colon or semicolon is removed.

=cut

sub handler {
    my($event, $handler) = @_;

    $event->{text} =~ s/^([^\s;:]*[;:])\s*(.*)/$1$2/;

    return 0;
}

event_r(type  => 'user_input',
	call  => \&handler);
