use strict;

use TLily::UI;
use TLily::Server::SLCP;

sub server_command {
	my($ui, $arg) = @_;
	my(@argv) = split /\s+/, $arg;

	my($host, $port) = @argv;
	$host = "lily.acm.rpi.edu" unless defined($host);
	$port = 8888               unless defined($port);

	my $server;
	$server = TLily::Server::SLCP->new(host    => $host,
					port    => $port,
					ui_name => $ui->name);
}
TLily::User::command_r(connect => \&server_command);

sub send_handler {
	my($e, $h) = @_;
	$e->{server}->sendln(join(",",@{$e->{RECIPS}}),$e->{dtype},$e->{text});
}
TLily::Event::event_r(type => 'user_send',
		call => \&send_handler);

sub to_server {
	my($e, $h) = @_;
	my $server = TLily::Server::name();

	if ($e->{text} =~ /^(\S*)([;:])(.*)/) {
		TLily::Event::send(type   => 'user_send',
			     server => $server,
			     RECIPS => [split /,/, $1],
			     dtype  => $2,
			     text   => $3);
		return 1;
	}

	$server->sendln($e->{text});
	return 1;
}
TLily::Event::event_r(type  => "user_input",
		order => "after",
		call  => \&to_server);
