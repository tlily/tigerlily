# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/osxspeak.pl,v 1.2 2003/08/12 05:09:00 coke Exp $

use strict;

# Based on Josh's experiment in win32 silliness.
#
# Arguably, win32speak.pl and osxspeak.pl can be merged into a single
# speak module.
#
# To use:
#
# %extension load osxspeak
# %on <foo> %attr speak 1
# 

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

    $message =~ s/[^a-z0-9]//ig;
    system("osascript -e 'say \"$message\"'&");

    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'after',
	    call  => \&sayit);
    event_r(type  => 'public',
	    order => 'after',
	    call  => \&sayit);
    event_r(type  => 'emote',
	    order => 'after',
	    call  => \&sayit);
}

1;

