# -*- Perl -*-

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/Attic/http2_parse.pl,v 1.2 2000/10/27 20:36:16 coke Exp $

use strict;

use TLily::Daemon::HTTP;

my $daemon = undef;

sub parse_http2 {
	my ($event, $handler) = @_;
	my $st;

	$daemon = TLily::Daemon::HTTP::daemon() unless defined($daemon);
	
	if (defined $event->{server}) {   # Server instance, not daemon instance
		$st = \$event->{server}->{_state};
	} else {
		$st = \$event->{daemon}->{_state};
	}
	
	if ($$st->{_done}) {
	 	#dispatch($event,"Scenario 1");
		save_file2 ($event, $handler);
		return;
	}
	
	my $text = $$st->{"_partial"} . $event->{data};
	
	while ($text =~ s/^([^\r\n]+)\r?\n//) {
		my $line = $1;
		TLily::Event::send(type   => 'http2_line',
						   daemon => $event->{daemon},
						   server => $event->{server},
						   data   => $line);
	}
	if ($text =~ s/^\r?\n//) {
		TLily::Event::send(type   => 'http2_complete',
						   server => $event->{server},
						   daemon => $event->{daemon},
						   data   => $text);
	}
	
	$$st->{"_partial"} = $text;
}

sub parse_http2_line {
	my ($event, $handler) = @_;
	
	my $text = $event->{data};
	my $st;
	
	if (defined $event->{server}) {
		$st = \$event->{server}->{"_state"}; 
	} else {
		$st = \$event->{daemon}->{"_state"};
	}
	
	#	my $ui = TLily::UI::name();
	
	if ((defined $event->{server}) && (!($$st->{_status}))) {
		if ($text !~ /^(HTTP\/\d+\.\d+)[ \t]+(\d+)[ \t]+.*$/) {
			# Do something here.  This is unexpected.
			return;
		}
		
		$event->{server}->{"_state"} = { _proto   => $1,
										 _status  => $2,
										 _msg	 => $3
									   };
		
		#	$ui->print ("Server returned status ", $$st->{_status}, "\n");
		return;
	} elsif ((!(defined $event->{server})) && (!($$st->{_command}))) {
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
				 _file	=> $2,
				 _proto   => $3,
			   };
		
		return;
	}
	
	if ($text =~ /^(\w+):(.+)$/) {
		$$st->{$1} = $2;
		return;
	}
}

sub complete_http2 {
	my ($event, $handler) = @_;
	
	my $st;


	
	if (defined $event->{server}) {
		$event->{server}->{_state}->{_done} = 1;
	 	#dispatch($event,"Scenario 2");
		save_file2($event, $handler);
		return;
	} else {
		$event->{daemon}->{_state}->{_done} = 1;
		$st = \$event->{daemon}->{_state};
	}
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
		my $d = $event->{daemon};
		
		$d->print("HTTP/1.0 200 OK\r\n");
		$d->print("Date: " . TLily::Daemon::HTTP::date() . "\r\n");
		$d->print("Connection: close\r\n");
		$d->print("\r\n");
		if ($$st->{_command} eq 'GET') {
			$d->print("<html><head>\n<title>Tigerlily</title>\n");
			$d->print("</head><body>\n");
			$d->print("To download the latest version of Tigerlily, ");
			$d->print("click ");
			$d->print("<a href=\"http://www.hitchhiker.org/tigerlily\">\n");
			$d->print("here</a></body></html>\n");
		}
		$d->close();
		return;
	}
	
	$$st->{_file} =~ s|^/||;
	
	unless ($event->{daemon}->send(file => $$st->{_file},
								   head => ($$st->{_command} eq 'HEAD'))) {
		$event->{daemon}->close();
		return;
	}
}

# This is a pseudo-eventhandler.  It never gets called by the event system,
# it just gets called as soon as possible from other events.

sub save_file2 {
	my ($event, $handler) = @_;
	
	my $st;
	my $filename;
	
	if (defined $event->{server}) {
		$st = \$event->{server}->{"_state"};
		$filename = $event->{server}->{filename};
	} else {
		$st = \$event->{daemon}->{"_state"};
		return unless $$st->{_passive};
		$filename = $$st->{_file};
	}
	
	return if $$st->{_nomorewrite};
	
	$event->{server}->{_content} .= $event->{data}; 

	#syswrite ($$st->{_filehandle}, $event->{data}, length($event->{data}));
	$$st->{_byteswritten} += length($event->{data});
	
	if ((defined ($$st->{"Content-Length"})) &&
		($$st->{_byteswritten} >= $$st->{"Content-Length"})) {
		$$st->{_nomorewrite} = 1;
		$event->{server}->terminate() if defined $event->{server};
		$event->{daemon}->close() if defined $event->{daemon};
	}
	return;
}

sub cleanup2 {
	my ($event, $handler) = @_;
	
	close ($event->{daemon}->{_state}->{_filehandle})
	  if defined $event->{daemon}->{_state}->{_filehandle};

	# Process the callback registered for this data... 

	&{$event->{server}->{callback}}($event->{server});

	return;
}

sub load {
	event_r (type => 'http2_data',
			 call => \&parse_http2);
	event_r (type => 'http2_line',
			 call => \&parse_http2_line);
	event_r (type => 'http2_complete',
			 call => \&complete_http2);
	event_r (type => 'http2_close',
			 call => \&cleanup2);
	event_r (type => 'server_disconnected',
			 call => \&cleanup2);

	$daemon = TLily::Daemon::HTTP::daemon();
}

sub unload {
	$daemon->terminate() if defined($daemon);
	undef $daemon;
}
