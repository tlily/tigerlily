# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/after.pl,v 1.3 1999/03/02 02:02:33 neild Exp $

use strict;

my $interval_help = "
Time intervals can be in any of the following formats:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days
";
help_r("interval" => $interval_help);

my $cron_help = qq(
Usage: %cron [after|every] <offset> <command>
       %cron cancel <id> ...
       %cron
       %after <offset> <command>
       %every <offset> <command>

%cron schedules a command to be executed at a given time.  "%cron after" \
specifies that the command should be run after a given interval.  "%cron \
every" specifies that it should be run after a given interval, and \
periodically afterwards.  "%cron at" is not implemented, but probably should \
be.

All current tasks may be listed by running "%cron" with no arguments, and \
an existing task may be cancelled with "%cron cancel".

%after and %every act like %cron, but they set the recurrance type by default.

(see also: intervals)
);

my %cron;
my %cron_id;
my %cron_when;
my $id=0;

sub parse_interval {
    my($s) = @_;

    if($s =~ m/^(\d+)s?$/) {
	return $1;
    }
    elsif($s =~ m/^(\d+)m$/) {
	return $1 * 60;
    }
    elsif($s =~ m/^(\d+)h$/) {
	return $1 * 3600;
    } 
    elsif($s =~ m/^(\d+)d$/) {
	return $1 * 86400 ;
    } 
    else {
	return;
    }
}

sub cron_command {
    my($ui, $args, $command) = @_;
    my @args = split /\s+/, $args;

    my $usage = "(%cron after|every interval command; type %help for help)\n";

    # Print all current tasks.
    if(@args == 0) {
        $ui->printf("(%2s  %-17s  %s)\n", "Id", "When", "Command");
	my $k;
	foreach $k (sort keys %cron) {
       	    my($sec,$min,$hour,$mday,$mon,$year) = localtime($cron_when{$k});
	    $ui->printf("(%2d  %02d:%02d:%02d %02d/%02d/%02d  %s)\n",
			$k, $hour, $min, $sec, $mon, $mday, $year, $cron{$k});
	}
	return;
    }

    # Cancel one or more tasks.
    if ($args[0] eq "cancel") {
	shift @args;
	while (@args) {
	    my $tbc = shift @args;
	    $ui->print("(cancelling task $tbc ($cron{$tbc}))\n");
	    TLily::Event::time_u($cron_id{$tbc});
	    delete $cron{$tbc};
	    delete $cron_id{$tbc};
	    delete $cron_when{$tbc};
	}
	return;
    }

    if ($args[0] eq "after" || $args[0] eq "every") {
	$command = shift @args;
    }

    if ($command eq "cron" || @args < 2) {
	$ui->print($usage);
	return;
    }

    my $itext = shift @args;
    my $cmd   = join(" ", @args);

    my $interval = parse_interval($itext);
    if (!defined $interval) {
	$ui->print($usage);
	return;
    }

    my $ui_name = $ui->name();

    $cron{$id} = $cmd;
    $cron_when{$id} = time + $interval;

    my $sub = sub {
	my($handler) = @_;
	my $ui = TLily::UI::name($ui_name);
	$ui->print("($itext has passed, running \"$cmd\".)\n");
	TLily::Event::send(type => 'user_input',
			   ui   => $ui,
			   text => $cmd);
	unless (defined $handler->{interval}) {
	    delete $cron{$id};
	    delete $cron_id{$id};
	    delete $cron_when{$id};
	}
    };
    my $h = { after => $interval, call => $sub };
    $h->{interval} = $interval if ($command eq "every");
    $cron_id{$id} = TLily::Event::time_r($h);

    $ui->print("($command $interval, I will run \"$cmd\" [id $id].)\n");
    $id++;
    return 0;
}
command_r("cron"  => \&cron_command);
command_r("after" => \&cron_command);
command_r("every" => \&cron_command);
shelp_r("cron" => "Run a command at a designated time.");
help_r("cron" => $cron_help);
help_r("after" => $cron_help);
help_r("every" => $cron_help);

sub unload() {
  my $ui = TLily::UI::name("main");
  foreach my $k (sort keys %cron) {
    $ui->print("(cancelling task $k ($cron{$k}))\n");
    TLily::Event::time_u($cron_id{$k});
    delete $cron{$k}; delete $cron_id{$k}; delete $cron_when{$k};
  }
}

1;
