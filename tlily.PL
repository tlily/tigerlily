#!/site/t/gnu/bin/perl -w

require 5.00307;

#$TL_ETCDIR=".";
#$TL_LIBDIR="LC";
$TL_EXTDIR="extensions";

use strict;
use vars qw($event);
use lib qw(.);

use LC::Event;
use LC::UI;
use LC::UI::Curses;
use LC::Server;
use LC::User;
use LC::Extend;
use LC::Global qw($event);

if ( -f 'tlily.PL' ) {
	my @tstat = stat('tlily.PL');
	my @mstat = stat($0);
	if ($tstat[9] > $mstat[9]) {
		print "tlily.PL is newer than $0 -- rerun Build.PL.\n";
		exit;
	}
}

$event = LC::Event->new();
my $ui = LC::UI::Curses->new(name => 'main', event => $event);

LC::User::init;
LC::Extend::cmd_init;

LC::Extend::load("server", $ui);
LC::Extend::load("output", $ui);

LC::User::command_r(quit => sub { exit; });
LC::User::command_r(foo  => sub { $ui->print("Foo you too!\n"); });

# remove
$ui->defcstyle("status" => 'yellow', 'blue', 'bold');

$SIG{__WARN__} = \&sig_warn;
sub sig_warn {
	$SIG{__WARN__} = \&sig_warn;
	$ui->print("WARNING: ", $_[0]);
}

$SIG{PIPE} = \&sig_pipe;
sub sig_pipe {
	$SIG{PIPE} = \&sig_pipe;
	my ($package, $filename, $line, $subroutine,
	    $hasargs, $wantarray, $evaltext, $is_require) = caller(1);

	$ui->print("WARNING: Caught SIGPIPE. (from $package::$subroutine)\n");
}

my $sigint = 0;
sub sigint {
	exit if ($sigint);
	$ui->print("(hit ctrl-c again within 5 seconds to exit)\n");
	$sigint = 1;
	$event->time_r(after => 5,
		       call  => sub {
			       $sigint = 0;
			       $ui->print("(you waited too long to hit ctrl-c; exit aborted)\n");
		       });
}
$ui->command_r("interrupt", \&sigint);
$ui->bind("C-C" => "interrupt");

sub output_handler {
	my($event, $handler) = @_;
	if ($event->{ui_name}) {
		my $ui = LC::UI::name($event->{ui_name});

		if ($event->{NOTIFY} && $event->{formatter}) {
			$event->{formatter}->($ui, $event);
		} elsif ($event->{NOTIFY} && $event->{indent}) {
			$ui->indent($event->{indent});
			$ui->print($event->{text}, "\n");
			$ui->indent();
		} elsif ($event->{NOTIFY}) {
			$ui->print($event->{text}, "\n");
		}

		if ($event->{BEEP}) {
			$ui->bell();
		}
	}

	return;
}
$event->event_r(type  => "all",
		order => "after",
		call  => \&output_handler);

show_banner();
    
while (1) {
	eval { $event->loop; };

	# Normal exit.
	if ($@ eq '') {
		$ui->print("*** Exiting.");
		exit;
	}

	# Non-fatal errors.
	if ($@ =~ /^Undefined subroutine/) {
		$ui->print("ERROR: ", $@);
		next;
	}
	
	# Oh, well.  Guess we have a problem.
	die;
}

# This screws up cperl something terrible, so put it at the end where we
# don't care.
sub show_banner() {
	$ui->print(<<END
     ("`-/")_.-'"``-._ 
      . . `; -._    )-;-,_`)          Tigerlily
     (v_,)'  _  )`-.\  ``-'          "Feel Free"
    _.- _..-_/ / ((.'
  ((,.-'   ((,/ 
------------------------------------------------------------------------------
END
);
}


1;
