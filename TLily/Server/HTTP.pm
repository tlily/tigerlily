#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Server/Attic/HTTP.pm,v 1.2 1999/08/31 00:04:31 steve Exp $

package TLily::Server::HTTP;

use strict;
use vars qw(@ISA);

use TLily::Server;
use Carp;

@ISA = qw(TLily::Server);

sub new {
    my ($proto, %args) = @_;
    my $class = ref($proto) || $proto;
	
    $args{port}   ||= 80;
    $args{protocol} = "http";
	
    croak "required parameter \"url\" missing"
      unless (defined $args{url});
	
    if ($args{url} =~ m|^http://([^:]+)(?::(\d+))?(/[/\S]+)$|) {  # A full url
		$args{port} = $2 if defined $2;
		$args{url} = $3;
		$args{host} = $1;
    }
    unless (defined $args{filename}) {
		my @t = split m|/|, $args{url};
		$args{filename} = pop @t;
	}
	
    TLily::Event::event_r (type => 'server_connected',
						   call => \&send_url);
	
    my $self = $class->SUPER::new(%args);
	
    $self->{filename} = $args{filename};
    $self->{url} = $args{url};
	
    bless $self, $class;
}

sub send_url {
    my ($event, $handler) = @_;

    my $ui = TLily::UI::name();

    return unless exists ($event->{server}->{url});

    $event->{server}->send("GET ", $event->{server}->{url},
			   " HTTP/1.0\r\n\r\n");

    return;
}

sub DESTROY { };

1;
