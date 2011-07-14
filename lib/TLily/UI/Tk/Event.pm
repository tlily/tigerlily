#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

package TLily::UI::Tk::Event;

use IO::Select;
use strict;
use vars qw($inMainLoop);
use TLily::Config qw(%config);

=head1 NAME

  TLily::UI::Tk::Event - The Tk UI\'s replacement event core

=head1 SYNOPSIS

use TLily::UI::Tk::Event;

=head1 DESCRIPTION

This class implements the TK UI\'s replacement to TLily\'s event core.

=cut

my ($rout, $wout, $eout, $nfound) = ("", "", "", 0);

sub new {
    print STDERR ": TLily::UI::Tk::Event::new\n" if $config{ui_debug};
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{mainwin} = shift;

    $self->{readable} = {};
    $self->{writable} = {};

    bless $self, $class;
}


sub io_r {
    print STDERR ": TLily::UI::Tk::Event::io_r\n" if $config{ui_debug};
    my($self, $fileno, $handle, $mode) = @_;

    print STDERR "handle: ", $handle, "\n" if $config{ui_debug};
    print STDERR "fileno: ", $fileno, "\n" if $config{ui_debug};
    print STDERR "mode: ", $mode, "\n" if $config{ui_debug};

    $self->{rselect} ||= IO::Select->new;
    $self->{eselect} ||= IO::Select->new;
    $self->{wselect} ||= IO::Select->new;

    if ($^O eq 'MSWin32') {
        if($mode =~ /r/) { $self->{rselect}->add($handle); }
        if($mode =~ /e/) { $self->{eselect}->add($handle); }
        if($mode =~ /w/) { $self->{wselect}->add($handle); }

        if (! $self->{_callback_installed}) {
            $self->{mainwin}->repeat(50 => sub { $self->callback() } );
            $self->{_callback_installed} = 1;
        }

    } else {
        if($mode =~ /(e|r)/) {
            $self->{readable}->{$handle} = $fileno;
            $self->{mainwin}->fileevent(\$handle, "readable",
                                        [ $self, "callback", "readable", $handle ]);
        }
        if($mode =~ /w/) {
            $self->{writable}->{$handle} = $fileno;
            $self->{mainwin}->fileevent(\$handle, "writable",
                                        [ $self,"callback", "writable", $handle ]);
        }
    }
}

sub io_u {
    print STDERR ": TLily::UI::Tk::Event::io_u\n" if $config{ui_debug};
    my($self, $fileno, $handle, $mode) = @_;

    print STDERR "handle: ", $handle, "\n" if $config{ui_debug};
    print STDERR "fileno: ", $fileno, "\n" if $config{ui_debug};
    print STDERR "mode: ", $mode, "\n" if $config{ui_debug};

    if ($^O eq 'MSWin32') {
        if($mode =~ /r/) { $self->{rselect}->remove($handle); }
        if($mode =~ /e/) { $self->{eselect}->remove($handle); }
        if($mode =~ /w/) { $self->{wselect}->remove($handle); }
    } else {
        if($mode =~ /(e|r)/) {
            delete $self->{readable}->{$handle};
            $self->{mainwin}->fileevent($handle, "readable", "");
        }
        if($mode =~ /w/) {
            delete $self->{writable}->{$handle};
            $self->{mainwin}->fileevent($handle, "writable", "");
        }
    }
}


sub run {
    my($self, $timeout) = @_;
    print STDERR ": TLily::UI::Tk::Event::run\ntimeout=$timeout\n" if $config{ui_debug};

    ($rout, $wout, $eout, $nfound) = ("", "", "", 0);

    $self->{alarm} = 0;
    $self->{after} = $self->{mainwin}->after($timeout*1000,
                                             sub {$self->{alarm} = 1});
    unless ($inMainLoop) {
        local $inMainLoop = 1;
        while (Tk::MainWindow->Count && !$self->{alarm} && !$nfound) {
#            print STDERR "timeout:", $timeout, "\n" if $config{ui_debug};
#            print STDERR "Count:", Tk::MainWindow->Count, "\n" if $config{ui_debug};
#            print STDERR "alarm:", $self->{alarm}, "\n" if $config{ui_debug};
#            print STDERR "nfound:", $nfound, "\n" if $config{ui_debug};
            eval {Tk::DoOneEvent(0)};
            if($@) {
                print STDERR "Eval error: $@\n";
            }
        }
#        print STDERR "<2>Count:", Tk::MainWindow->Count, "\n" if $config{ui_debug};
#        print STDERR "<2>alarm:", $self->{alarm}, "\n" if $config{ui_debug};
#        print STDERR "<2>nfound:", $nfound, "\n" if $config{ui_debug};
        $inMainLoop=0;
    }
#    print STDERR "<3>Count:", Tk::MainWindow->Count, "\n" if $config{ui_debug};
#    print STDERR "<3>alarm:", $self->{alarm}, "\n" if $config{ui_debug};
#    print STDERR "<3>nfound:", $nfound, "\n" if $config{ui_debug};
    $self->{mainwin}->after("cancel", $self->{after});
    $self->{alarm} = 0;

    return ($rout, $wout, $eout, $nfound);
}

sub callback {
    if ($^O eq 'MSWin32') {
        my ($self) = @_;

        print STDERR ": TLily::UI::Tk::Event::callback\n" if $config{ui_debug};
        $nfound = select($rout=$self->{rselect}->bits, $wout=$self->{wselect}->bits, $eout=$self->{eselect}->bits, 0);

    } else {
        my($self, $mode, $handle) = @_;
        print STDERR ": TLily::UI::Tk::Event::callback ($handle is $mode)\n" if $config{ui_debug};
        if($mode eq "readable") {
            vec($rout, $self->{$mode}->{$handle}, 1) = 1;
            $nfound++;
        } elsif($mode eq "writable") {
            vec($wout, $self->{$mode}->{$handle}, 1) = 1;
            $nfound++;
        }
    }
}

sub activate { $_[0]->{alarm} = 1 }

1;
