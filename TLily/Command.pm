# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Command.pm,v 1.2 1999/02/27 00:52:37 josh Exp $
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
    my $server = TLily::Server::name();
    $server->sendln($c);
}


1;
