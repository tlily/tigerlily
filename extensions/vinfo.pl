# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/vinfo.pl,v 1.4 1999/10/02 17:46:59 josh Exp $

event_r(type => 'private',
	order => 'before',
	call => \&send_handler);

command_r('vinfo' => \&vinfo_handler);
shelp_r('vinfo', "Automatic version information transmission.");

sub command {
    my $server=TLily::Server::active();
    
    # The bit about 'send' events below is a hack for occasions when you
    # send a vinfo request to yourself.
    $server->cmd_process(join('', @_), sub {
		    $_[0]->{NOTIFY} = 0 unless ($_[0]->{type} eq 'private');
		});
}

sub send_version_info {
    my($to) = @_;
    command($to, ";[auto] tlily version is ", $TLily::Version::VERSION,
	    ", perl version is ", $], ".");
}

sub send_handler {
    my($event, $handler) = @_;
    my $ui = ui_name();

    return 0 unless (($event->{VALUE} eq "@@@ tlily info @@@") ||
		     ($event->{VALUE} eq "+++ tlily info +++"));

    $event->{NOTIFY} = 0;

    if ($config{'send_info_ok'}) {
	$ui->print("(Sending tlily/perl version info to " . $event->{SOURCE} .
		  ")\n");
	send_version_info($event->{SOURCE});
    } else {
	$ui->print("(Denying version info request from " . $event->{SOURCE} .
		  ".  See %help vinfo for details.  Use %vinfo send to explicitly send a response.)\n");
    }

    return 0;
}

sub vinfo_handler {
    my $ui = shift;
    my @args = split /\s+/, $_[0];
    my $cmd = shift @args || '';

    if ($cmd eq 'request') {
	foreach (@args) {
	    $ui->print("(sending version info request to $_)\n");
	    command("$_;@@@ tlily info @@@");
	}
    } elsif ($cmd eq 'send') {
	foreach (@args) {
	    send_version_info($_);
	}
    } elsif ($cmd eq 'permit') {
	my $opt = shift @args || 'on';
	if ($opt eq 'on') {
	    $ui->print("(Permitting version info requests)\n");
	    $config{'send_info_ok'} = 1;
	} else {
	    $ui->print("(Forbidding version info requests)\n");
	    $config{'send_info_ok'} = 0;
	}
    } else {
	$ui->print("? Usage: vinfo request <user> ...\n");
	$ui->print("?        vinfo send <destination> ...\n");
	$ui->print("?        vinfo permit [on | off]\n");
    }

    return 0;
}
