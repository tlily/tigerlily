# -*- Perl -*-
# $Id$

use strict;

TLily::Event::event_r(type  => "user_input",
                            order => "before",
                          call  => \&input_handler);

shelp_r("multicore","Target commands to specific cores");

my $help =<<HELP;
This extension allows you to prefix a "/" command  with the name
of the server you wish to run the command on. You may specify
multiple cores with a comma separated list, or all cores with a *.
You may specify a partial core name, and the "/" will auto-expand
it to a valid core name, if possible.

Examples:

RPI/blurb off             # disables blurb on RPI
IMG,RPI/here I'm here     # Changes blurb and state on 2 cores.
*/detach                  # detach from every core you're connected to.
HELP
help_r("multicore",$help);

sub input_handler {
    my($e, $h) = @_;

    next unless $e->{text} =~ m/^([^@;:=\s]+)(\/.*)/;
    my($servers, $command) = ($1, $2);

    next if $servers eq "&" ;# pipes.pl uses this.

    my @servers;

    if ($servers ne "*")  {
      my $die=0;
      foreach my $server (split/,/,$servers) {
            my $s = TLily::Server::find($server);
           if (!$s) {
            $e->{ui}->print("(could find no server to match to \"$server\")\n");
            $die = 1;
          } else {
            push @servers,$s;
          }
      }
      return 1 if $die;
    } else {
      @servers = TLily::Server::find();
    }

    foreach my $server (@servers) {
      $server->cmd_process($command, sub {;});
    }
    return 1;
}


sub expand_slash {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    my $partial = substr($line, 0, $pos);

    if (0) {
    # We tried expanding servers, people didn't like it.
    if ($partial eq "*") {
        my $servers =
          join(",",map(scalar $_->name, TLily::Server::find));
        $ui->set_input(length($servers) + 1, $servers . "/");
        return;
    }
    }

    if (length($partial) && $partial !~ m|[/@;:= ]|) {
        my @servers =
          grep(/^\Q$partial\E/i, map(scalar $_->name, TLily::Server::find));
        if (@servers == 1) {
            $pos++ if (substr($line, $pos, 1) eq "/");
            $ui->set_input(length($servers[0]) + 1,
                           $servers[0]."/".substr($line, $pos));
            return;
        }
    }

    $ui->command("insert-self", $key);
    return;


}

TLily::UI::command_r("electric-slash" => \&expand_slash);
TLily::UI::bind('/' => "electric-slash");
