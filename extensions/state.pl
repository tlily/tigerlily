
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
		next if ($keep{$_}{$s} == 1);

		my $sub = {
			my($e) = @_;
			my $serv = $e->{server};

			if ($s eq "NAME") {
				$serv->state(HANDLE => $e->{HANDLE},
				NAME => $e->{VALUE},
				UPDATED => 1);
			} else {
				$serv->state(HANDLE => $e->{HANDLE},
				$s, $e->{VALUE});
			}
			return;
		};

		$event->event_r(type  => $keep{$_}{$s},
		                order => 'after',
		                call  => $sub);
	}
}


# special handlers
# USER/STATE (dispatch userstate events _and_ update STATE)

my $sub = sub {
	my($e) = @_;
	my $serv = $e->{server};

	$serv->state(HANDLE => $e->{HANDLE},
	             STATE  => "here");

	# if it's me, fire off a userstate event.
	if ($e->{IsUser}) {
		my %event = (type   => 'userstate',
		             isuser => 1,
		             from   => 'away',
		             to     => 'here',
		             server => $e->{Server});
		$event->send(\%event);
	}

	return;
};
$event->event_r(type  => 'here',
		order => 'before',
		call  => $sub);

$sub = sub {
	my ($e) = @_;
	my $serv = $e->{server};

	$serv->state(HANDLE => $e->{HANDLE},
	             STATE  => "away");

	# if it's me, fire off a userstate event.
	if ($e->{IsUser}) {
		my %event = (type   => 'userstate',
		             isuser => 1,
		             from   => 'here',
		             to     => 'away',
		             server => $serv);
		$event->send(\%event);
	}

	return;
};
$event->event_r(type  => 'away',
		order => 'before',
		call  => $sub);

# DISC/destroy
# (need to add one.. not that it matters really)


# The other thing SLCP does is to get rid of a lot of the informational 
# messages from the server.  Here's an attempt to provide an easy way for 
# the client to provide these..



