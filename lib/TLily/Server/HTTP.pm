#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2005  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /data/cvs/lily/tigerlily2/TLily/Server/HTTP.pm,v 1.5 2001/01/26 03:01:51 neild Exp $

package TLily::Server::HTTP;

use strict;
use vars qw(@ISA);

use TLily::Server;
use Carp;

@ISA = qw(TLily::Server);

sub new {
    my ($proto, %args) = @_;
    my $class = ref($proto) || $proto;


    croak "required parameter \"url\" missing"
      unless (defined $args{url});

    # WJC: "fixed" re so that urls with path info are preserved.
    #
    # The path is optional, and may be just "/". It used to be (/[/\S]+), which
    # needs a slash and then at least one more character -- so "http://host/"
    # and "http://host" did not match at all, {host} was never set, and
    # TLily::Server::new croaked "required parameter host missing". Fetching
    # the front page of anything was impossible.
    if ($args{url} =~ m|^(https?)://([^/:]+)(?::(\d+))?(/\S*)?$|) {  # A full url
        $args{port} = $3 if defined $3;
        $args{url} = (defined $4 && length $4) ? $4 : "/";
        $args{host} = $2;
        $args{protocol} = $1;
        $args{port} = 443 if ($args{protocol} eq "https" && !defined $args{port});
    }
    $args{protocol} = "http" unless defined $args{protocol};
    $args{port}   ||= 80;

    # An https URL needs TLS on the port as given. {secure} is the wrong switch
    # for that: it means lily's pinned SSL on the port above this one, which
    # for 443 would dial 444 and pin every host we ever fetched from.
    #
    # Setting both explicitly also stops a fetch inheriting whatever the user's
    # lily connection uses. TLily::Server defaults {secure} to the global
    # config, so anyone connected to lily over SSL has been having plain http
    # fetches attempted over SSL, against the wrong port, all along.
    $args{tls}    = ($args{protocol} eq "https") ? 1 : 0;
    $args{secure} = 0;

    unless (defined $args{filename}) {
        my @t = split m|/|, $args{url};
        # A bare "/" has no last component to name; keep this defined rather
        # than handing callers an undef they never used to get.
        $args{filename} = @t ? pop @t : "index.html";
    }

    my $self = $class->SUPER::new(%args);

    $self->{handler} = TLily::Event::event_r (type => 'server_connected',
                                              call => \&send_url);

    $self->{filename} = $args{filename};
    $self->{url} = $args{url};
    $self->{callback} = $args{callback} if (defined($args{callback}));

    bless $self, $class;
}

sub send_url {
    my ($event, $handler) = @_;

    #Since we got this far, we don't need the server_connected callback anymore.
    TLily::Event::event_u($event->{server}->{handler});

    return unless exists ($event->{server}->{url});

    my $request = "GET " . $event->{server}->{url} . " HTTP/1.0\r\n";
    $request .= "USER-AGENT: Tigerlily\r\n";
    $request .= "host: " . $event->{server}->{host} . "\r\n";
    $request .= "\r\n";
    $event->{server}->send($request);

    return;
}

# don't track the HTTP servers (our parent class does, and that would
# just keep them around) A better solution might be to have the notion of
# transient servers.

sub add_server {};

sub DESTROY {
 # XXX - This never seems to print.
 #print "DESTROYING HTTP SERVER\n";
};

1;
