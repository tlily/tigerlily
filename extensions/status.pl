# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/status.pl,v 1.25 2002/06/11 01:55:48 bwelling Exp $

use strict;

sub set_clock {
    my $ui = ui_name("main");

    my @a = localtime;
    
    $ui->set(clock => TLily::Utils::format_time(\@a, delta => "clockdelta",
    						type => "clocktype",
						seconds => "clockseconds"));
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
