# -*- Perl -*-
# $Id$

use strict;

use TLily::UI;
use TLily::Server::SLCP;
use TLily::Server::AIM;
use TLily::Server::IRC;
use TLily::Event;

=head1 NAME

server.pl - Server interface commands

=head1 DESCRIPTION

This extension contains commands for interfacing with servers.

=head1 COMMANDS

=over 10

=item %connect

Connect to a server.  See "%help %connect".

=item %close

Close a connection to the current active server.  See "%help %close".

=back

=head1 UI COMMANDS

=over 4

=item next-server

Change the current active server to the next server in the list of servers.
Bound to C-q by default.

=cut

sub connect_command {
    my($ui, $arg) = @_;
    my(@argv) = split /\s+/, $arg;
    my $auto_login = 1;
    TLily::Event::keepalive();

    while ((@argv) && ($argv[0] =~ /^-/)) {
	my $opt = shift @argv;
	if ($opt eq "-nologin") {
	    $auto_login = 0;
	} else {
	    $ui->print("(unknown switch \"$opt\")\n");
	    return;
	}
    }

    my $host = shift @argv;
    my ($port, $user, $pass) = @argv;
    my $ssl;

    if (!defined $host) {
	if (!defined($config{server})) {
	    $ui->print("(no default server specified)\n");
	    return;
	}

	$host = $config{server};
	$port = $config{port};
    }

    # Expand host aliases.
    if (!defined($port) && $config{server_info}) {
	foreach my $i (@{$config{server_info}}) {
	    if ($host eq $i->{alias}) {
		($host, $port) = ($i->{host}, $i->{port});
		last;
	    }
	}
    }

    # Pick out autologin information.
    if ($auto_login) {
	if ($config{server_info}) {
	    foreach my $i (@{$config{server_info}}) {
		if ($host eq $i->{host}) {
		    $port = $i->{port} if (!defined $port);
		    if ($port == $i->{port}) {
			($user, $pass) = ($i->{user}, $i->{pass});
			last;
		    }
		}
	    }
	}
    }

    my $class = 'TLily::Server::SLCP';

    if ($host =~ /^aim$/i) {
        $host = "host not used";
        $port = "port not used";
        $class = 'TLily::Server::AIM';
        ($user, $pass) = @argv;

    } elsif ($host =~ /^aim:([^\:]+):([^\:]+)/i) {
        $host = "host not used";
        $port = "port not used";
        $class = 'TLily::Server::AIM';
        $user = $1; $pass = $2;
    } elsif ($host =~ /^irc(s?):([^\:]+):([^\:]+)$/i) {
        $ssl = $1;
        $host = $2;
        $user = $3;
        $pass = "pass not implemented";
        $class = 'TLily::Server::IRC';
    }

    my $server = $class->new(host      => $host,
                             port      => $port,
                             ssl       => $ssl,
                             user      => $user,
                             password  => $pass,
                             'ui_name' => $ui->name);
    return unless $server;

    $server->activate();
}
command_r('connect' => \&connect_command);
shelp_r('connect' => "Connect to a server.");
help_r('connect' => "
Usage: %connect [host] [port]

Create a new connection to a server.

(See also: %close)
");


sub close_command {
    my($ui, $arg) = @_;
    my(@argv) = split /\s+/, $arg;
    TLily::Event::keepalive();

    my $server = active_server();
    if (!$server) {
	$ui->print("(you are not currently connected to a server)\n");
	return;
    }

    $ui->print("(closing connection to \"", scalar($server->name()), "\")\n");
    $server->terminate();
    return;
}
command_r('close' => \&close_command);
shelp_r('close' => "Close the connection to the current server.");
help_r('close' => "
Usage: %close

Close the connection to the current server.
");


sub next_server {
    my($ui, $command, $key) = @_;

    my @server = TLily::Server::find();
    my $server = active_server() || $server[-1];

    my $idx = 0;
    foreach (@server) {
	last if ($_ == $server);
	$idx++;
    }

    if (@server == 0) {
        $ui->print("(You are not connected to any servers)\n");
        return;
    }

    $idx = ($idx + 1) % @server;
    my $new_server = $server[$idx];
    $new_server->activate();

    if (@server == 1) {
        return;
    }

    TLily::Event::send({type       => 'server_change',
			old_server => $server,
			server     => $new_server});

    $ui->print("(switching to server \"",
	       scalar($new_server->name()), "\")\n")
      unless $config{switch_quiet};
    return;
}
TLily::UI::command_r("next-server" => \&next_server);
TLily::UI::bind("C-q" => "next-server");


sub send_handler {
    my($e, $h) = @_;

    #
    # Multiserver sends.
    #
    my $ui = $e->{ui} || TLily::UI::name();
    my $active = TLily::Server::active();
    my $server;

    # be defensive
    if (! @{$e->{RECIPS}}) {
      $server = $active;
    }

    for my $recip (@{$e->{RECIPS}}) {
	my($name, $serv) = split /@/, $recip, 2;
	if (defined($serv)) {
	    my $servName = $serv;
	    $serv = TLily::Server::find($serv);
	    if (!defined($serv)) {
		$ui->print("(cannot find server \"$servName\")\n");
		return 1;
	    }
	} else {
	    $serv = $active;
	}

	if (!defined $server) {
	    $server = $serv;
	}

	if ($server != $serv) {
	    $ui->print("(can only send to one server at a time)\n");
	    return 1;
	}

	$recip = $name;
    }

    $e->{server} = $server;
    $server->send_message(join(",",@{$e->{RECIPS}}),$e->{dtype},$e->{text});
}
event_r(type => 'user_send',
	call => \&send_handler);

sub to_server {
    my($e, $h) = @_;
    my $server = $e->{server} || active_server();

    if (! $server) {
	# we aren't connected to a server
        if ($e->{text} == "" && $config{smartexit}) {
            TLily::Event::keepalive();
            exit;
        }
	return 1;
    }

    $server->command($e->{ui}, $e->{text});
}
event_r(type  => "user_input",
	order => "after",
	call  => \&to_server);

sub smartexit_message {
  my ($e,$h)=@_;
  my $ui=TLily::UI::name();
  if (TLily::Server::find==0 && $config{smartexit}) {
    $ui->print("(Smartexit is on; press enter to exit tigerlily.)\n");
  }
  return 1;
}
event_r(type  => 'server_disconnected',
	order => 'after',
	call  => \&smartexit_message);

shelp_r('smartexit' => 'Automatically quit after disconnecting.', 'variables');

1;
