#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Event.pm,v 1.31 2000/02/14 23:19:45 tale Exp $

package TLily::Event::Core;

use strict;
use TLily::Config qw(%config);

sub new {
    print STDERR ": TLily::Event::Core::new\n" if $config{ui_debug};
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
    print STDERR ": TLily::Event::Core::io_r\n" if $config{ui_debug};
    my($self, $fileno, $handle, $mode) = @_;
    vec($self->{rbits}, $fileno, 1) = 1 if ($mode =~ /r/);
    vec($self->{wbits}, $fileno, 1) = 1 if ($mode =~ /w/);
    vec($self->{ebits}, $fileno, 1) = 1 if ($mode =~ /e/);
}


sub io_u {
    print STDERR ": TLily::Event::Core::io_u\n" if $config{ui_debug};
    my($self, $fileno, $handle, $mode) = @_;
    vec($self->{rbits}, $fileno, 1) = 0 if ($mode =~ /r/);
    vec($self->{wbits}, $fileno, 1) = 0 if ($mode =~ /w/);
    vec($self->{ebits}, $fileno, 1) = 0 if ($mode =~ /e/);
}


sub run {
    print STDERR ": TLily::Event::Core::run\n" if $config{ui_debug};
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
use TLily::Config qw(%config);
use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(&event_r &event_u);


=head1 NAME

TLily::Event - Event queue.

=head1 SYNOPSIS

use TLily::Event;

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

=back

=head1 FUNCTIONS

=over

=cut

# Queue of waiting events.
my @queue;

# Priority-sorted list of event handlers.
my @e_name;
# List of event handlers to remove
my %e_name_remove;

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
    print STDERR ": TLily::Event::Core::init\n" if $config{ui_debug};
    $core = TLily::Event::Core->new;

    TLily::Registrar::class_r(name_event => \&event_u);
    TLily::Registrar::class_r(io_event   => \&io_u);
    TLily::Registrar::class_r(time_event => \&time_u);
    TLily::Registrar::class_r(idle_event => \&idle_u);
}


=item replace_core()

Replace the Event Core.  Takes an object ref to use as the new core.
The new core must implement the same interface as TLiLy::Event::Core.

=cut

# replace the event core.  It binds the galaxy together, like the Force.
sub replace_core {
    print STDERR ": TLily::Event::replace_core\n" if $config{ui_debug};
    $core = $_[0];
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
use Carp qw(confess);
sub event_u {
    my($id) = @_;   
    $id = $id->{id} if (ref $id);
    $e_name_remove{$id} = 1;
    TLily::Registrar::remove("name_event", $id);
    return;
}


=item io_r()

Register an IO event handler.

=over

=item handle

The filehandle associated with this handler.

=item mode

Mode of the handler: r or w  (read/write)

=item call

The handler function.  This function will be called with an event and the
handler as its arguments.

=back

=cut
sub io_r {
    print STDERR ": TLily::Event::io_r\n" if $config{ui_debug};
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
    
    $h->{'type'} = "IO";

    $h->{id} = $next_id++;
    push @e_io, $h;
    
    print STDERR "handle: ", $h->{handle}, "\n" if $config{ui_debug};
    $core->io_r($n, $h->{handle}, $h->{mode});
    
    $h->{registrar} = TLily::Registrar::default();
    TLily::Registrar::add("io_event", $h->{id});
    return $h->{id};
}


=item io_u()

Unregister an IO event handler.

=cut
sub io_u {
    print STDERR ": TLily::Event::io_u\n" if $config{ui_debug};
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    
    my($io, @io);
    foreach $io (@e_io) {
	if ($io->{id} == $id) {
	    $core->io_u($io->{'fileno'},$io->{handle},$io->{mode});
	} else {
	    push @io, $io;
	}
    }
    @e_io = @io;
    
    TLily::Registrar::remove("io_event", $id);
    return;
}


=item time_r()

Register a timed event handler.

=over 

=item call

The handler function.  This function will be called with an event and the
handler as its arguments.

=item interval

Every <interval> seconds, the event handler will fire.

=item after

After <interval> seconds, the event handler will fire (once)

=back

=cut
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

    $h->{'type'} = "TIMED";
    
    $h->{id} = $next_id++;
    @e_time = sort { $a->{'time'} <=> $b->{'time'} } (@e_time, $h);
    
    $h->{registrar} = TLily::Registrar::default();
    TLily::Registrar::add("time_event", $h->{id});
    return $h->{id};
}


=item time_u()

Unregister a timed event handler.

=cut
sub time_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    @e_time = grep { $_->{id} != $id } @e_time;
    TLily::Registrar::remove("time_event", $id);
    return;
}


=item idle_r()

Register an idle event handler.

=over

=item call

The handler function.  This function will be called with an event and the
handler as its arguments.

=back

=cut
sub idle_r {
    my $h = (@_ == 1) ? shift : {@_};
    
    # Sanity check.
    croak "Handler registered without \"call\"." unless ($h->{call});

    $h->{id} = $next_id++;
    push @e_idle, $h;
    TLily::Registrar::add("idle_event", $h->{id});
    return $h->{id};
}


=item idle_u()

Unregister an idle event handler.

=cut
sub idle_u {
    my($id) = @_;
    $id = $id->{id} if (ref $id);
    @e_idle = grep { $_->{id} != $id } @e_idle;
    TLily::Registrar::remove("idle_event", $id);
    return;
}


=item invoke()

=cut
sub invoke {
    my $h = shift;
    $h->{registrar}->push_default if ($h->{registrar});
    unshift @_, $h->{obj} if ($h->{obj});
    my $rc;
    eval {
	local $SIG{ALRM} = sub { die "event timeout\n"; };
        my $timeout = $config{event_timeout};
        if (! defined($timeout) || $timeout !~ /^\d$/) {
	    if ($^O =~ /cygwin/) {
                $timeout = 60;
	    } else {
                $timeout = 5;
            }

	}
        alarm($timeout);
	$rc = $h->{call}->(@_);
	alarm(0);
    };
    warn "$h->{type} handler caused error: $@" if ($@);
    $h->{registrar}->pop_default  if ($h->{registrar});
    return $rc;
}

=item loop_once()

=cut
#use Data::Dumper;
sub loop_once {
    print STDERR ": TLily::Event::loop_once\n" if $config{ui_debug};
    
    # Timed events.
    # This is a tad ugly -- rewrite if you're feeling bored. -DN
    my $time = time;
    my $sort = 0;
    # BUG: If a timed event is registered while in this loop, there is a
    # very good chance it will be forever lost.  I (DCL) became aware of
    # the problem when changing the keepalive extension to be able to
    # reregister its interval.  The first attempt to do this called time_u
    # to unregister the existing timer and then time_r to register a new
    # one, and the new timer was lost.  (In the new registration, "interval"
    # was set to '2' but "after" not set; I haven't tried to figure out
    # whether that was relevant, though adding "after" also set
    # to 2 did make the problem go away.)
    foreach my $h (@e_time) {
	if ($h->{'time'} <= $time) {
	    invoke($h, $h);
	    if ($h->{interval}) {
		$h->{'time'} += $h->{interval};
		while ($h->{'time'} <= $time) {
		    invoke($h, $h);
		    $h->{'time'} += $h->{interval};
		}
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
    
    # Named events.
  EVENT:
    while (my $e = shift @queue) {
	foreach my $h (@e_name) {
	    next if $e_name_remove{$h->{id}};
	    if ($e->{type} eq $h->{type} or $h->{type} eq 'all') {
		my $rc = invoke($h, $e, $h);
		if (defined($rc) && ($rc != 0) && ($rc != 1)) {
		    warn "Event handler returned $rc.";
#                    warn Dumper($h);
		}
		next EVENT if ($rc);
	    }
	}
    }
    if(%e_name_remove) {
	@e_name = grep { !$e_name_remove{$_->{id}} } @e_name;
	%e_name_remove = ();
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

=item loop()

=cut
sub loop {
    loop_once while (1);
}

1;


__END__

