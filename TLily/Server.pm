#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Server.pm,v 1.26 2001/01/26 03:01:48 neild Exp $

package TLily::Server;

use strict;

use Carp;
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

    if (!defined($name)) {
        $name = "$args{host}";
        $name =~ s/^([^\.]+).*$/$1/;
    }
    if ($server{$name}) {
	my $i = 2;
	while ($server{$name."#$i"}) { $i++; }
	$name .= "#$i";
    }

    $self->{name}      = $name if (defined($args{name}));
    # NOTE: If you add other names, make _sure_ that those names aren't
    # already taken by other server objects, otherwise bad stuff will happen.
    @{$self->{names}}  = ($name);
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
    # Potential problem if one of the names here conflicts with
    # one already taken.  So don't call this from anywhere but new().
    foreach (@{$self->{names}}) {
        $server{$_} = $self;
    }
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

    foreach (@{$self->{names}}) { delete $server{$_} }; #DONE
    @server = grep { $_ ne $self } @server;
    activate($server[0]) if ($active_server == $self);

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

If given an arguement, will attempt to add that name as an alias for
this server.  It returns 1 if it was successful, 0 otherwise.

If no argument is given, in a scalar context it will return the primary
(canonical) name for the server, while in a list context it will return
the list of names of the server.

=cut

sub name {
    my($self, $name) = @_;

    if (defined($name)) {
        if (defined($server{$name})) {
            my $i = 2;
            while ($server{$name."#$i"}) { $i++; }
            $name .= "#$i";
        }
        $server{$name} = $self;
        if (!defined($self->{name})) {
            $self->{name} = $name;
            unshift @{$self->{names}}, $name;
        } else {
            push @{$self->{names}}, $name;
        }
        return 1;
    } else {
        return $self->{names}[0] if (!wantarray);
        return @{$self->{names}};
    }
}

=item active()

If called as a function with no arguments, returns the currently active
server.

If called as a function with a server ref argument, or as a method of a
server ref, returns a boolean indicating whether that server is the
currently active one.

=cut

sub active {
    return($_[0] == $active_server) if (ref($_[0]));
    return $active_server;
}

=item find()

Given a string, will look for that string in the server names hash, and,
if it finds a server object, will return the ref; will return undef
otherwise.

Given no arguments, will return the list of servers currently open.

=cut

sub find {
    return $server{$_[0]} if defined($_[0]);
    return @server;
}


=item activate()

Makes this server object the active one.

=cut

sub activate {
    shift if (@_ > 1);
    $active_server = shift;
    $active_server = undef unless ref($active_server);
    TLily::Event::send(type => 'server_activate', 'server' => $active_server);
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
	    #next if ($errno == $::EAGAIN);
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
    $self->send(@_, $crlf);
}


=item command()

Processes a user command.  The Server base class provides default processing
for commands -- currently, it recognizes sends.  Returns true if the command
was recognized, false otherwise.

=cut

sub command {
    my($self, $ui, $text) = @_;

    # Sends.
    if ($text =~ /^([^\s;:]*)([;:])(.*)/) {
        TLily::Event::send(type   => 'user_send',
                           server => $self,
                           RECIPS => [split /,/, $1],
                           dtype  => $2,
                           text   => $3);
	return 1;
    }

    return;
}


=head2 HANDLERS

=item reader()

IO Handler to process input from the server.

=cut

sub reader {
    my($self, $mode, $handler) = @_;

    my $buf;
    my $rc = sysread($self->{sock}, $buf, 1024);

    # Interrupted by a signal.
    return if (!defined($rc) && $! == $::EAGAIN);

    # End of line.
    if (!defined($rc) || $rc == 0) {
	my $ui = TLily::UI::name($self->{"ui_name"}) if ($self->{"ui_name"});
	$ui->print("*** Lost connection to \"" . $self->{"name"} . "\" ***\n");
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


#DESTROY { warn "Server object going down!\n"; }

1;

__END__

=cut
