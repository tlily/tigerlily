
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

# %U: source's pseudo and blurb
# %u: source's pseudo
# %V: VALUE
# %T: title of discussion whose name is in VALUE.
# %R: RECIPS
# %O: name of thingy whose OID is in VALUE.
#
# leading characters (up to first space) define behavior as follows: 
# A: always use this message
# V: use this message if VALUE is defined.
# E: use this message if VALUE is empty.
# v: use this message if the source of the event is "me" and VALUE is defined
# e: use this message if the source of the event is "me" and the VALUE is empty

# the first matching message is always used.

my @infomsg = (connect    => 'A *** %U has entered lily ***',
	       attach     => 'A *** %U has reattached ***',
	       disconnect => 'V *** %U has left lily (%V) ***',
	       disconnect => 'E *** %U has left lily ***',
	       detach     => 'E *** %U has detached ***',
	       detach     => 'V *** %U has been detached %V ***',
	       here       => 'e (you are now here)',
	       here       => 'E *** %U is now "here" ***',
	       away       => 'e (you are now away)',
	       away       => 'E *** %U is now "away" ***',
	       away       => 'V *** %U has idled "away" ***', # V=idled really.
	       rename     => 'v (you are now named %V)',
	       rename     => 'V *** %u is now named %V ***',
	       blurb      => 'e (your blurb has been turned off)',
	       blurb      => 'v (your blurb has been set to [%V])',
	       blurb      => 'V *** %u has changed their blurb to [%V] ***',
	       blurb      => 'E *** %u has turned their blurb off ***',
	       info       => 'e (your info has been cleared)',
	       info       => 'v (your info has been changed)',
	       info       => 'V *** %u has changed their info ***',
	       info       => 'E *** %u has cleared their info ***',
	       ignore     => 'A *** %u is now ignoring you %V ***',
	       unignore   => 'A *** %u is no longer ignoring you ***',
	       unidle     => 'A *** %u is now unidle ***',
	       create     => 'e (you have created discussion %R "%T")',
	       create     => 'E *** %u has created discussion %R "%T" ***',
	       destroy    => 'e (you have destroyed discussion %R)',
	       destroy    => 'E *** %u has destroyed discussion %R ***',
# bugs in slcp- permit/depermit don't specify people right.
#	       permit     => 'e (someone is now permitted to discussion %R)',
#	       permit     => 'E (You are now permitted to some discussion)',
#	       depermit   => 'e (Someone is now depermitted from %R)',
# note that slcp doesn't do join and quit quite right
	       permit     => 'V *** %O is now permitted to discussion %R ***',
	       depermit   => 'V *** %O is now depermitted from %R ***',
	       join       => 'e (you have joined %R)',
	       join       => 'E *** %u is now a member of %R ***',
	       quit       => 'e (you have quit %R)',
	       quit       => 'E *** %u is no longer a member of %R ***',
	       retitle    => 'v (you have changed the title of %R to "%V")',
	       retitle    => 'V *** %u has changed the title of %R to "%V" ***',
	       sysmsg     => 'V %V',
	       pa         => 'V ** Public address message from %U: %V **'
# need to handle review, sysalert, pa, game, and consult.	       
);

	
# here's the handler for the above messages..
register_eventhandler(Order => 'before',
		      Call => sub {
			my ($e) = @_;
			my $serv = $e->{Server} || $::servers[0];

			return 0 if (! $e->{ToUser});

			my $Me =  $serv->user_name;

			my $i = 0;
			my $found;
			while ($i < $#infomsg) {
			  my $type = $infomsg[$i];
			  my $msg = $infomsg[$i + 1];
			  $i += 2;
			  
			  next unless ($type eq $e->{Type});
			  ($flags,$msg) = ($msg =~ /(\S+) (.*)/);
			  if ($flags =~ /A/) {
                            $found = $msg; last;
                          }
			  if ($flags =~ /V/ && ($e->{VALUE} =~ /\S/)) { 
			    $found = $msg; last; 
			  }
			  if ($flags =~ /E/ && ($e->{VALUE} !~ /\S/)) {
			    $found = $msg; last;
			  }
			  if ($flags =~ /v/ && ($e->{SOURCE} eq $Me)
			                    && ($e->{VALUE} =~ /\S/)) {
			    $found = $msg; last;
			  }
			  if ($flags =~ /e/ && ($e->{SOURCE} eq $Me)
			                    && ($e->{VALUE} !~ /\S/)) {
			    $found = $msg; last;
			  }
			}
			
			if ($found) {
			  my $source = $e->{SOURCE};
			  $found =~ s/\%u/$source/g;
			  my $blurb = $serv->get_blurb(HANDLE => $e->{HANDLE});
			  $source .= " [$blurb]" if $blurb;
			  $found =~ s/\%U/$source/g;
			  $found =~ s/\%V/$e->{VALUE}/g;
			  $found =~ s/\%R/$e->{RECIPS}/g;
                          if ($found =~ /\%O/) {
			    my $target = $serv->get_name(HANDLE => $e->{VALUE});
			    $found =~ s/\%O/$target/g;
                          }
			  if ($found =~ /\%T/) {
			    my $title = $serv->get_title(NAME => $e->{RECIPS});
			    $found =~ s/\%T/$title/g;
			  }

			  $e->{Text} = "<notify>$found</notify>";
			}
			
			return(0);
		      });



