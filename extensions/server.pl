use strict;

use LC::Global qw($event $user);
use LC::UI;
use LC::Server;

my $server;

sub server_command {
	my($user, $ui, $arg) = @_;
	my @argv = split /\s+/, $arg;

	if (@argv != 2) {
		$ui->print("(usage: %server <host> <port>)\n");
		return;
	}

	my($host, $port) = @argv;
	#my $server;
	eval {
		$server = LC::Server->new(host => $host,
					  port => $port,
					  event => $event);
	};
	unless ($server) {
		$ui->print($@);
		return;
	}

	$event->event_r(type => "user_input",
			call => \&to_server);
}

$user->command_r(server => \&server_command);


sub server_cat {
	my($event, $handler) = @_;

	my $ui = LC::UI::name("main");
	$ui->print($event->{data});
	return;
}

$event->event_r(type => 'server_data',
		call => \&server_cat);

sub to_server {
	my($event, $handler) = @_;

	$server->send($event->{text}, "\n");
}
