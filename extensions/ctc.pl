# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/ctc.pl,v 1.1 1999/04/06 19:12:05 steve Exp $

use Net::Domain qw(hostfqdn);
use Socket qw(inet_ntoa inet_aton);
use TLily::Daemon::HTTP;

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
