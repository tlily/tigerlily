package TLily::Event::Core;

use strict;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    
    # Values to pass to select().
    $self->{rbits} = "";
    $self->{wbits} = "";
    $self->{ebits} = "";
    
    bless $self, $class;
}


sub io_r {
    my($self, $fileno, $mode) = @_;
    vec($self->{rbits}, $fileno, 1) = 1 if ($mode =~ /r/);
    vec($self->{wbits}, $fileno, 1) = 1 if ($mode =~ /w/);
    vec($self->{ebits}, $fileno, 1) = 1 if ($mode =~ /e/);
}


sub io_u {
    my($self, $fileno, $mode) = @_;
    vec($self->{rbits}, $fileno, 1) = 0 if ($mode =~ /r/);
    vec($self->{wbits}, $fileno, 1) = 0 if ($mode =~ /w/);
    vec($self->{ebits}, $fileno, 1) = 0 if ($mode =~ /e/);
}


sub run {
    my($self, $timeout) = @_;

    my($rout, $wout, $eout) =
      ($self->{rbits}, $self->{wbits}, $self->{ebits});
    my $nfound = select($rout, $wout, $eout, $timeout);

    return ($rout, $wout, $eout, $nfound);
}



package TLily::Event;

use strict;
use Carp;
use TLily::Registrar;
use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(&event_r &event_u);


=head1 NAME

TLily::Event - Event queue.

=head1 DESCRIPTION

This class implements the core tlily event loop.  (Ideally, Perl would have
its own event loop, rendering this class needless...but at this time the
Perl Event.pm is not yet complete, so we use our own internal version.)

=head2 EVENTS

The event system handles four types of events: named events, timed events,
I/O events, and idle events.

=over

=item Named events

Named events are triggered with the send() call (see below).  A named event
is a hashref.  All named events must have a 'type' parameter, which is used
to determine which handlers receive that event.

=item Timed events

Timed events are triggered at specified times.

=item I/O events

I/O events are triggered when activity occurs on a given filehandle.

=item Idle events

Idle events are triggered when there is no other activity.

=head2 FUNCTIONS

=over

=cut


# Queue of waiting events.
my @queue;

# Priority-sorted list of event handlers.
my @e_name;

# Time-sorted list of timed handlers.
my @e_time;

# IO handlers.
my @e_io;

# Idle handlers.
my @e_idle;

# ID counter.
my $next_id = 1;

# Replacable event core.
my $core;


=item init()

Initializes the event system.  This must be called before any other event
calls.

=cut

sub init {
    $core = TLily::Event::Core->new;

    TLily::Registrar::class_r(name_event => \&event_u);
    TLily::Registrar::class_r(io_event   => \&io_u);
    TLily::Registrar::class_r(time_event => \&time_u);
    TLily::Registrar::class_r(idle_event => \&idle_u);
}


=item send()

Send a named event.  Takes either a hash reference, or a hash.

    TLily::Event::send(type => 'text', 'text' => 'foo');

=cut

# Send an event.
sub send {
    my $e = (@_ == 1) ? shift : {@_};
    croak "Event sent without \"type\"." unless ($e->{type});
    push @queue, $e;
}


=item keepalive()

Event handlers are killed if they take more than five seconds to complete.
Call keepalive to give a handler more time.  If called with an argument,
the handler will be killed if it takes more than that number of seconds
to complete.

=cut

sub keepalive {
    my($t) = @_;
    alarm($t || 0);
}


=item event_r()

Register a named event handler.  Takes either a hash reference, or a hash.
Options are:

=over

=item type

The type of event handled by this handler: may be an event type, or 'all'.

=item order

The priority of the handler: either 'before', 'during', or 'after'.

=item call

The handler function.  This function will be called with an event and the
handler as its arguments.

=back

=cut

# Register a new named event handler.
sub event_r {
    my $h = (@_ == 1) ? shift : {@_};
    my %order = (before => 1, during => 2, after => 3);
    
    # The default order is 'during'.
    $h->{order} ||= 'during';
    
    # Sanity check.
    croak "Handler registered without \"call\"." unless ($h->{call});
    croak "Handler registered without \"type\"." unless ($h->{type});
    croak "Handler registered with odd order \"$h->{order}\"."
      unless ($order{$h->{order}});
    
    $h->{id} = $next_id++;
    @e_name = sort {$order{$a->{order}} <=> $order{$b->{order}}}
      (@e_name, $h);
    
    $h->{registrar} = TLily::Registrar::default();
    TLily::Registrar::add("name_event", $h->{id});
    return $h->{id};
}


=item event_u()

Unregister a named event handler.

=cut

# Deregister a named event handler.
sub event_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    @e_name = grep { $_->{id} != $id } @e_name;
    TLily::Registrar::remove("name_event", $id);
    return;
}


# Register a new IO event handler.
sub io_r {
    my $h = (@_ == 1) ? shift : {@_};
    
    # Sanity check.
    croak "Handler registered without \"call\"."   unless ($h->{call});
    croak "Handler registered without \"mode\"."   unless ($h->{mode});
    croak "Handler registered with odd mode."
      unless ($h->{mode} =~ /[rwx]/);
    croak "Handler registered without \"handle\"." unless ($h->{handle});
    
    my $n = fileno($h->{handle});
    croak "Handler registered with bad handle."    unless(defined $n);
    
    # Hang on to the fileno.  We can't trust the handle to still be
    # valid when the caller unregisters the handler: once the handle
    # has been closed, the fileno goes away.
    $h->{'fileno'} = $n;
    
    $h->{id} = $next_id++;
    push @e_io, $h;
    
    $core->io_r($n, $h->{mode});
    
    $h->{registrar} = TLily::Registrar::default();
    TLily::Registrar::add("io_event", $h->{id});
    return $h->{id};
}


# Deregister an IO event handler.
sub io_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    
    my($io, @io);
    foreach $io (@e_io) {
	if ($io->{id} == $id) {
	    $core->io_u($io->{'fileno'},
			$io->{mode});
	} else {
	    push @io, $io;
	}
    }
    @e_io = @io;
    
    TLily::Registrar::remove("io_event", $id);
    return;
}


# Register a new timed event handler.
sub time_r {
    my $h = (@_ == 1) ? shift : {@_};
    
    # Sanity check.
    croak "Handler registered without \"call\"." unless ($h->{call});
    croak "Handler registered with insane interval."
      if ($h->{interval} && $h->{interval} <= 0);
    
    $h->{'after'} = 0 if (!defined($h->{'time'}) &&
			  !defined($h->{after}) &&
			  defined($h->{interval}));
    
    # Run after N seconds.
    if (defined($h->{after})) {
	$h->{'time'} = time + $h->{after};
    }
    # Oops.
    elsif (!defined($h->{'time'})) {
	croak "Handler registered without \"after\", \"time\", or \"interval\".";
    }
    
    $h->{id} = $next_id++;
    @e_time = sort { $a->{'time'} <=> $b->{'time'} } (@e_time, $h);
    
    $h->{registrar} = TLily::Registrar::default();
    TLily::Registrar::add("time_event", $h->{id});
    return $h->{id};
}


# Deregister a timed event handler.
sub time_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    @e_time = grep { $_->{id} != $id } @e_time;
    TLily::Registrar::remove("time_event", $id);
    return;
}


# Register a new idle event handler.
sub idle_r {
    my $h = (@_ == 1) ? shift : {@_};
    
    # Sanity check.
    croak "Handler registered without \"call\"." unless ($h->{call});

    $h->{id} = $next_id++;
    push @e_idle, $h;
    TLily::Registrar::add("idle_event", $h->{id});
    return;
}


# Deregister an idle event handler.
sub idle_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    @e_idle = grep { $_->{id} != $id } @e_idle;
    TLily::Registrar::remove("idle_event", $id);
    return;
}


sub invoke {
    my $h = shift;
    $h->{registrar}->push_default if ($h->{registrar});
    unshift @_, $h->{obj} if ($h->{obj});
    my $rc;
    eval {
	local $SIG{ALRM} = sub { die "event timeout\n"; };
	alarm(5);
	$rc = $h->{call}->(@_);
	alarm(0);
    };
    warn "$h->{type} handler caused error: $@" if ($@);
    $h->{registrar}->pop_default  if ($h->{registrar});
    return $rc;
}


sub loop_once {
    # Named events.
  EVENT:
    while (my $e = shift @queue) {
	foreach my $h (@e_name) {
	    if ($e->{type} eq $h->{type} or $h->{type} eq 'all') {
		my $rc = invoke($h, $e, $h);
		if (defined($rc) && ($rc != 0) && ($rc != 1)) {
		    warn "Event handler returned $rc.";
		}
		next EVENT if ($rc);
	    }
	}
    }
    
    # Timed events.
    # This is a tad ugly -- rewrite if you're feeling bored. -DN
    my $time = time;
    my $sort = 0;
    foreach my $h (@e_time) {
	if ($h->{'time'} <= $time) {
	    invoke($h, $h);
	    if ($h->{interval}) {
		$h->{'time'} += $h->{interval};
		$sort = 1;
	    } else {
		$h->{registrar}->remove("event", $h->{id})
		  if ($h->{registrar});
	    }
	}
    }
    @e_time = grep { $_->{'time'} > $time } @e_time;
    
    if ($sort) {
	@e_time = sort { $a->{'time'} <=> $b->{'time'} } @e_time;
    }
    
    my $timeout;
    if (@e_idle) {
	$timeout = 0;
    } elsif ($e_time[0]) {
	$timeout = $e_time[0]->{'time'} - $time;
	$timeout = 0 if ($timeout < 0);
    }
    
    # IO events.
    my($r, $w, $e, $n) = $core->run($timeout);
    foreach my $h (@e_io) {
	if (vec($r, fileno($h->{handle}), 1) && $h->{mode} =~ /r/) {
	    invoke($h, 'r', $h);
	} elsif (vec($w, fileno($h->{handle}), 1) && $h->{mode} =~ /w/) {
	    invoke($h, 'w', $h);
	} elsif (vec($e, fileno($h->{handle}), 1) && $h->{mode} =~ /e/) {
	    invoke($h, 'e', $h);
	}
    }

    foreach my $h (@e_idle) {
	invoke($h, $h);
    }
}


sub loop {
    loop_once while (1);
}

1;


__END__

