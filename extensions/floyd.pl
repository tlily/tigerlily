use TLily::Bot custom;
use FileHandle;
use IPC::Open2;
use POSIX ":sys_wait_h";
    
my %running_games;
my $max_games = 5;
my $interpreter = "./rezrov_slave.pl ZORK1.DAT";

$SIG{CHLD} = \&reaper;

event_r(type => 'private',
	call => sub {
	    my($event, $handler) = @_;	
	    my $message = $event->{VALUE};

	    if (! $running_games{$event->{SHANDLE}}) {
		if (scalar(keys(%running_games)) > $max_games) {
		    response($event, "Too many games are currently in session.  Please try again later.");
		    return;
		}
		
		start_game($event);
	    } else {
		if ($message =~ /^\s*save/i) {
		    response($event,"game saving is not currently supported");
		    return 0;
		}
		my $fh = $running_games{$event->{SHANDLE}}->{"wh"};
		print $fh "$message\n";
	    }
	    
	    return 0;
	});



sub start_game {
    my ($event) = @_;
    
    my $rh = new FileHandle;
    my $wh = new FileHandle;
    $wh->autoflush(1);

    chdir("$::TL_EXTDIR/floyd");
    eval { $pid = open2($rh, $wh, "$interpreter"); };
    if (! $pid or $@) {
	response($event,"Error starting interpreter: $@");
        exit;
    }

    my $iohandler = TLily::Event::io_r(handle => $rh,
				       mode => 'r',
				       name => "floyd-$event->{SHANDLE}",
				       obj => $rh,
				       call => sub {
					   my ($rh) = @_;
  					   my $line = <$rh>;
					   if ($line =~ /^\#\$\# SEND (.*)/) {
					       response($event, $1, 1);
					   }
				       });
    
    $running_games{$event->{SHANDLE}} = { rh => $rh,
					 wh => $wh,
  					 pid => $pid,
					 iohandler => $iohandler };
    
}

sub reaper {
    while ($child = waitpid(-1, WNOHANG)) {
	last if $child == -1;

        foreach (keys %running_games) {
	    my $game = $running_games{$_};
	    if ($child == $game->{pid}) {
	    	print "Reaped PID $child\n";
	        delete $running_games{$_};
	    }
        }	
    }	
}

sub unload {
    foreach (keys %running_games) {
   	kill TERM, $running_games{$_}->{pid};
    }
}

1;
