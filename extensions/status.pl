# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/status.pl,v 1.24 2002/06/06 22:23:41 bwelling Exp $

use strict;

sub set_clock {
    my $ui = ui_name("main");
    
    my @a = localtime;
    if ($config{clockdelta}) {
	my($t) = ($a[2] * 60) + $a[1] + $config{clockdelta};
	$t += (60 * 24) if ($t < 0);
	$t -= (60 * 24) if ($t >= (60 * 24));
	$a[2] = int($t / 60);
	$a[1] = $t % 60;
    }
    my $ampm = "";
    my $seconds = "";
    my $format = "%02d:%02d%s%s";
    if ($config{clocktype} eq '12') {
	if ($a[2] >= 12) {
	    $ampm = 'p';
	    $a[2] -= 12 if $a[2] > 12;
	}
	elsif ($a[2] < 12) {
            $a[2] = 12 if $a[2] == 0;
	    $ampm = 'a';
	}
        $format = "%2d:%02d%s%s";
    }
    if ($config{clockseconds}) {
        $seconds = sprintf(":%02d", $a[0]);
    }
	
    $ui->set(clock => sprintf($format, $a[2], $a[1], $seconds, $ampm));
    return 0;
}    

sub set_serverstatus {
    my $ui     = ui_name("main");
    my $server = active_server();
    unless ($server) {
        $ui->set(connected => "-- NOT CONNECTED --");
        return;
    }
    $ui->set(connected => undef);

    my $sname = $server->state(DATA => 1,
			       NAME => "NAME");
    $ui->set(server => $sname) if (defined $sname);
    
    my($name, %state);
    $name  = $server->user_name() || "";

    if ($name ne "") {
        %state = $server->state(NAME => $name);
    
        $name .= " [$state{BLURB}]" if (defined $state{BLURB} &&
				        $state{BLURB} =~ /\S/);
    }

    $ui->set(nameblurb => $name);
    $ui->set(state => $state{STATE}) if defined($state{STATE});
    
    return 0;
}


sub load {
    my $ui = ui_name("main");
    my $server = active_server();
    
    $ui->define(nameblurb => 'left');
    $ui->define(clock     => 'right');
    $ui->define(state     => 'right');
    $ui->define(server    => 'right');
    $ui->define(connected => 'override');
    
    my $sec = (localtime)[0];
    set_clock();
    my ($after, $interval);
    if ($config{clockseconds}) {
        $after = 1;
	$interval = 1;
    } else {
        $after = 60 - $sec;
	$interval = 60;
    }
    TLily::Event::time_r(after    => $after,
			 interval => $interval,
			 call     => \&set_clock);
    
    if ($server) {
	set_serverstatus();
    } else {
        $ui->set(connected => "-- NOT CONNECTED --");
    }
    
    event_r(type => 'userstate',
	    order => 'after',	
	    call => \&set_serverstatus);
    
    event_r(type => 'rename',
	    order => 'after',
	    call => \&set_serverstatus);
    
    event_r(type => 'blurb',
	    order => 'after',	
	    call => \&set_serverstatus);
    
    event_r(type => 'connected',
	    order => 'after',	
	    call => \&set_serverstatus);
    
    event_r(type => 'server_activate',
	    order => 'after',	
	    call => \&set_serverstatus);
}
