# -*- Perl -*-
# $Id$
#
# keepalive -- periodically ping the server, just to verify our connection
#              is still there.
#

use strict;
use warnings;

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
    $keepalive_debug    - Set this to be notified when a ping is sent.

In addition, you may modify the keepalive interval with the %keepalive
command.');


if (! exists $config{keepalive_interval} or $config{keepalive_interval} <= 0) {
    $config{keepalive_interval} = 150; # 2.5 minutes
}

##############################################################################
# Keepalive state.

# Which servers are we pinging?  Maps server name to state:
#   0 - No outstanding server ping.
#   1 - Ping sent, no response received.
#   2 - No response received to last server ping.
my %pinging;

# When did we last ping a server?
my $last_ping = 0;

# Event ID of our timer.
my $timer_id;


##############################################################################
# Keepalive function -- ping servers

sub keepalive {
    my $ui = ui_name();

    $ui->print("(checking keepalive state)\n")
        if ($config{keepalive_debug});

    foreach my $server (TLily::Server::find()) {
        next unless defined($server);
        my $name = $server->name;

        $pinging{$name} = 0 if ! defined($pinging{$name});

        # 0 - no ping outstanding
        if ($pinging{$name} == 0) {
            $pinging{$name} = 1;
            $ui->print("(sending #\$# ping to $name)\n")
                    if ($config{keepalive_debug});
            $server->sendln('#$# ping');
        }

        # 1 - ping outstanding, carp
        elsif ($pinging{$name} == 1) {
            $ui->print("(server $name not responding)\n");
            $pinging{$name} = 2;
        }
    }

    $last_ping = time;

    return 0;
}

sub keepalive_handle_pong {
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
}

sub keepalive_handle_disconnect {
    my($event) = @_;
    delete $pinging{$event->{server}->name};
    return;
}

event_r(type => 'pong',
        call => \&keepalive_handle_pong);

event_r(type => 'server_disconnected',
        call => \&keepalive_handle_disconnect);


##############################################################################
# Keepalive variable -- reschedule keepalives whenever the interval changes.

sub keepalive_update {
    my($interval) = @_;

    TLily::Event::time_u($timer_id) if $timer_id;
    $timer_id = undef;

    return unless $interval;

    my $after = $last_ping + $interval - time;
    $after = 0 if ($after < 0);
    $timer_id = TLily::Event::time_r(after    => $after,
                                     interval => $interval,
                                     call     => \&keepalive);

    return;
}

TLily::Config::callback_r
  (State     => 'STORE',
   Variable => 'keepalive_interval',
   List     => 'config',
   Call     => sub {my($v,%a)=@_; keepalive_update(${$a{Value}})});


##############################################################################
# Keepalive command

sub keepalive_command {
    my($ui, $args) = @_;

    if ($args =~ /^(off|0)$/i) {
        $ui->print("(disabling keepalive)\n");
        #$config{keepalive_interval} = undef;
        keepalive_update(undef);
    } elsif ($args =~ /^\d+$/) {
        $ui->print("(setting keepalive interval to $args seconds)\n");
        #$config{keepalive_interval} = $args;
        keepalive_update($args);
    } elsif (!$config{keepalive_interval}) {
        $ui->print("(keepalive is currently disabled)\n");
    } else {
        my $interval = $config{keepalive_interval};
        my $next = $last_ping + $interval - time;
        $next = 0 if ($next < 0);

        $ui->print("Pinging servers every $interval seconds.\n");
        $ui->print("Next ping in $next seconds.\n");
        $ui->print("Server status:\n");

        foreach my $server (TLily::Server::find()) {
            next unless defined($server);
            my $name = $server->name;

            $ui->print("$name - ");
            if (!$pinging{$name}) {
                $ui->print("ok\n");
            } elsif ($pinging{$name} == 1) {
                $ui->print("waiting for response\n");
            } elsif ($pinging{$name} == 2) {
                $ui->print("server not responding\n");
            }
        }
    }

    return;
}

command_r(keepalive => \&keepalive_command);


##############################################################################
# Start things up.

keepalive_update($config{keepalive_interval});
