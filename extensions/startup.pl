# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/startup.pl,v 1.16 2002/12/03 20:32:14 josh Exp $

use strict;

event_r(type  => 'connected',
	order => 'before',
	call  => \&startup_handler);

sub startup_handler ($$) {
    my($event,$handler) = @_;
    return if ($event->{startup_files_run}); # Don't loop!
    my $ui = ui_name();

    if(-f $ENV{HOME}."/.lily/tlily/Startup") {
        local(*SUP);
	if (! open(SUP, "<$ENV{HOME}/.lily/tlily/Startup")) {
	    $ui->print("Error opening Startup: $!\n");
	    return 0;
	}
        $ui->print("(Running ~/.lily/tlily/Startup)\n\n");
	while(<SUP>) {
            next if /^(#|\s+$)/;
	    chomp;
	    TLily::Event::send({type    => 'user_input',
				ui      => $ui,
				startup => 1,
				text    => $_});
	}
	close(SUP);
    } else {
        $ui->print("(No startup file found.)\n");
        $ui->print("(If you want to install one, " .
                   "call it ~/.lily/tlily/Startup)\n");
    }

    # Run server-side startup memo
    my $server = active_server();
    my $sub = sub {
	my(%args) = @_;

	if(!$args{text}) {
	    $args{ui}->print("Error opening *tlilyStartup: $!\n");
	    TLily::Event::send(%$event,
                               type              => 'connected',
			       startup_files_run => 1,
			       ui                => $args{ui});
	    return 0;
	}
        {   my $f;
	    foreach (@{$args{text}}) { $f = 1 and last if not /^\s*$/ }

            unless($f) {
		$args{ui}->print("(No startup memo found.)\n",
		    "(If you want to install one, ",
		    "call it tlilyStartup or *tlilyStartup)\n");
		TLily::Event::send(%$event,
				   type              => 'connected',
				   startup_files_run => 1,
				   ui                => $args{ui});
		return 0;
	    }
        }
        $args{ui}->print("(Running memo tlilyStartup)\n\n");
	foreach (@{$args{text}}) {
            next if /^#/;
	    chomp;
	    TLily::Event::send({type    => 'user_input',
				ui      => $args{ui},
				startup => 1,
				text    => $_});
	}
	TLily::Event::send(%$event,
			   type              => 'connected',
			   startup_files_run => 1,
			   ui                => $args{ui});
	return 0;
    };

    unless ($config{no_startup_memo}) {
        $server->fetch(ui     => $ui,
		       type   => "memo",
                       name   => "tlilyStartup",
		       target => "me",
		       call   => $sub);
    } else {
	TLily::Event::send(%$event,
			   type              => 'connected',
			   startup_files_run => 1,
			   ui                => $ui);
        return 0;
    }

    return 1;
}

1;
