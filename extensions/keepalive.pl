# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/keepalive.pl,v 1.5 1999/10/03 18:25:51 josh Exp $
#
# keepalive -- periodically ping the server, just to verify our connection
#              is still there.
#

use strict;

shelp_r("keepalive" => "Send periodic pings to the server.");
help_r("keepalive",
'The keepalive extension is useful for maintaining a connection to the
server on links which drop after a period of inactivity.  (Such as when
sitting behind a firewall doing NAT.)  Keepalive will send a "/why" to
the server every few minutes.  There are two configuration variables:

    $keepalive_interval - Specifies the frequency (in seconds) to send pings.
    $keepalive_debug    - Set this to be notified when a ping is sent.');

my $pinging = 0;

sub keepalive {
    my($server, $handler) = @_;

    my $ui = ui_name();

    $ui->printf("(keepalive)\n") if ($config{keepalive_debug});
    if ($pinging == 1) {
	$ui->print("(server not responding)\n");
	$pinging = 2;
    } elsif ($pinging == 0) {
	$pinging = 1;
	$server->cmd_process("/why", sub {
			my($event) = @_;
			$event->{NOTIFY} = 0;
			return unless ($event->{type} eq 'endcmd');
			if ($pinging == 2) {
			    $ui->print("(server is responding again)\n");
			}
			$pinging = 0;
			return;
		    });
    }
    
    return 0;
}


if ($config{keepalive_interval} <= 0) {
    $config{keepalive_interval} = 600;
}

TLily::Event::time_r(interval => $config{keepalive_interval},
		     call => sub { keepalive(active_server(),@_) });
