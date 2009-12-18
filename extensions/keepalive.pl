# -*- Perl -*-
# $Id$
#
# keepalive -- periodically ping the server, just to verify our connection
#              is still there.
#

use strict;

shelp_r("keepalive_interval" => "Frequency in seconds of server pings. ",
        "variables");
shelp_r("keepalive_debug" => "If true, notify user when keepalive occurs. ",
        "variables");
shelp_r("keepalive" => "Send periodic pings to the server.");
help_r("keepalive",
'The keepalive extension is useful for maintaining a connection to the
server on links which drop after a period of inactivity.  (Such as when
sitting behind a firewall doing NAT.)  Keepalive will send a "/why" to
the server every few minutes.  There are two configuration variables:

    $keepalive_interval - Specifies the frequency (in seconds) to send pings.
    $keepalive_debug    - Set this to be notified when a ping is sent.');

my %pinging;

my %timer;

sub keepalive {
    my($server, $handler) = @_;

    my $ui = ui_name();
    my $name = $server->name;

    $pinging{$name} = 0 if ! defined($pinging{$name});

    if ($timer{interval} != $config{keepalive_interval}) {
        $timer{interval}  = $config{keepalive_interval};
    }

    $ui->print("(checking keepalive $name)\n") if ($config{keepalive_debug});
    if ($pinging{$name} == 1) {
	$ui->print("(server $name not responding)\n");
	$pinging{$name} = 2;
    } elsif ($pinging{$name} == 0) {
	$pinging{$name} = 1;
	$ui->print("(sending #\$# ping to $name)\n") if ($config{keepalive_debug});	
	$server->sendln('#$# ping');
    }

    return 0;
}

if ($config{keepalive_interval} <= 0) {
    $config{keepalive_interval} = 600;
}

$timer{interval} = $config{keepalive_interval};
$timer{after} = $config{keepalive_interval};
$timer{call} = sub {
    foreach my $server (TLily::Server::find()) {
        next unless defined($server);
        keepalive($server, @_)
    }
};

TLily::Event::time_r(\%timer);

event_r(type => 'pong',
	call => sub {
            my($event) = @_;
	    
	    my $ui = ui_name();	    
            my $name = $event->{server}->name;
	    
            $event->{NOTIFY} = 0;
	    
	    $ui->print("(received %pong from $name)\n") if ($config{keepalive_debug});	
            if ($pinging{$name} == 2) {
                $ui->print("(server $name is responding again)\n");
            }
            $pinging{$name} = 0;
            return;
        });

# Clean up state.
event_r(type => 'server_disconnected',
        call => sub {
            my($event) = @_;

	    $pinging{$event->{server}->name} = 0;
	    return;
	});
