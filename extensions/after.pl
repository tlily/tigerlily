# -*- Perl -*-
# $Id$

use strict;

=head1 NAME

after.pl - Time delay functions

=head1 DESCRIPTION

This extension contains %commands for executing commands in a time-delayed
and/or recurring fashion, a la the Unix cron daemon.

=head1 COMMANDS

=over 10

=cut

my $interval_help = "
Time intervals can be in any of the following formats:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days
";
help_r("interval" => $interval_help);

=item %cron

Runs a command at a given time.  See "%help cron" for details.

=cut

=item %after

Runs a command after a given time has elapsed.  See
"%help after" for details.

=cut

=item %every

Runs a command once per given interval.  See "%help every" for details.

=cut

my $cron_help = qq(
Usage: %cron [after|every] <offset> <command>
       %cron [cancel|delete] <id> ...
       %cron
       %after <offset> <command>
       %every <offset> <command>

%cron schedules a command to be executed at a given time.  "%cron after" \
specifies that the command should be run after a given interval.  "%cron \
every" specifies that it should be run after a given interval, and \
periodically afterwards.  "%cron at" is not implemented, but probably should \
be.

All current tasks may be listed by running "%cron" with no arguments, and \
an existing task may be cancelled with "%cron cancel" or "%cron delete". \
(The two forms are equivalent.)

%after and %every act like %cron, but they set the recurrance type by default.

(see also: interval)
);

my %cron;
my %cron_id;
my %cron_interval;
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
    my($command, $ui, $args) = @_;
    my @args = split /\s+/, $args;
    my $usage = "(%cron after|every interval command; type %help for help)\n";

    # Print all current tasks.
    if(@args == 0) {
	if (scalar(keys %cron)) {
        	$ui->printf("(%2s  %-17s  %-6s %s)\n", "Id", "When", "Repeat", "Command");
		my $k;
		foreach $k (sort keys %cron) {
       	    	my($sec,$min,$hour,$mday,$mon,$year) = localtime($cron_when{$k});
	    	$ui->printf("(%2d  %02d:%02d:%02d %02d/%02d/%02d  %6s %s)\n",
				$k, $hour, $min, $sec, $mon+1, $mday, $year%100, $cron_interval{$k}, $cron{$k});
		}
	} else {
		$ui->print("(There are no scheduled events)\n");
	}
	return;
    }

    # Cancel one or more tasks.
    if ($args[0] eq "cancel" || $args[0] eq "delete") {
	shift @args;
	while (@args) {
	    my $tbc = shift @args;
	    $ui->print("(cancelling task $tbc ($cron{$tbc}))\n");
	    TLily::Event::time_u($cron_id{$tbc});
	    delete $cron{$tbc};
	    delete $cron_id{$tbc};
	    delete $cron_interval{$tbc};
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
    my $serv = TLily::Server::active();

    $cron{$id} = $cmd;
    $cron_when{$id} = time + $interval;

    my $hid = $id;  # because $id will change, and the closure will see that.
                    # ($id is not local).
    my $sub = sub {
	my($handler) = @_;
	my $ui = TLily::UI::name($ui_name);
	$ui->print("($itext has passed, running \"$cmd\".)\n");
	foreach my $task (split(/\\n/, $cmd)) {
		TLily::Event::send(type => 'user_input',
			   	ui   => $ui,
			   	server => $serv,
			   	text => $task);
	}
	unless (defined $handler->{interval}) {
	    delete $cron{$hid};
	    delete $cron_id{$hid};
	    delete $cron_interval{$hid};
	    delete $cron_when{$hid};
	} else {
            $cron_when{$hid} += $handler->{interval};
        }
    };
    my $h = { after => $interval, call => $sub };
    ($cron_interval{$id} = $h->{interval} = $interval) if ($command eq "every");
    $cron_id{$id} = TLily::Event::time_r($h);
    my $servname = $serv->name();

    $ui->print("($command $interval, I will run \"$cmd\" [id $id, $servname].)\n");
    $id++;
    return 0;
}
command_r("cron"  => sub { cron_command("cron", @_); });
command_r("after" => sub { cron_command("after",@_); });
command_r("every" => sub { cron_command("every",@_); });
shelp_r("cron" => "Run a command at a designated time.");
help_r("cron" => $cron_help);
shelp_r("after" => "Run a command after a given amount of time.");
help_r("after" => $cron_help);
shelp_r("every" => "Run a command every given amount of time.");
help_r("every" => $cron_help);

sub unload() {
  my $ui = TLily::UI::name("main");
  foreach my $k (sort keys %cron) {
    $ui->print("(cancelling task $k ($cron{$k}))\n");
    TLily::Event::time_u($cron_id{$k});
    delete $cron{$k}; delete $cron_id{$k};
    delete $cron_when{$k}; delete $cron_interval{$id};
  }
}

1;
