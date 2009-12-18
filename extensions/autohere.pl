# -*- Perl -*-
# $Id$

use strict;

TLily::Event::event_r(type  => "user_input",
	  		  order => "before",
			  call  => \&autohere_handler);

shelp_r("autohere","Make user 'here' when they send messages");

my $help =<<HELP;
This extension will automatically send a /here command when you are away
and send a public or private message.
HELP
help_r("autohere",$help);

sub autohere_handler {
    my($e, $h) = @_;

    # If we aren't 'away' on the current server, don't worry.
    my $server = TLily::Server::active();
    next unless $server;

    my $name = $server->user_name();
    next unless $name;

    my %state = $server->state(NAME => $name);
    next if $state{STATE} ne 'away';
    

    # Test for a send.
    next unless $e->{text} =~ m/^([^@;:=\s]+)[:;]/;


    # Okay, it was a send, and we were away.  Send a '/here'.
    $server->cmd_process('/here', sub {;});

    return 0;
}
