use strict;

use LC::Global qw($event);
use LC::UI;
use LC::Server::SLCP;

sub server_command {
	my($ui, $arg) = @_;
	my(@argv) = split /\s+/, $arg;

	my($host, $port) = @argv;
	$host = "lily.acm.rpi.edu" unless defined($host);
	$port = 8888               unless defined($port);

	my $server;
	$server = LC::Server::SLCP->new(host    => $host,
					port    => $port,
					ui_name => $ui->name,
					event   => $event);
}
LC::User::command_r(connect => \&server_command);

sub send_handler {
	my($e, $h) = @_;
	$e->{server}->sendln(join(",",@{$e->{RECIPS}}),$e->{dtype},$e->{text});
}
$event->event_r(type => 'user_send',
		call => \&send_handler);

sub to_server {
	my($e, $h) = @_;
	my $server = LC::Server::name();

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
$event->event_r(type  => "user_input",
		order => "after",
		call  => \&to_server);
