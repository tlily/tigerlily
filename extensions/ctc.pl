# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/ctc.pl,v 1.2 1999/04/11 02:35:32 steve Exp $

use Net::Domain qw(hostfqdn);
use Socket qw(inet_ntoa inet_aton);
use TLily::Daemon::HTTP;
use TLily::Server::HTTP;

use strict;

my %pending;
my %received;

my $hostaddr;

my $http;

sub command {
    cmd_process(join('', @_), sub {
		    $_[0]->{NOTIFY} = 0 unless ($_[0]->{type} eq 'private')
		});
}

sub ctc_cmd {
    my ($ui, $args) = @_;
    
    my ($cmd, @rest) = split /\s+/, $args;
    
    $cmd = lc($cmd);
    
    if ($cmd eq 'send') {
	my ($to, $file) = @rest;

	# Generate an alias
	my @tmp = split m|/|, $file;
	my $shfile = pop @tmp;
	my $alias = "";
	for (my $i = 0; $i < 8; $i++) {
	    my $c = rand (26);
	    my $r = rand (100);
	    $alias .= ($r < 50) ? chr($c + 65) : chr ($c + 97);
	}
	$alias .= "/$shfile";
	
	unless ((TLily::Daemon::HTTP::file_r (file  => $file,
					      alias => $alias))) {
	    $ui->print("(unable to find file $file)");
	    return;
	}
	$pending{$alias} = { file => $file, to => $to };
	$ui->print("(sending file request to $to)\n");
	command($to, 
		";@@@ ctc send @@@ http://$hostaddr:$http->{port}/$alias");
	return;
    }

    if ($cmd eq 'get') {
	my ($from, $file) = @rest;
	my $lfrom;

	if (!defined $from) {
	    $ui->print ("(you must specify a user to get from)\n");
	    return;
	}

	$lfrom = lc($from);
	if ((!exists($received{$lfrom})) ||
	    (!(scalar(@{$received{$lfrom}})))) {
	    $ui->print ("(no pending sends from ${from})\n");
	    return;
	}

	my $url = 0;

	if ($file) {
	    for (my $i = 0; $i < scalar(@{$received{$lfrom}}); $i++) {
		if ($received{$lfrom}->[$i]->{URL} =~ /$file$/) {
		    $url = splice @{$received{$lfrom}}, $i, 1;
		    last;
		}
	    }
	    if (!$url) {
		$ui->print ("($from did not send you a file named $file)\n");
		return;
	    }
	} else {
	    $url = shift @{$received{$lfrom}};
	}

#	return passive_get($url, $from) if $url->{Passive};
	$ui->print ("(getting $url->{URL})\n");
	TLily::Server::HTTP->new(url => $url->{URL},
				 ui_name => $ui->{name});
	return;
    }

    if ($cmd eq 'list') {
	$ui->print(" Type   User                    Filename\n");
	
	foreach my $p (keys %pending) {
	    my $s = "SEND";   # Passive eventually, too.
	    $ui->printf(" $s   %-23s %s\n", $pending{$p}->{to},
			$pending{$p}->{file});
	}
	foreach my $p (keys %received) {
	    foreach my $q (@{$received{$p}}) {
		my @r = split m|/|, $q->{URL};
		my $r = pop @r;
		$ui->printf(" GET    %-23s %s\n", $p, $r);
	    }
	}
	return;
    }

    if ($cmd eq 'cancel') {
	my ($to, $file) = @rest;

	for my $p (keys %pending) {
	    if (!$to || $pending{$p}->{to} eq lc($to)) {
		TLily::Daemon::HTTP::file_u($p);
		delete $pending{$p};
	    }
	}
	my $o = ($to) ? " to $to" : "";
	$ui->print("(all pending sends", $o, " cancelled)\n");
	return;
    }

    if ($cmd eq 'refuse') {
	my ($from, $file) = @rest;

	my $lfrom = lc($from);
	if (!$received{$lfrom}) {
	    $ui->print("(no pending gets from $from)\n");
	    return;
	}

	for (my $i = 0; $i < scalar(@{$received{$lfrom}}); $i++) {
	    if (!$file || $received{$lfrom}->[$i]->{URL} =~ /$file$/) {
		command ($from, ";@@@ ctc refuse @@@ ",
			 $received{$lfrom}->[$i]->{URL});
		my @f = split m|/|, $received{$lfrom}->[$i]->{URL};
		my $f = pop @f;
		$ui->print("(refusing file $f from $from)\n");
		splice @{$received{$lfrom}}, $i, 1;
	    }
	}
	delete $received{$lfrom} unless (scalar(@{$received{$lfrom}}));
	return;
    }
    $ui->print("unknown %ctc command, see %help ctc\n");
}

sub send_handler {
    my ($event, $handler) = @_;

    return 0 unless ($event->{VALUE} =~
		     s/^@@@ ctc (send|passive|passiveok|refuse) @@@\s*//);

    my $cmd = $1;
    my $ui = TLily::UI::name();

    $event->{NOTIFY} = 0;
    $event->{BELL} = 0;

    my ($addr, $port, $alias, $file) =
      ($event->{VALUE} =~ m|^http://(.+):(\d+)/(.+/(.+))$|);

    if (($cmd eq 'send')) {
	push (@{$received{"\L$event->{SOURCE}"}},
	      { URL     => $event->{VALUE},
		Passive => ($cmd eq 'passive')
	      });
	$ui->print ("(Received ctc send request file \"$file\" from ",
		    $event->{SOURCE}, ")\n");
	$ui->print ("(Use %ctc get $event->{SOURCE} to receive)\n");
	return;
    }
}

sub file_done {
    my ($event, $handler) = @_;
 
    if (exists $pending{$event->{daemon}->{filealias}}) {
	my $ui = TLily::UI::name();

	$ui->print ("(File ", $pending{$event->{daemon}->{filealias}}->{file},
		    " sent successfully)\n");
	delete $pending{$event->{daemon}->{filealias}};
	TLily::Daemon::HTTP::file_u ($event->{daemon}->{filealias});
    }
}

sub load {
    $hostaddr = inet_ntoa(inet_aton(hostfqdn()));

    $http = TLily::Daemon::HTTP->new();

    event_r (type => 'http_filedone',
	     call => \&file_done);

    event_r (type  => 'private',
	     order => 'before',
	     call  => \&send_handler);

    command_r('ctc' => \&ctc_cmd);
    shelp_r('ctc' => "Client to client transfer commands");
    help_r ('ctc' => "
%ctc send   <user> <file>     - Sends the specified file to the user.
%ctc get    <user> [<file>]   - Gets the (optionally specified) file
                                from the specified user.
%ctc list                     - List pending sends and gets.
%ctc cancel [<user>]          - Cancel pending sends.
%ctc refuse <user> [<file>]   - Refuse a pending get.
");
}
