# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/slcp_state.pl,v 1.5 2003/05/01 19:07:16 steve Exp $

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

my %keep;
%{$keep{USER}} = (HANDLE => 1,
		  NAME => 'rename',
		  BLURB => 'blurb',
		  STATE => 1);
%{$keep{DISC}} = (HANDLE => 1, 
		  NAME => 1,
		  TITLE => 'retitle');

# build the default handlers defined above:
foreach (keys %keep) {
    my $s;
    foreach $s (keys %{$keep{$_}}) {
	next if ($keep{$_}{$s} eq "1");
	
	my $sub = sub {
	    my($e) = @_;
	    my $serv = $e->{server};
	    
	    if ($s eq "NAME") {
		$serv->state(HANDLE => $e->{SHANDLE},
			     NAME => $e->{VALUE},
			     UPDATED => 1);
	    } else {
		$serv->state(HANDLE => $e->{SHANDLE},
			     $s, $e->{VALUE});
	    }
	    return;
	};
	
	event_r(type  => $keep{$_}{$s},
                order => 'during',
	        call  => $sub);
    }
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

