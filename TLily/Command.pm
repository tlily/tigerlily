# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Command.pm,v 1.5 1999/10/02 02:45:05 mjr Exp $
package TLily::Command;

use strict;
use Exporter;
use TLily::Event qw(&event_r);

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);

@EXPORT_OK = qw(&cmd_process);

my %pending_commands = ();
my %active_commands = ();

sub init () {
    # The order of these handlers is important!
    event_r(type => 'begincmd',
	    call => sub {
		my($e) = @_;
		my $cmd = $e->{command};
		my $id = $e->{cmdid};

		if (defined $pending_commands{$cmd}) {
		    $active_commands{$id} = $pending_commands{$cmd};
		    delete $pending_commands{$cmd};
		}
		return 0;
	    }); 

    event_r(type => 'all',
	    call => sub {
		my($e) = @_;
		my $id = $e->{cmdid};

		return 0 if ($e->{type} eq 'endcmd');
		return 0 unless ($id);
		my $f = $active_commands{$id};
		&$f($e) if (defined $f);
		return 0;
	    });

    event_r(type => 'endcmd',
	    call => sub {
		my($e) = @_;
		my $id = $e->{cmdid};

		if (defined $active_commands{$id}) {
		    my $f = $active_commands{$id};
		    &$f($e) if (defined $f);
		    delete $active_commands{$id};
		}
		return 0;
	    });
}


sub cmd_process ($$) {
    my($c, $f) = @_;
    $pending_commands{$c} = $f;
    my $server = TLily::Server::active();
    $server->sendln($c);
}


1;
