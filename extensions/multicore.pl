# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/multicore.pl,v 1.1 2001/07/27 18:35:29 coke Exp $

use strict;

TLily::Event::event_r(type  => "user_input",
	  		  order => "before",
			  call  => \&input_handler);

sub input_handler {
    my($e, $h) = @_;

    next unless $e->{text} =~ m/^[@\*]/;

    my($servers); 
    foreach (TLily::Server::find()) {
      $servers->{$_->name()} = $_;
    }

    if ($e->{text} =~ m:^\@([A-Z_a-z]+)(/..*):) {
      my ($server,$command) = ($1,$2);
      chomp($command);


      if (not exists($servers->{$server})) {
        TLily::UI::name("main")->print("Bad server: $server: try one of ". join(", ",%$servers) . "\n");
        return 1;
      }

      $servers->{$server}->cmd_process($command, sub {;});

      return 1;

    } elsif ($e->{text} =~ m:^\*(/..*):) {
      my($command) = $1;
      foreach (keys %$servers) {
        $servers->{$_}->cmd_process($command, sub {;});
      }
      return 1;
    }

    return;
}
