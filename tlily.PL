@@PERL@@

require 5.00307;

#$TL_ETCDIR=".";
$TL_LIBDIR="@@LIBDIR@@";
$TL_EXTDIR="@@LIBEXTDIR@@";

use strict;
use lib qw(@@LIBMODDIR@@);

use TLily::Event;
use TLily::Config;
use TLily::UI;
use TLily::UI::Curses;
use TLily::Server;
use TLily::Server::SLCP;
use TLily::User;
use TLily::Extend;
use TLily::Version;
use TLily::Command;

if ( -f 'tlily.PL' ) {
	my @tstat = stat('tlily.PL');
	my @mstat = stat($0);
	if ($tstat[9] > $mstat[9]) {
		print "tlily.PL is newer than $0 -- rerun Build.PL.\n";
		exit;
	}
}

TLily::Config::init();
TLily::Event::init();
TLily::Command::init();
my $ui = TLily::UI::Curses->new(name => 'main');

# remove
$ui->defstyle('status'  => 'reverse');
$ui->defstyle('sender'  => 'bold');
$ui->defstyle('dest'    => 'bold');
$ui->defstyle('pubhdr'  => 'normal');
$ui->defstyle('pubmsg'  => 'normal');
$ui->defstyle('privhdr' => 'normal');
$ui->defstyle('privmsg' => 'normal');
$ui->defstyle('emote'   => 'normal');
$ui->defcstyle('status' => 'yellow', 'blue', 'bold');
$ui->defcstyle('pubhdr' => 'green', 'white', 'normal');
$ui->defcstyle('pubmsg' => 'green', 'white', 'normal');

show_banner();
    
TLily::User::init;
TLily::Extend::cmd_init;

TLily::User::command_r(quit => sub { exit; });

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
	TLily::Event::time_r(after => 5,
		             call  => sub {
			             $sigint = 0;
			             $ui->print("(you waited too long to hit ctrl-c; exit aborted)\n");
		             });
}
$ui->command_r("interrupt", \&sigint);
$ui->bind("C-c" => "interrupt");

sub output_handler {
	my($event, $handler) = @_;
	if ($event->{ui_name}) {
		my $ui = TLily::UI::name($event->{ui_name});

		if ($event->{BELL}) {
			$ui->bell();
		}

		if ($event->{NOTIFY} && $event->{formatter}) {
			$event->{formatter}->($ui, $event);
		} elsif ($event->{NOTIFY} && $event->{indent}) {
			$ui->indent($event->{indent});
			$ui->print($event->{text}, "\n");
			$ui->indent();
		} elsif ($event->{NOTIFY}) {
			$ui->print($event->{text}, "\n");
		}
	}

	return;
}
TLily::Event::event_r(type  => "all",
		      order => "after",
		      call  => \&output_handler);

sub prompt_handler {
	my($event, $handler) = @_;
	my $server = $event->{server};

	if (defined($event->{value})) {
		$server->sendln($event->{value});
		return;
	}

	if ($event->{ui_name}) {
		my $ui = TLily::UI::name($event->{ui_name});
		$ui->prompt_for(prompt   => $event->{text},
				password => $event->{password},
		                call     => sub { $server->sendln($_[1]); });
		return;
	}

	# This should never happen.
	warn "Unanswerable prompt: $event->{text}\n";
	return;
}
TLily::Event::event_r(type  => "prompt",
		order => "after",
		call  => \&prompt_handler);

TLily::Extend::load_extensions($ui);

$ui->print("\n");

TLily::Event::send(type => 'user_input',
		   text => "%connect");

while (1) {
	eval { TLily::Event::loop; };

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
      . . `; -._    )-;-,_`)        Tigerlily $TLily::Version::TL_VERSION
     (v_,)'  _  )`-.\  ``-'          "Feel Free"
    _.- _..-_/ / ((.'
  ((,.-'   ((,/ 
------------------------------------------------------------------------------
END
);
}


1;
