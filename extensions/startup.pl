# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/startup.pl,v 1.2 1999/03/15 23:53:17 josh Exp $

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
    event_u($handler->{id});
    return 0;
}

1;
