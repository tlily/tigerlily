#!/usr/bin/perl -w
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/tlily.PL,v 1.41 1999/09/17 07:20:18 josh Exp $

use strict;
use Config;
use TLily::Version;

# Find perl
my $PERL = $Config{'startperl'} ? $Config{'startperl'}     : 
           $Config{'perlpath'}  ? "#!".$Config{'perlpath'} :
                                  "#/usr/bin/perl";

my $perl_exec = $Config{'perl'};

# On broken systems like RPI's, try to locate perl in the user's path
if(length $PERL > 32) {
    my $P;
    foreach $P (split(/:/,$ENV{PATH})) {
	$PERL = "$P/$perl_exec";
	last if -x $PERL;
    }
    $PERL = '#!'.$PERL;
}

$PERL .= " -w" if $ENV{DASH_W};

# If the length is still too long, complain
if(length $PERL > 32) {
    warn "WARNING: Path to perl interpreter is long;",
	" tlily may not work right.\n";
}

# calculate a fallback value for EAGAIN in case errno.ph does not work.
local(*F);
open(F,">/tmp/en.c") || die "Can't write to /tmp/en.c: $!\n";
print F <<EOF;
#include <stdio.h>
#include <sys/errno.h>

int main (int argc, char* argv[]) {
   printf("EAGAIN=\%d\\n",EAGAIN);
   return(0);
}
EOF
close(F);
system("$Config{cc} /tmp/en.c -o /tmp/en");
`/tmp/en` =~ /EAGAIN=(\d+)/;
my $fallback_EAGAIN = $1 || "undef";
unlink("/tmp/en.c","/tmp/en");

my $PREFIX = '.';
    my $LIBDIR    = $ENV{TL_LIBDIR} || '.';
    my $LIBMODDIR = $ENV{TL_LIBDIR} || '.';
    my $LIBEXTDIR = "$ENV{TL_LIBDIR}/extensions" || './extensions';
    my $ETCDIR    = $ENV{TL_ETCDIR} || '.';

    my $file = 'tlily';
    print "Writing $file\n";
    if(-f $file) { unlink $file; }
	
    local(*OFH);
    open(OFH, ">$file") or die "Cannot open $file: $!\n";
	
    while(<DATA>) {
	s|\@\@PERL\@\@|$PERL|;
	s|\@\@LIBDIR\@\@|$LIBDIR|;
	s|\@\@LIBMODDIR\@\@|$LIBMODDIR|;
	s|\@\@LIBEXTDIR\@\@|$LIBEXTDIR|;
	s|\@\@ETCDIR\@\@|$ETCDIR|;
	s|\@\@EAGAIN\@\@|$fallback_EAGAIN|;	
	print OFH $_;
    }
    close(OFH);
    chmod(0555, $file); # To discourage editing

__END__
@@PERL@@
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

require 5.00307;

$TL_ETCDIR = "@@ETCDIR@@";
$TL_LIBDIR = "@@LIBDIR@@";
$TL_EXTDIR = "@@LIBEXTDIR@@";

$fallback_EAGAIN = @@EAGAIN@@;

use strict;
use lib qw(@@LIBMODDIR@@);
use vars qw($EAGAIN);

use TLily::Event;
use TLily::Config;
use TLily::UI;
use TLily::Server;
use TLily::Server::SLCP;
use TLily::User;
use TLily::Extend;
use TLily::Version;
use TLily::Command;
use TLily::Bot;

if ( -f 'tlily.PL' ) {
    my @tstat = stat('tlily.PL');
    my @mstat = stat($0);
    if ($tstat[9] > $mstat[9]) {
	print "tlily.PL is newer than $0 -- rerun make.\n";
	exit;
    }
}

eval { require "errno.ph"; EAGAIN(); };
if ($@) { 
    print "WARNING: Unable to load errno.ph successfully.\n";
    $EAGAIN = $::fallback_EAGAIN;
    die "No fallback value for EAGAIN defined!  Unable to continue.\n" 
       unless $EAGAIN;       
    print "         Using EAGAIN=$EAGAIN\n";
} else {
    $EAGAIN = EAGAIN()
};

TLily::Config::init();
TLily::Event::init();
TLily::Command::init();
TLily::Bot::init();
my $ui = load_ui();

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
	    $ui->style("slcp");
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



sub load_ui {
    my %available;

    $config{UI} ||= "Curses";

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

    # nope?  ok, fall back to Curses.
    if (! $available{$config{UI}}) {
	print "UI \"$config{UI}\" was not found.\n";
	print "Press ENTER to try the default UI, or Control-C to quit.\n";
	<STDIN>;
	$config{UI}="Curses";
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
    $ui->style("default");
}

=head1 NAME

tlily - TigerLily

=head1 SYNOPSIS

    tlily [-h <host>] [-p <port>] [-UI=<UI Name>]

=head1 DESCRIPTION

This is TigerLily.  Need we say more?  Yes.

=head1 SEE ALSO

F<http://www.hitchhiker.org/tigerlily/>

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
