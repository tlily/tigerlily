# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

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

BEGIN {
    # Thanks again, POE::Kernel!

    # http://support.microsoft.com/support/kb/articles/Q150/5/37.asp
    if ($^O eq 'MSWin32') {
        eval '*EINPROGRESS = sub { 10036 };';
        eval '*EWOULDBLOCK = sub { 10035 };';
    }
}


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

    $ui->print("Connecting to $self->{host}, port $self->{port}...") if $ui;

#    $self->{sock} = IO::Socket::INET->new(PeerAddr => $self->{host},
#					  PeerPort => $self->{port},
#					  Proto    => 'tcp');
    eval { $self->{sock} = contact($self->{host}, $self->{port}); };
    if ($@) {
	$ui->print("failed: $@") if $ui;
	return;
    }

    $ui->print("connected.\n") if $ui;

    tl_nonblocking($self->{sock});

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

sub remove_server {
    my($self) = @_;
    foreach (@{$self->{names}}) { delete $server{$_} };
    return;
}


# internal utility function
sub contact {
    my($serv, $port) = @_;

    my($iaddr, $paddr, $proto);
    local *SOCK;

    $port = getservbyname($port, 'tcp') if ($port =~ /\D/);
    croak "No port" unless $port; 
    $iaddr = inet_aton($serv);
    die "No such host or address\n" unless defined($iaddr);

    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    socket(SOCK, PF_INET, SOCK_STREAM, $proto) or die "$!\n";
    connect(SOCK, $paddr) or die "$!\n";
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

If given an argument, will attempt to add that name as an alias for
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

    my $target = shift; 

    if (defined ($target)) {
 
        return $server{$target} if exists($server{$target});
  
        ## allow a case insensitive match, but only if it's unique.
        my @matches;
        foreach my $potential (@server) {
            if (lc($potential->name) eq lc($target)) {
                push @matches,$potential;
            }     
        }
        if (@matches == 1) {
            return $matches[0];
        } else {
            return undef;
        }
    }
 
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

    if ($TLily::Config::config{send_debug}) {
        my $t = $s;
        $t =~ s/\n/\\n/g;
        $t =~ s/\r/\\r/g;
        $t =~ s/\t/\\t/g;
        $t =~ s/([\x00-\x17\x7f-\xff])/"\\x " . printf("%x", $1)/ge;
        TLily::UI::name($self->{ui_name})->print
					("Send $self->{ui_name}: $t\n");
    }

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


=item send_message($recips, $separator, $message)

Send a message (a user send) to the server.   $recips is comma-separated.

=cut

sub send_message {
    my ($self, $recips, $separator, $message) = @_;

    $self->sendln($recips, $separator, $message);
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

    # Interrupted by a signal or would block
    return if (!defined($rc) && $! == $::EAGAIN);

    # Would block.  (used only on win32 right now)
    return if (($^O eq "MSWin32") && (!defined($rc) && $! == &EWOULDBLOCK));

    # End of line.
    if (!defined($rc) || $rc == 0) {
	my $ui = TLily::UI::name($self->{"ui_name"}) if ($self->{"ui_name"});
	$ui->print("*** Lost connection to \"" . $self->{"name"} . "\" ***\n") if $ui;
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


=item tl_nonblocking()

Make a socket non-blocking, cross-platformly.
  
This code is lifted from POE::Kernel.  Very cool.  I would not have
figured this out.

=cut

sub tl_nonblocking {
    my ($handle) = @_;

    if ($^O eq 'MSWin32') {
        my $set_it = "1";
          
        # 126 is FIONBIO (some docs say 0x7F << 16)
        ioctl($handle,
              0x80000000 | (4 << 16) |
              (ord('f') << 8) | 126,
              $set_it) or die "Can't set the handle non-blocking: $!";

     } else {

         # Make the handle stop blocking, the POSIX way.
            
         my $flags = fcntl($handle, F_GETFL, 0)
             or croak "fcntl fails with F_GETFL: $!\n";
         fcntl($handle, F_SETFL, $flags | O_NONBLOCK)
             or croak "fcntl fails with F_SETFL: $!\n";
     }
}


#DESTROY { warn "Server object going down!\n"; }

1;

__END__

=cut