# -*- Perl -*-

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/http_parse.pl,v 1.4 1999/04/06 17:32:04 steve Exp $

use strict;

use TLily::Daemon::HTTP;

my $daemon = undef;

sub parse_http {
    my ($event, $handler) = @_;
    my $ui = TLily::UI::name();
    
    if ($event->{daemon}->{_state}->{_done}) {
	# stub for PUT
	return;
    }
    
    my $text = $event->{daemon}->{_state}->{_partial} . $event->{text};

#    $ui->print("$text");
    while ($text =~ s/^([^\r\n]+)\r?\n//) {
	my $line = $1;
#	$ui->print("$line\n");
	TLily::Event::send(type   => 'http_line',
			   daemon => $event->{daemon},
			   text   => $line);
    }
    if ($text =~ s/^\r?\n$//) {
	TLily::Event::send(type   => 'http_complete',
			   daemon => $event->{daemon});
    }
    
    $event->{daemon}->{_state}->{_partial} = $text;
}

sub parse_http_line {
    my ($event, $handler) = @_;
    
    my $text = $event->{text};
    my $st = \$event->{daemon}->{_state};
    
    if (!($$st->{_command})) {
	if ($text !~ /^(\w+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?$/) {
	    $event->{daemon}->send_error (errno => 400,
					  title => "Bad Request",
					  long  => "This server did not " .
					  "understand that " .
					  "request.");
	    $event->{daemon}->close();
	    return;
	}
	
	$$st = { _command => $1,
		 _file    => $2,
		 _proto   => $3,
	       };
	
	return;
	
    }
    
    if ($text =~ /^(\w+):(.+)$/) {
	$$st->{$1} = $2;
	return;
    }
}

sub complete_http {
    my ($event, $handler) = @_;
    
    my $st = \$event->{daemon}->{_state};
    
    if (($$st->{_command} ne 'GET') &&
	($$st->{_command} ne 'HEAD')) {
	$event->{daemon}->send_error (errno => 501,
				      title => "Not Implemented",
				      long  => "This server did not " .
				      "understand that request.");
	$event->{daemon}->close();
	return;
    }
    
    # Special case for /
    if ($$st->{_file} =~ m|^/$|) {
	my $fd = $event->{daemon}->{sock};
	
	print $fd "HTTP/1.0 200 OK\r\n";
	print $fd "Date: " . TLily::Daemon::HTTP::date() . "\r\n";
	print $fd "Connection: close\r\n";
	print $fd "\r\n";
	if ($$st->{_command} eq 'GET') {
	    print $fd "<html><head>\n<title>Tigerlily</title>\n";
	    print $fd "</head><body>\n";
	    print $fd "To download the latest version of Tigerlily, ";
	    print $fd "click ";
	    print $fd "<a href=\"http://www.hitchhiker.org/tigerlily\">\n";
	    print $fd "here</a></body></html>\n";
	}
	$event->{daemon}->close();
	return;
    }
    
    $$st->{_file} =~ s|/||;
    
    unless ($event->{daemon}->send(file => $$st->{_file},
				   head => ($$st->{_command} eq 'HEAD'))) {
	$event->{daemon}->close();
	return;
    }
}

sub load {
    event_r (type => 'http_data',
	     call => \&parse_http);
    event_r (type => 'http_line',
	     call => \&parse_http_line);
    event_r (type => 'http_complete',
	     call => \&complete_http);
    my $port = 31336;
    while (!(defined($daemon)) && ($port < 31340)) {
	$daemon = TLily::Daemon::HTTP->new (port => ++$port);
    }
    warn ("Unable to bind to a port!") unless $daemon;
}
