#!/usr/bin/perl
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2003  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Id$

require 5.00307;
use strict;
use vars qw($EAGAIN $TL_ETCDIR $TL_LIBDIR $TL_TMPDIR $TL_LIBMODDIR);

sub directory_init {
    $::TL_ETCDIR = "."          unless defined($::TL_ETCDIR);
    $::TL_LIBDIR = "lib"        unless defined($::TL_LIBDIR);
    $::TL_EXTDIR = "extensions" unless defined($::TL_EXTDIR);
    
    $::TL_TMPDIR = "/tmp";
    if ($^O =~ /cygwin/) {
        $::TL_TMPDIR = $ENV{TEMP} || 'C:\WINDOWS\TEMP';
        $::TL_TMPDIR =~ s/^.://g;
        $::TL_TMPDIR =~ s/\\/\//g;
    }
    
    if ($^O eq 'MSWin32') {
        $::TL_TMPDIR = $ENV{TEMP} || 'C:\WINDOWS\TEMP';
    }
    
    if (!defined($::TL_LIBMODDIR) ||
	($::TL_LIBMODDIR ne "//INTERNAL")) {
	unshift @INC, $::TL_LIBMODDIR;
    }    
}

sub platform_init {   
    if ($TLily::Version::VERSION =~ /-aqua$/) {
        eval {
            require Foundation;
            require Foundation::Functions;
            require AppKit;
            require AppKit::Functions;
            require MyApp;
        };
        # This seems... a tad evil.
        $::TL_LIBDIR = $INC[0];
        $::TL_EXTDIR = $INC[0]. "/extensions";
        push @INC,$::TL_LIBDIR;
    }

    if ($^O eq 'MSWin32') {
        $TLily::Version::VERSION .= "-ap";
    }
    
    if ($^O =~ /cygwin/) {
        $EAGAIN = $::fallback_EAGAIN;
    } else {
        $EAGAIN = eval { require "Errno.pm"; Errno::EAGAIN(); };
        $EAGAIN = eval { require "errno.ph"; EAGAIN(); } if $@;
        if ($@) { 
            if (defined $::fallback_EAGAIN) {
    	        print STDERR "WARNING: Using fallback EAGAIN.\n";
                $EAGAIN = $::fallback_EAGAIN;
            } elsif ($::TL_LIBMODDIR !~ m|^//INTERNAL|) {
                if (! -f ".tlily-eagain") {
                    $EAGAIN = `$^X tools/find_eagain`;
                    if ($EAGAIN =~ /^(\d+)/) {
                        print STDERR "Saving EAGAIN to .tlily-eagain.\n";
                        $EAGAIN = $1;
                        local *FH;
                        open(FH, "> .tlily-eagain") or die ".tlily-eagain: $!\n";
                        print FH $EAGAIN, "\n";
                    } else {
                        die "Cannot determine value for EAGAIN.\n";
                    }
                } else {
                    local *FH;
                    open(FH, ".tlily-eagain") or die ".tlily-eagain: $!\n";
                    $EAGAIN = <FH>;
                    if ($EAGAIN =~ /^(\d+)/) {
                        $EAGAIN = $1;
                    } else {
                        die ".tlily-eagain seems to be corrupt; delete it and try again.\n";
                    }
                }
            } else {
                die "Cannot determine value for EAGAIN.\n";
            }
        }
    }
}

BEGIN { directory_init(); }

use lib $TL_LIBDIR;
use TLily::Event;
use TLily::Config;
use TLily::UI;
use TLily::Server;
use TLily::Server::SLCP;
use TLily::User;
use TLily::Extend;
use TLily::Version;
use TLily::Utils;

BEGIN { platform_init(); }

TLily::Config::init();
TLily::Event::init();

if(defined $config{bot}) {
    eval "use TLily::Bot; TLily::Bot::init();";
}

my $nsApp;
if ($TLily::Version::VERSION =~ /-aqua$/) {

    # Get a reference to the shared NSApplication object
    $nsApp = NSApplication->sharedApplication;
    
    # Load the main menu Nib, making the NSApplication object its owner
    NSBundle->loadNibNamed_owner("MainMenu", $nsApp);
}

my $ui = load_ui();

if ($TLily::Version::VERSION =~ /-aqua$/) {
    # Make the controller the delegate of the application
    $nsApp->setDelegate($ui);
}

show_banner();

TLily::User::init;
TLily::Extend::init;

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
	} elsif ($event->{NOTIFY} && $event->{slcp}) {
	    $ui->style($event->{slcp_fmt} || "slcp");
	    $ui->print($event->{text}, "\n");
	    $ui->style("default");
	} elsif ($event->{NOTIFY}) {
	    $ui->print($event->{text}, "\n");
	}
	
    }
    
    return 0;
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
			call     => sub { 
			    TLily::Event::send(type => 'user_input',
					       ui   => $ui,
					       text => $_[1]);
			    # or, to bypass the normal handlers (and break
			    # %commands)
			    #$server->sendln($_[1]); 
			});
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
		   ui   => $ui,
		   text => "%connect") unless ($config{noauto});


if ($TLily::Version::VERSION =~ /-aqua$/) {
    # Start the NSApplication object's run loop
    $nsApp->run;
} else {
   # use the normal event loop.
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
}
                   
sub load_ui {
    my %available;

    my $default_UI = "TextWindow";

    if ($TLily::Version::VERSION =~ /-aqua$/) {
        $default_UI = "Cocoa";
    }
 
    $config{UI} ||= $default_UI;

    if ($::TL_LIBDIR =~ m|^//INTERNAL|) {
	my $ui = eval "TLily::UI::$config{UI}->new(name => 'main');";
	if ($@) {
	    print STDERR "ERROR: Unable to load UI \"$config{UI}\".\n$@\n";
	    exit;
	}
	return $ui;
    }

    opendir(D,"$::TL_LIBDIR/TLily/UI");
    map { s/.pm$//; $available{$_}++; } grep /\.pm$/, readdir(D);
    closedir D;

    # did they specify a substring or case-insensitive match of an available
    # UI?
    if (! $available{$config{UI}}) {
	foreach (keys %available) { 
	    if (/$config{UI}/i) { $config{UI} = $_; }
	}
    }

    # nope?  ok, fall back to TextWindow.
    if (! $available{$config{UI}}) {
	print "UI \"$config{UI}\" was not found.\n";
	print "Press ENTER to try the default UI, or Control-C to quit.\n";
	<STDIN>;
	$config{UI}="TextWindow";
    }

    # OK, load the UI..
    eval "use TLily::UI::$config{UI}; \$ui = TLily::UI::$config{UI}->new(name => 'main');";
    if ($@) {
	warn "ERROR: Unable to load UI \"$config{UI}\".\n$@\n";
	# sometimes they die() in the new(), leaving a half-allocated UI.
	TLily::UI::purge("main");
    }
    
    die "FATAL: Unable to load a UI module.  Exiting.\n" unless $ui;

    return $ui;
}


# This screws up cperl something terrible, so put it at the end where we
# don't care.
sub show_banner() {
    $ui->prints(yellow => qq[     ("`-/")_.-'"``-._ \n],
                yellow => qq[      . . `; -._    )-;-,_`)],
                                             green  => qq[          TigerLily $TLily::Version::VERSION\n],
                yellow => qq[     (v_,)'  _  )`-.\  ``-'],
                                            bwhite => qq[             "Feel Free"\n],
                yellow => qq[    _.- _..-_/ / ((.'\n],
                yellow => qq[  ((,.-'   ((,/ \n],
                bwhite => qq[------------------------------------------------------------------------------\n]);
# ` This comment with the backquote is here merely to let cperl work again.
    $ui->style("default");
}


=head1 NAME

tlily - TigerLily

=head1 SYNOPSIS

    tlily [-h <host>] [-p <port>] [-UI=<UI Name>]

=head1 DESCRIPTION

This is TigerLily.  Need we say more?  Yes.

=head1 SEE ALSO

F<http://www.tlily.org/tigerlily/>

For hacking on tlily, you may want to see
L<TLily::UI>,
L<TLily::User>,
L<TLily::Event>,
L<TLily::Registrar>,
L<TLily::Daemon>,
L<TLily::Server>,
L<TLily::Daemon::HTTP>,
L<extensions::slcp_parse>,
and 
L<extensions::slcp_output>.

=head1 BUGS

Many.  We will eventually fix them and cause more.

=cut
1;
