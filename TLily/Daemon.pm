# *-* Perl *-*
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Daemon.pm,v 1.1 1999/03/22 23:45:58 steve Exp $

package TLily::Daemon;

use strict;

use Socket;
use Fcntl;
use Carp;

=head1 NAME

TLily::Daemon - Tigerlily daemon object

=head1 DESCRIPTION

The Daemon module defines a class that represents listening tcp connections
of some type.  Anything that wants to open a socket for listening should
create a subclass of this class.

=head2 Functions
=over 10

=cut

my %daemon;

=item new(%args)

Creates a new TLily::Daemon object.  Takes 'port', 'type', 'protocol',
and 'queuelen' arguments.  The 'protocol' argument is used to determine the
events generated for data -- the event type will be "protocol_data".
The 'type' argument is optional, and specifies the type of socket to create
(udp or tcp).  It defaults to tcp.  The 'queuelen' argument is also optional,
and specifies the number of incoming connections allowed in the listen
queue.  This defaults to 5.

    $serv = TLily::Daemon->new(protocol => "http",
							   port     => "31337");

This will return undef if it was unable to listen on the requested port.

=cut

sub new {
	my ($proto, %args) = @_;
	my $class = ref($proto) || $proto;
	my $self = {};

	croak "Required parameter \"port\" not found!" unless $args{port};

	# Get a name for this server
	# This is stolen (cut-n-pasted) from Server.pm
	my $name = $args{name};
    $name = "$args{port}" if (!defined($name));
    if ($daemon{$name}) {
		my $i = 2;
		while ($daemon{$name."#$i"}) { $i++; }
		$name .= "#$i";
    }

	$self->{name}      = $name;
	$self->{port}      = $args{port};
	$self->{proto}     = defined($args{protocol}) ? $args{protocol} : "daemon";
	$self->{queuelen}  = $args{queuelen} ? $args{queuelen} : 5;
	$self->{type}      = defined($args{type}) ? $args{type} : 'tcp';
	$self->{connected} = ();
#	$self->{bytes_in}  = 0;
#	$self->{bytes_out} = 0;

	local (*SOCK);
	my $p = getprotobyname($self->{type});
	my $t = (($self->{type} eq 'udp') ? SOCK_DGRAM : SOCK_STREAM);
	if (!(socket(SOCK, PF_INET, $t, $p))) {
		warn "socket: $!";
		return undef;
	}

	$self->{sock} = *SOCK;

	if (!(setsockopt(SOCK, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)))) {
		warn "setsockopt: $!";
		close $self->{sock};
		return undef;
	}
	if (!(bind(SOCK, sockaddr_in($self->{port}, INADDR_ANY)))) {
#		warn "bind: $!";
		close $self->{sock};
		return undef;
	}
	if (!(fcntl($self->{sock}, F_SETFL, O_NONBLOCK))) {
		warn "fcntl: $!";
		close $self->{sock};
		return undef;
	}
 	if (!(listen(SOCK, $self->{queuelen}))) {
 		warn "listen: $!";
 		close $self->{sock};
 		return undef;
 	}

	my $ui = TLily::UI::name();
	$ui->print("Listening on port " . $self->{port} . "\n");
#	return bless $self, $class;

	$self->{io_id} = TLily::Event::io_r (handle => $self->{sock},
										 mode   => 'r',
										 obj    => $self,
										 call   => \&acceptor);
	$self->{active} = 1;
	
	$daemon{$name} = $self;

	bless $self, $class;
}

=item terminate()

Stops a listening daemon

=cut

sub terminate {
	my ($self) = @_;

	close($self->{sock}) if ($self->{sock});
	$self->{sock} = undef;

	$daemon{$self->{name}} = undef;

	TLily::Event::io_u($self->{io_id});

	foreach my $cxn ($self->{connected}) {
		$cxn->close();
	}
	$self->{connected} = undef;

	return;
}

=item name()

In a list context, returns all existing daemons.

In a scalar context, returns the server with the given name, or
undef if no argument is given.

=cut

sub name {
	return values(%daemon) if (wantarray);
	shift if (@_ > 1);
	my ($a) = @_;
	return undef if (!defined $a);
	return $a->{"name"} if ref($a);
	return $daemon{$a};
}

sub cxn_u {
	my ($self, $obj) = @_;
	
	return unless $self->{connected};

	$self->{connected} = grep { $_ != $obj } @{$self->{connected}};
	$self->{connected} = () unless $self->{connected};
}

sub acceptor {
	my ($self, $mode, $handler) = @_;

# 	my $ui = TLily::UI::name();

	local *NEWSOCK;
	return unless (accept(NEWSOCK, $self->{sock}));

#	$ui->print("Accepted connection\n");
	# Force subclasses to deal with nonblocking sockets.  That's just life.
	fcntl(NEWSOCK, F_SETFL, O_NONBLOCK);

	my $class = ref($self);
	my $obj = 
	  defined($self->{connection_ob}) ? $self->{connection_ob} :
		"${class}::Core";
	my $sock = *NEWSOCK;

	my $newobj = 
	  eval "${obj}->new('sock' => \$sock , 'proto' => '$self->{proto}')";
	if (!defined($newobj)) {
		if ($@) {
			warn $@;
			return;
		}
		warn "${obj}->new() returned undefined value!";
		close NEWSOCK;
		return;
	}

	$newobj->{daemon} = $self;

	push @{$self->{connected}}, $newobj;
	return;
}

1;
