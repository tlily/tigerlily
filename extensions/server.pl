use strict;

use LC::Global qw($event);
use LC::UI;
use LC::Server::SLCP;

my $server;

sub server_command {
	my($ui, $arg) = @_;
	my @argv = split /\s+/, $arg;

	#@argv = qw(pauline.einstein.org 7777);
	@argv = qw(lily.acm.rpi.edu 8888);
	if (@argv != 2) {
		$ui->print("(usage: %server <host> <port>)\n");
		return;
	}

	my($host, $port) = @argv;
	#my $server;
	eval {
		$server = LC::Server::SLCP->new(host    => $host,
						port    => $port,
						ui_name => $ui->name,
						event   => $event);
	};
	unless ($server) {
		$ui->print($@);
		return;
	}

	$event->event_r(type  => "user_input",
			order => "after",
			call  => \&to_server);
}

LC::User::command_r(server => \&server_command);

sub send_handler {
	my($e, $h) = @_;
	$e->{server}->sendln(join(",",@{$e->{RECIPS}}),$e->{dtype},$e->{text});
}
$event->event_r(type => 'user_send',
		call => \&send_handler);

sub to_server {
	my($e, $h) = @_;

	if ($e->{text} =~ /^(\S*)([;:])(.*)/) {
		$event->send(type   => 'user_send',
			     server => $server,
			     RECIPS => [split /,/, $1],
			     dtype  => $2,
			     text   => $3);
		return 1;
	}

	$server->sendln($e->{text});
	return 1;
}
