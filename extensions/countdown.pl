# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/countdown.pl,v 1.1 1999/03/17 00:08:16 josh Exp $
#
# Put a countdown timer on your status line.
#

use strict;

my $end_t;
my $interval;
my $interval_c;
my $timer = '';
my $event_id;

sub set_timer {
    my ($ui) = @_;

    my $r = $end_t - time;
    my $u = int($r / $interval);
    $u ||= 1;

    if($r <= $interval) {
	if($interval == 60*60*24) {
	    $interval_c = 'h';
	    $interval = 60*60;
	    $u = int($r / $interval);
	}
	elsif($interval == 60*60) {
	    $interval_c = 'm';
	    $interval = 60;
	    $u = int($r / $interval);
	}
    }

    my $l = $r % $interval;

    if ($r <= 0) {
	$timer = '';
	$ui->set(countdown => $timer);

	undef $event_id;
	$ui->set(countdown => $timer);
	$ui->bell();
	$ui->print("(Timer has expired)\n");
	return 0;
    }

    if($config{countdown_fmt}) {
	my($days,$hrs,$mins,$secs,$rem);
	$rem = $r;
	$days = int($rem / (60*60*24));
	$rem = int($rem % (60*60*24));
	$hrs = int($rem / (60*60));
	$rem = int($rem % (60*60));
	$mins = int($rem / (60));
	$rem = int($rem % (60));
	$secs = int($rem);
	my $str = $config{countdown_fmt};

	if($days > 0) { $str =~ s/\%\{(\d*)d(.*?)\}/sprintf("%$1d",$days).$2/e; }
	else { $str =~ s/\%\{(\d*)d.*?\}//; }

	if($hrs > 0) { $str =~ s/\%\{(\d*)h(.*?)\}/sprintf("%$1d",$hrs).$2/e; }
	else { $str =~ s/\%\{(\d*)h.*?\}//; }

	if($mins > 0) { $str =~ s/\%\{(\d*)m(.*?)\}/sprintf("%$1d",$mins).$2/e; }
	else { $str =~ s/\%\{(\d*)m.*?\}//; }

	if($interval_c eq 's' && $secs > 0) {
	    $str =~ s/\%\{(\d*)s(.*?)\}/sprintf("%$1d",$secs).$2/e;
	} else {
	    $str =~ s/\%\{(\d*)s.*?\}//;
	}

	$timer = $str;
    }
    else {
	$timer = $u . $interval_c;
    }
    $ui->set(countdown => $timer);

    $event_id = TLily::Event::time_r(after => $l || $interval,
				     call  => sub { set_timer($ui) });

    return 0;
}

sub countdown_cmd {
    my($ui,$args) = @_;

    if ($args eq 'off') {
	time_u($event_id) if ($event_id);
	$timer = '';
	$ui->set(countdown => $timer);
	undef $event_id;
	return 0;
    }

    if ($args !~ /^(\d+)([dhms]?)$/) {
	$ui->print("Usage: %countdown [<time> | off]\n");
	return 0;
    }

    $ui->define(countdown => 'right');

    if ($2 eq 'd') {
	$interval = 60 * 60 * 24;
	$interval_c = 'd';
    } elsif ($2 eq 'h') {
	$interval = 60 * 60;
	$interval_c = 'h';
    } elsif ($2 eq 'm') {
	$interval = 60;
	$interval_c = 'm';
    } else {
	$interval = 1;
	$interval_c = 's';
    }

    $end_t = time + ($1 * $interval);

    set_timer($ui);
    return 0;
}

command_r('countdown', \&countdown_cmd);
shelp_r('countdown',
		    'Display a countdown timer on the status line');
help_r('countdown', <<END
Usage: %countdown <time>
       %countdown off

Displays a countdown timer on the status line.  The time may be specified in several ways:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days

You may use "%countdown off" to cancel an existing countdown.
END
		   );
