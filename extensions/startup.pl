# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/startup.pl,v 1.3 1999/04/14 03:03:24 albert Exp $

use strict;

event_r(type => 'connected',
	order => 'after',
	call => \&startup_handler);

sub startup_handler ($$) {
    my($event,$handler) = @_;
    my $ui = ui_name();

    if(-f $ENV{HOME}."/.lily/tlily/Startup") {
	open(SUP, "<$ENV{HOME}/.lily/tlily/Startup");
	if($!) {
	    $ui->print("Error opening Startup: $!\n");
	    event_u($handler->{id});
	    return 0;
	}
        $ui->print("(Running ~/.lily/tlily/Startup)\n\n");
	while(<SUP>) {
	    chomp;
	    TLily::Event::send({type => 'user_input',
				ui   => $ui,
				text => "$_\n"});
	}
	close(SUP);
    } else {
        $ui->print("(No Setup file found.)\n");
        $ui->print("(If you want to install one, call it ~/.lily/tlily/Startup)\n");
    }

    my $server = server_name();
    my $sub = sub {
	my(%args) = @_;
        
	if(!$args{text}) {
	    $args{ui}->print("Error opening *tlilyStartup: $!\n");
	    return 0;
	}
        {   my $f;
	    foreach (@{$args{text}}) { $f = 1 and last if not /^\s*$/ }

            unless($f) {
		$args{ui}->print("(No Setup memo found.)\n",
		    "(If you want to install one, ",
		    "call it tlilyStartup or *tlilyStartup)\n");
		return 0;
	    }
        }
        $args{ui}->print("(Running memo tlilyStartup)\n\n");
	foreach (@{$args{text}}) {
	    chomp;
	    TLily::Event::send({type => 'user_input',
				ui   => $args{ui},
				text => "$_\n"});
	}
    };
    $server->fetch(ui     => $ui,
		   type   => "memo",
                   name   => "tlilyStartup",
		   target => "me",
		   call   => $sub);

    event_u($handler->{id});
    return 0;
}

1;
