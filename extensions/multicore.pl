# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/multicore.pl,v 1.2 2001/07/30 18:41:17 neild Exp $

use strict;

TLily::Event::event_r(type  => "user_input",
	  		  order => "before",
			  call  => \&input_handler);

sub input_handler {
    my($e, $h) = @_;

    next unless $e->{text} =~ m/^([^@;:=\s]+)(\/.*)/;
    my($server, $command) = ($1, $2);

    if ($server ne "*") {
      my $s = TLily::Server::find($server);
      if (!$s) {
	$e->{ui}->print("(could find no server to match to \"$server\")\n");
        return 1;
      }

      $s->cmd_process($command, sub {;});

      return 1;

    } else {
      foreach (TLily::Server::find()) {
        $_->cmd_process($command, sub {;});
      }
      return 1;
    }

    return;
}


sub expand_slash {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    my $partial = substr($line, 0, $pos);

    if (length($partial) && $partial !~ m|[/@;:= ]|) {
	my @servers =
	  grep(/^\Q$partial\E/i, map(scalar $_->name, TLily::Server::find));
	if (@servers == 1) {
	    $ui->set_input(length($servers[0]) + 1,
			   $servers[0].substr($line, $pos)."/");
	    return;
	}
    }

    $ui->command("insert-self", $key);
    return;


}

TLily::UI::command_r("electric-slash" => \&expand_slash);
TLily::UI::bind('/' => "electric-slash");
