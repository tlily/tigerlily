#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Server.pm,v 1.14 1999/04/06 03:19:11 josh Exp $

package TLily::Server;

use strict;

use Carp;
#use IO::Socket;
use Socket;
use Fcntl;

use TLily::Event;

=head1 NAME

TLily::Server - Lily server base class

=head1 SYNOPSIS


use TLily::Server();

=head1 DESCRIPTION

The Server module defines a class that represents a tcp connection of
some form.  It includes I/O functions -- protocol specific functions
go in subclasses (such as TLily::Server::SLCP).

new() will call die() on failure, so be sure to catch exceptions if this
matters to you!

=head1 FUNCTIONS

=over 10

=cut

my %server;
my @server; # For ordering.
my $active_server;

=item new(%args)

Creates a new TLily::Server object.  Takes 'host', 'port', and
'protocol' arguments.  The 'protocol' argument is used to determine the
events generated for server data -- the event type will be "protocol_data".

    $serv = TLily::Server->new(protocol => "slcp",
                               host     => "lily",
                               port     => 7777);

=cut

sub new {
    my($proto, %args) = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};

    bless $self, $class;
    
    my $ui = TLily::UI::name($args{ui_name}) if ($args{ui_name});

    croak "required parameter \"host\" missing"
      unless (defined $args{host});
    croak "required parameter \"port\" missing"
      unless (defined $args{port});

    # Generate a unique name for this server object.
    my $name = $args{name};
    $name = "$args{host}:$args{port}" if (!defined($name));
    if ($server{$name}) {
	my $i = 2;
	while ($server{$name."#$i"}) { $i++; }
	$name .= "#$i";
    }

    $self->{name}      = $name;
    $self->{host}      = $args{host};
    $self->{port}      = $args{port};
    $self->{ui_name}   = $args{ui_name};
    $self->{proto}    = defined($args{protocol}) ? $args{protocol}:"server";
    $self->{bytes_in}  = 0;
    $self->{bytes_out} = 0;

    $ui->print("Connecting to $self->{host}, port $self->{port}...");

#    $self->{sock} = IO::Socket::INET->new(PeerAddr => $self->{host},
#					  PeerPort => $self->{port},
#					  Proto    => 'tcp');
    $self->{sock} = contact($self->{host}, $self->{port});
    if (!defined $self->{sock}) {
	$ui->print("failed: $!\n");
	return;
    }

    $ui->print("connected.\n");

    fcntl($self->{sock}, F_SETFL, O_NONBLOCK) or die "fcntl: $!\n";

    $self->{io_id} = TLily::Event::io_r(handle => $self->{sock},
					mode   => 'r',
					obj    => $self,
					call   => \&reader);

    $self->add_server();

    TLily::Event::send(type   => 'server_connected',
		       server => $self);
	
    return $self;
}

=item add_server()

Add the server object to the list of available servers.

=cut

sub add_server {
    my ($self) = @_;
    $server{$self->{name}} = $self;
    push @server, $self;
}


# internal utility function
sub contact {
    my($serv, $port) = @_;

    my($iaddr, $paddr, $proto);
    local *SOCK;

    $port = getservbyname($port, 'tcp') if ($port =~ /\D/);
    croak "No port" unless $port;

    $iaddr = inet_aton($serv);
    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    socket(SOCK, PF_INET, SOCK_STREAM, $proto) or return;
    connect(SOCK, $paddr) or return;
    return *SOCK;
}

=item terminate()

Shuts down a server instance.

=cut

sub terminate {
    my($self) = @_;

    close($self->{sock}) if ($self->{sock});
    $self->{sock} = undef;

    $server{$self->{name}} = undef;
    @server = grep { $_ ne $self } @server;
    $active_server = $server[0] if ($active_server == $self);

    TLily::Event::io_u($self->{io_id});
    
    TLily::Event::send(type   => 'server_disconnected',
		       server => $self);

    return;
}


=item ui_name()

Returns the name of the UI object associated with the server.

=cut

sub ui_name {
    my($self) = @_;
    return $self->{ui_name};
}


=item name()

In a list context, returns all existing servers.

In a scalar context, returns the server with the given name, or the
currently active server if no argument is given.

=cut

sub name {
    return @server if (wantarray);
    shift if (@_ > 1);
    my($a) = @_;
    if (!defined $a) {
	return $active_server;
    } elsif (ref($a)) {
	return $a->{"name"};
    } else {
	return $server{$a};
    }
}


=item activate()

Makes this server object the active one.

=cut

sub activate {
    shift if (@_ > 1);
    $active_server = shift;
    $active_server = undef unless ref($active_server);
}

=item send()

Send a chunk of data to the server, synchronously.  This call will block until
the entire block of data has been written.

    $serv->send("a bunch of stuff to send to the server");

=cut

sub send {
    my $self = shift;
    my $s = join('', @_);

    $self->{bytes_out} += length($s);

    my $written = 0;
    while ($written < length($s)) {
	my $bytes = syswrite($self->{sock}, $s, length($s), $written);
	if (!defined $bytes) {
	    # The following is broken, and must be fixed.
	    #next if ($errno == EAGAIN);
	    die "syswrite: $!\n";
		}
	$written += $bytes;
    }

    return;
}


=item sendln()

Behaves exactly like send(), but sends a crlf pair at the end of the line.

=cut

my $crlf = chr(13).chr(10);
sub sendln {
    my $self = shift;
    # \r\n is non-portable.  Fix, please.
    #$self->send(@_, "\r\n");
    $self->send(@_, $crlf);
}


=head2 HANDLERS

=item reader()

IO Handler to process input from the server.

=cut

sub reader {
    my($self, $mode, $handler) = @_;

    my $buf;
    my $rc = sysread($self->{sock}, $buf, 1024);

    # Error of some kind.
    if ($rc < 0) {
	# The following is broken, and must be fixed.
	#if ($errno != EAGAIN) {
	#	die "sysread: $!\n";
	#}
	# A signal interrupted us -- just fall out, we'll be back.
    }

    # End of line.
    elsif ($rc == 0) {
	my $ui = TLily::UI::name($self->{ui_name}) if ($self->{ui_name});
	$ui->print("*** Lost connection to \"$self->{name}\" ***\n");
	$self->terminate();
    }

    # Data as usual.
    else {
	$self->{bytes_in} += length($buf);
	TLily::Event::send(type   => "$self->{proto}_data",
			   server => $self,
			   data   => $buf);
    }

    return;
}


DESTROY { warn "Server object going down!\n"; }

1;

__END__

=cut
