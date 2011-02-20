# *-* Perl *-*
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::Daemon;

use strict;
use warnings;

use Socket;
use Fcntl;
use Carp;

=head1 NAME

TLily::Daemon - Tigerlily daemon object

=head1 SYNOPSIS

use TLily::Daemon;

=head1 DESCRIPTION

The Daemon module defines a class that represents listening tcp connections
of some type.  Anything that wants to open a socket for listening should
create a subclass of this class.

=head1 FUNCTIONS

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
    $name = "listen:$args{port}" if (!defined($name));
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
#    $self->{bytes_in}  = 0;
#    $self->{bytes_out} = 0;

    local (*SOCK);
    my $p = getprotobyname($self->{type});
    my $t = (($self->{type} eq 'udp') ? SOCK_DGRAM : SOCK_STREAM);
    if (!(socket(SOCK, PF_INET, $t, $p))) {
        warn "socket: $!";
        return;
    }

    $self->{sock} = *SOCK;

    if (!(setsockopt($self->{sock}, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)))) {
        warn "setsockopt: $!";
        close $self->{sock};
        return;
    }
    if (!(bind($self->{sock}, sockaddr_in($self->{port}, INADDR_ANY)))) {
#    warn "bind: $!";
        close $self->{sock};
        return;
    }
    if (!(fcntl($self->{sock}, F_SETFL, O_NONBLOCK))) {
        warn "fcntl: $!";
        close $self->{sock};
        return;
    }
    if (!(listen($self->{sock}, $self->{queuelen}))) {
        warn "listen: $!";
        close $self->{sock};
        return;
    }

    my $ui = TLily::UI::name();
    $ui->print("Listening on port " . $self->{port} . "\n");

    $self->{io_id} = TLily::Event::io_r (handle => $self->{sock},
                                         mode   => 'r',
                                         obj    => $self,
                                         call   => \&acceptor);
    $self->{active} = 1;

    $daemon{$name} = $self;

    return bless $self, $class;
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
    $cxn->close() if defined $cxn;
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
    return if (!defined $a);
    return $a->{"name"} if ref($a);
    return $daemon{$a};
}

sub cxn_u {
    my ($self, $obj) = @_;

    return unless $self->{connected};

    $self->{connected} = grep { $_ != $obj } @{$self->{connected}};
    $self->{connected} = () unless $self->{connected};
    return;
}

sub acceptor {
    my ($self, $mode, $handler) = @_;

    local *NEWSOCK;
    return unless (accept(NEWSOCK, $self->{sock}));

    # Force subclasses to deal with nonblocking sockets.  That's just life.
    fcntl(NEWSOCK, F_SETFL, O_NONBLOCK);

    my $class = ref($self);
    my $obj =
      defined($self->{connection_ob}) ? $self->{connection_ob} :
    "${class}::Connection";
    my $sock = *NEWSOCK;

    my $newobj =
      eval "${obj}->new('sock' => $sock , 'proto' => '$self->{proto}')";
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
