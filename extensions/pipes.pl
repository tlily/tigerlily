# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/pipes.pl,v 1.6 1999/10/23 06:16:01 josh Exp $
#
# Piped command processing.
#

my $counter = 0;
sub pipe_handler {
    my($server, $ui, $cmd) = @_;

    my $lcmd;
    my $run = '';
    my $mode = 0;
    while ($cmd) {
	if ($cmd =~ /^\|\s*(.*)/) {
	    break if ($mode != 2);
	    $cmd = $1;
	    $run .= "| ";
	    $mode = 1;
	} elsif ($cmd =~ /^>\s*(\S+)\s*(.*)/) {
	    break if ($mode != 2);
	    $cmd = $2;
	    $run .= "> $1 ";
	    $mode = 3;
	} elsif ($cmd =~ /^([^|>]*)(.*)/) {
	    if ($mode == 0) {
		$cmd = $2;
		$lcmd = $1;
		$mode = 2;
	    } elsif ($mode == 1) {
		$cmd = $2;
		$run .= "$1 ";
		$mode = 2;
	    } else {
		break;
	    }
	} else {
	    break;
	}
    }

    if ($cmd || $mode == 1) {
	$ui->print("(parse error)\n");
	return 1;
    }

    my $tmpfile = "$::TL_TMPDIR/tlily-out-" . $counter++ . "-" . $$;

    if ($mode != 3) {
	$run .= "> $tmpfile";
	local(*FD);
	sysopen(FD, $tmpfile, O_RDWR|O_CREAT, 0600);
	close(FD);
    }

    my $fd = "pipes--fd--" . $counter;
    my $rc = open($fd, $run);
    if ($rc == 0) {
	my $l = $@; $l =~ s/(\\<)/\\$1/g;
	$ui->print("Error in pipe: $l\n");
    }

    $server->cmd_process($lcmd, sub {
	my($event) = @_;
	$event->{NOTIFY} = 0;
	if ($event->{type} eq 'begincmd') {
	} elsif ($event->{type} eq 'endcmd') {
	    close $fd;
	    if ($mode != $3) {
		local(*FD);
		open(FD, "<$tmpfile");
		my @l = <FD>;
		foreach (@l) {
		    chomp;
		    s/(\\<)/\\$1/g;
		    $ui->print($_, "\n");
		}
		close(FD);
		unlink($tmpfile);
	    }
	} elsif (defined $event->{text}) {
	    if ($fd) {
		my $rc = print $fd $event->{text}, "\n";
		unless ($rc) {
		    close $fd;
		    undef $fd;
		}
	    }
	}
    });

    return 1;
}

sub and_handler {
    my($event, $handler) = @_;
    if ($event->{text} =~ /^\s*&\s*(.*?)\s*$/) {
        pipe_handler(active_server(), $event->{ui}, $1);
        return 1;
    }
    return;
}

event_r(type => 'user_input',
        call => \&and_handler);
command_r("pipe", sub { pipe_handler(active_server(), @_); });
shelp_r("pipe", "Pipe lily commands through shell commands");
help_r("pipe", "
Usage: %pipe /who | grep foo
       &/review detach > output

A piped command is begun with a \"&\".  The first component should be a lily \
command.  The command output may be filtered through shell commands, \
separated by pipes.  The final output may be redirected through a file \
with \"> file\".  If the output is not sent to a file, it is printed to the \
screen upon command termination.

WARNING!  This command will NOT work properly with anything that generates \
text that needs to be formatted by the client.  This extension needs a \
complete redesign.  It's main use, however, is to deal with /review, which \
should work without problems.
");
