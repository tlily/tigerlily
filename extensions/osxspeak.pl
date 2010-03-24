# -*- Perl -*-
# $Id$

use strict;
use warnings;

help_r('osxspeak',<<EOH);
%extension load osxspeak  # enable the extension
%set osxvoice fred        # optional, defaults to sysvoice.
%on <foo> %attr speak 1   # only these events are spoken.
EOH

sub sayit {
    my($event, $handler) = @_;

    my $Me =  $event->{server}->user_name();
    
    # don't say anything if we sent the message somewhere.
    return if ($event->{SOURCE} eq $Me && $event->{RECIPS} ne $Me);
    
    # don't say anything unless the "speak" attribute has been set (with %on)
    return unless $event->{speak};
        
    my $message = "From $event->{SOURCE} to $event->{RECIPS}: $event->{VALUE}";
    
    if ($event->{type} eq "emote") {
        $message = "(to $event->{RECIPS}), $event->{SOURCE} $event->{VALUE}";
    }

    my $voice = ''; #default to sysvoice.
    if ($config{osxvoice}) {
        $voice = ' --voice="' . $config{osxvoice} . '" ';
    }

    $message =~ s/\n/ /g;
    system(qq{say $voice "$message"});

    return;
}

sub load {
    foreach my $type (qw/private public emote/) {
        event_r(
            type  => $type,
            order => 'after',
            call  => \&sayit
        );
    }
    return;
}

1;

