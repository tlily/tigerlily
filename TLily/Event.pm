package LC::Event::Core;

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



package LC::Event;

use strict;
use Carp;
use LC::Registrar;


sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	# Queue of waiting events.
	$self->{queue}   = [];

	# Priority-sorted list of event handlers.
	$self->{e_name}  = [];

	# Time-sorted list of timed handlers.
	$self->{e_time}  = [];

	# IO handlers.
	$self->{e_io}    = [];

	# ID counter.
	$self->{id}      = 1;

	# Replacable event core.
	$self->{core}    = LC::Event::Core->new;

	LC::Registrar::class_r(name_event => sub { $self->event_u(@_) });
	LC::Registrar::class_r(io_event   => sub { $self->io_u(@_) });
	LC::Registrar::class_r(time_event => sub { $self->time_u(@_) });

	bless $self, $class;
}


# Send an event.
sub send {
	my $self = shift;
	my $e = (@_ == 1) ? shift : {@_};
	croak "Event sent without \"type\"." unless ($e->{type});
	push @{$self->{queue}}, $e;
}


# Register a new named event handler.
sub event_r {
	my $self = shift;
	my $h = (@_ == 1) ? shift : {@_};
	my %order = (before => 1, during => 2, after => 3);

	# The default order is 'during'.
	$h->{order} ||= 'during';

	# Sanity check.
	croak "Handler registered without \"call\"." unless ($h->{call});
	croak "Handler registered without \"type\"." unless ($h->{type});
	croak "Handler registered with odd order \"$h->{order}\"."
	  unless ($order{$h->{order}});

	$h->{id} = $self->{id}++;
	@{$self->{e_name}} = sort {$order{$a->{order}} <=> $order{$b->{order}}}
	  (@{$self->{e_name}}, $h);

	$h->{registrar} = LC::Registrar::default();
	LC::Registrar::add("name_event", $h->{id});
	return $h->{id};
}


# Deregister a named event handler.
sub event_u {
	my($self, $id) = @_;
	$id = $id->{id} if (ref $id);
	@{$self->{e_name}} = grep { $_->{id} != $id } @{$self->{e_name}};
	LC::Registrar::remove("name_event", $id);
	return;
}


# Register a new IO event handler.
sub io_r {
	my $self = shift;
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

	$h->{id} = $self->{id}++;
	push @{$self->{e_io}}, $h;

	$self->{core}->io_r($n, $h->{mode});

	$h->{registrar} = LC::Registrar::default();
	LC::Registrar::add("io_event", $h->{id});
	return $h->{id};
}


# Deregister an IO event handler.
sub io_u {
	my($self, $id) = @_;
	$id = $id->{id} if (ref $id);

	my($io, @io);
	foreach $io (@{$self->{e_io}}) {
		if ($io->{id} == $id) {
			$self->{core}->io_u($io->{'fileno'},
					    $io->{mode});
		} else {
			push @io, $io;
		}
	}
	@{$self->{e_io}} = @io;

	LC::Registrar::remove("io_event", $id);
	return;
}


# Register a new timed event handler.
sub time_r {
	my $self = shift;
	my $h = (@_ == 1) ? shift : {@_};

	# Sanity check.
	croak "Handler registered without \"call\"." unless ($h->{call});
	croak "Handler registered with insane interval."
	  if ($h->{interval} && $h->{interval} <= 0);

	# Run after N seconds.
	if (defined($h->{after})) {
		$h->{'time'} = time + $h->{after};
	}
	# Oops.
	elsif (!defined($h->{'time'})) {
		croak "Handler registered without \"after\" or \"time\".";
	}

	$h->{id} = $self->{id}++;
	@{$self->{e_time}} =
	  sort { $a->{'time'} <=> $b->{'time'} } (@{$self->{e_time}}, $h);

	$h->{registrar} = LC::Registrar::default();
	LC::Registrar::add("time_event", $h->{id});
	return $h->{id};
}


# Deregister a timed event handler.
sub time_u {
	my($self, $id) = @_;
	$id = $id->{id} if (ref $id);
	@{$self->{e_time}} = grep { $_->{id} != $id } @{$self->{e_time}};
	LC::Registrar::remove("time_event", $id);
	return;
}


sub invoke {
	my $h = shift;
	$h->{registrar}->push_default if ($h->{registrar});
	unshift @_, $h->{obj} if ($h->{obj});
	my $rc = $h->{call}->(@_);
	$h->{registrar}->pop_default  if ($h->{registrar});
	return $rc;
}


sub loop_once {
	my($self) = @_;

	# Named events.
      EVENT:
	while (my $e = shift @{$self->{queue}}) {
		foreach my $h (@{$self->{e_name}}) {
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
	foreach my $h (@{$self->{e_time}}) {
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
	@{$self->{e_time}} = grep { $_->{'time'} > $time } @{$self->{e_time}};

	if ($sort) {
		@{$self->{e_time}} =
		  sort { $a->{'time'} <=> $b->{'time'} } @{$self->{e_time}};
	}

	my $timeout;
	if ($self->{e_time}->[0]) {
		$timeout = $self->{e_time}->[0]->{'time'} - $time;
		$timeout = 0 if ($timeout < 0);
	}

	# IO events.
	my($r, $w, $e, $n) = $self->{core}->run($timeout);
	foreach my $h (@{$self->{e_io}}) {
		if (vec($r, fileno($h->{handle}), 1) && $h->{mode} =~ /r/) {
			invoke($h, 'r', $h);
		}
		elsif (vec($w, fileno($h->{handle}), 1) && $h->{mode} =~ /w/) {
			invoke($h, 'w', $h);
		}
		elsif (vec($e, fileno($h->{handle}), 1) && $h->{mode} =~ /e/) {
			invoke($h, 'e', $h);
		}
	}
}


sub loop {
	my($self) = @_;
	while (1) { $self->loop_once; }
}

1;
