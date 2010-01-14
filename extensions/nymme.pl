# -*- Perl -*-
# $Id$

use strict;
use warnings;

my $usage = 'Collapse whitespace on incoming messages.';
shelp_r(nymme => $usage);
help_r(nymme => $usage);

sub handler {
    my $event = shift;
    $event->{VALUE} =~ s/\s+/ /g;
    return 0;
}

foreach my $type (qw/public private emote/) {
    event_r(type => $type, order => 'before', call => \&handler);
}
