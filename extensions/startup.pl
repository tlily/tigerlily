# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/startup.pl,v 1.12 2000/02/08 01:45:21 tale Exp $

use strict;

event_r(type  => 'connected',
	order => 'before',
	call  => \&startup_handler);

sub startup_handler ($$) {
    my($event,$handler) = @_;
    my $ui = ui_name();

    if(-f $ENV{HOME}."/.lily/tlily/Startup") {
        local(*SUP);
	open(SUP, "<$ENV{HOME}/.lily/tlily/Startup");
	if($!) {
	    $ui->print("Error opening Startup: $!\n");
	    event_u($handler);
	    return 0;
	}
        $ui->print("(Running ~/.lily/tlily/Startup)\n\n");
	while(<SUP>) {
            next if /^#/;
	    chomp;
	    TLily::Event::send({type => 'user_input',
				ui   => $ui,
				text => "$_\n"});
	}
	close(SUP);
    } else {
        $ui->print("(No startup file found.)\n");
        $ui->print("(If you want to install one, call it ~/.lily/tlily/Startup)\n");
    }

    # Run server-side startup memo
    my $server = active_server();
    my $sub = sub {
	my(%args) = @_;
        
	if(!$args{text}) {
	    $args{ui}->print("Error opening *tlilyStartup: $!\n");
	    event_u($handler);
	    TLily::Event::send(%$event,
                               type => 'connected',
			       ui   => $args{ui});
	    return 0;
	}
        {   my $f;
	    foreach (@{$args{text}}) { $f = 1 and last if not /^\s*$/ }

            unless($f) {
		$args{ui}->print("(No startup memo found.)\n",
		    "(If you want to install one, ",
		    "call it tlilyStartup or *tlilyStartup)\n");
		event_u($handler);
		TLily::Event::send(%$event,
				   type => 'connected',
				   ui   => $args{ui});
		return 0;
	    }
        }
        $args{ui}->print("(Running memo tlilyStartup)\n\n");
	foreach (@{$args{text}}) {
            next if /^#/;
	    chomp;
	    TLily::Event::send({type => 'user_input',
				ui   => $args{ui},
				text => "$_\n"});
	}
	event_u($handler);
	TLily::Event::send(%$event,
			   type => 'connected',
			   ui   => $args{ui});
	return 0;
    };

    unless ($config{no_startup_memo}) {
        $server->fetch(ui     => $ui,
		       type   => "memo",
                       name   => "tlilyStartup",
		       target => "me",
		       call   => $sub);
    } else {
        event_u($handler);
	TLily::Event::send(%$event,
			   type => 'connected',
			   ui   => $ui);
        return 0;
    }

    event_u($handler);
    return 1;
}

1;
