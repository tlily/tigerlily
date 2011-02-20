# -*- Perl -*-
# $Id$

# This hash keeps track of what fields from %USER and %DISC are stored in
# the state database.  We need to ensure that every one of these state
# variables that we do store is properly updated by the corresponding %NOTIFY
# events.

# NOTE! due to the way i implemented the state() function, you need to store
# at least one property besides HANDLE and NAME.

# These hashes mark the stored state to the SLCP notify type which updates
# them.  handlers are automatically made, setting the state variable to
# the VALUE parameter of the associated SLCP notify.  Set the value to plain
# ol' "1" to avoid this behavior, for cases where a less generic handler is
# needed.

use strict;

for my $spec ([rename => "NAME"], [blurb => "BLURB"]) {
    my $field = $spec->[1];

    my $sub = sub {
        my($e) = @_;
        $e->{server}->state
            (HANDLE  => $e->{SHANDLE},
             $field  => $e->{VALUE},
             UPDATED => 1);
        return;
    };

    event_r(type  => $spec->[0],
            order => 'during',
            call  => $sub);
}

for my $spec ([drename => "NAME"], [retitle => "TITLE"]) {
    my $field = $spec->[1];

    my $sub = sub {
        my($e) = @_;
        $e->{server}->state
            (HANDLE  => $e->{RHANDLE}->[0],
             $field  => $e->{VALUE},
             UPDATED => 1);
        return;
    };

    event_r(type  => $spec->[0],
            order => 'during',
            call  => $sub);
}


# special handlers
# USER/STATE (dispatch userstate events _and_ update STATE)

my $sub = sub {
    my($e) = @_;
    my $serv = $e->{server};

    $serv->state(HANDLE => $e->{SHANDLE},
                 STATE  => "here");

    # if it's me, fire off a userstate event.
    if ($e->{isuser}) {
        my %event = (type   => 'userstate',
                     isuser => 1,
                     from   => 'away',
                     to     => 'here',
                     server => $e->{Server});
        TLily::Event::send(\%event);
    }

    return;
};
event_r(type  => 'here',
        order => 'before',
        call  => $sub);

$sub = sub {
    my ($e) = @_;
    my $serv = $e->{server};

    $serv->state(HANDLE => $e->{SHANDLE},
                 STATE  => "away");

    # if it's me, fire off a userstate event.
    if ($e->{isuser}) {
        my %event = (type   => 'userstate',
                     isuser => 1,
                     from   => 'here',
                     to     => 'away',
                     server => $serv);
        TLily::Event::send(\%event);
    }

    return;
};
event_r(type  => 'away',
        order => 'before',
        call  => $sub);

# DISC/destroy
# (need to add one.. not that it matters really)
$sub = sub {
    my ($e) = @_;

    my $name = $e->{server}->get_name(HANDLE => $e->{RHANDLE}->[0]);

    $e->{server}->state(HANDLE   => $e->{RHANDLE}->[0],
                        NAME     => $name,
                        __DELETE => 1);
};
event_r(type => 'destroy',
        call => $sub);

