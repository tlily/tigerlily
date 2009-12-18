# -*- Perl -*-
# $Id$

#
# A Biff module
#
# TODO:
#  - Add support for regular POP
#  - Independant check intervals for each drop
#  - multiple UI handling?
#
use IO::Socket;
use IO::Select;
use strict;
no strict "refs";

=head1 NAME

biff.pl - Watch mail drops for incoming mail

=head1 DESCRIPTION

This extension watches mail drops for incoming mail, and alerts the user
when new mail is detected, both audibly, and in the status bar.

=head1 CONFIGURATION

=over 10

=item biff_drops

A list of mail drops to check for incoming mail.

=cut

shelp_r('biff_drops' => 'A list of mail drops.', 'variables');
help_r('variables biff_drops', q{
You can set the list of mail drops to be checked by biff.pl via the
biff_drops configuration variable, by assigning an arrayref of hashrefs to
it, such as:
\$config{biff_drops} = [{type => 'mbox', path => '/home/mjr/Mailbox'}];
Unfortunately, this variable can not yet be set using %set.  You set it
in your tlilyStartup file (see "%help startup.pl"), or by using %eval.

Valid mail drop types and their required elements are:
mbox - Standard Unix mbox file
  path => Absolute path to file
maildir - Maildir (as used in Qmail)
  path => Absolute path to directory
rpimchk - RPI lightweight POP mail check protocol
  host => mailcheck host
  port => mailcheck port (usually 1110)
  user => account username
});

=item biff_interval

The interval between mail drop checks.

=back

=cut

shelp_r('biff_interval' =>
  'The interval between mail drop checks', 'variables');
help_r('variables biff_interval', q{
The biff_interval configuration variable controls the interval between
mail drop polls, in seconds.  If one of your mail drops is not an mbox or
maildir, please be considerate, and keep the interval above 5 minutes.
(That's 300 seconds for you non-math types.)
});

# ' This comment with the single quote is to get [c]perl-mode back on track.

shelp_r('biff', 'Monitor mail spool for new mail');
help_r('biff', q{
Usage: %biff [on|off|list]

Monitors mail drop(s), and displays an indicator on the status line when
new mail arrives.  Will automatically look for MAILDIR, then MAIL
environment variables to determine a single default mail drop, if
none are set in the config variable.  The 'on' and 'off' arguments
turn notification on and off, the 'list' argument lists the maildrops
currently being monitored, and if no argument is given, %biff will list
those maildrops with unread mail.

See "%help variables biff_drops" for how to configure your mail drop list.
});


=head1 COMMANDS

=over 10

=cut

# Set the check interval (in seconds);
my $check_interval = $config{biff_interval} || 60;
my $check_eventid;		# id of the timed event handler for check_drops()
my $biff = '';			# Statusline variable
my $active;			# Is mail notification on?

# List of maildrops to check.  Each element is a hash, which contains access
# and state information for drop.  Listed below are the hash elements used
# for each type of maildrop.  Elements preceded by a '*' are internal, and
# transitory.  All other elements can be set from the config variable.
# (all)
#   type => contains one of the types defined below.
#  *status => The status of the drop.  Should be set either by the
#             check_<type> function, or an iohandler.  Is read by update_biff
#             which ors together the status of all drops, and uses that to
#             set the statusline and/or beep.  One of the following:
#               0 => No unread mail in drop
#               1 => Unread mail in drop
#               3 => New mail has just arrived in drop
# mbox - Standard  Unix mailbox.
#   path => Absolute pathname of the mbox
#  *mtime => mtime of mbox when last checked, as returned by -M
# maildir - Unix maildir.
#   path => Absolute pathname of the maildir
#  *mtime => mtime of most recent new message when last checked, as returned
#            by -M
# rpimchk - RPI lightweight POP check protocol
#   host => POP host
#   port => Port of mailcheck daemon
#   user => username to check
#  *sock => Handle of socket connection to server
#  *request => preconstructed request packet
#  *bytes => Number of bytes waiting for user

my @drops;

# Check functions.  Each function is named check_<type>, and is passed a
# hashRef of the drop.

sub check_mbox(\%) {
    my $mboxRef = shift;
    my $mtime = -M $mboxRef->{path};
    my $atime = -A _;
    my $size = -s _;

    $mboxRef->{status} = 0;	# Default is no unread mail.
    if (-f _ && -s _ && ($mtime < -A _) ) {
	if (($mboxRef->{mtime} == 0) || ($mtime < $mboxRef->{mtime})) {
	    $mboxRef->{mtime} = $mtime;	# Update mtime
	    $mboxRef->{status} = 3; # Ring bell
	} else {
	    $mboxRef->{status} = 1; # Unread mail
	}
    }
}

sub check_maildir(\%) {
    my $mdirRef = shift;
    my $mtime = undef;
    opendir(DH, "$mdirRef->{path}/new/");
    foreach (readdir(DH)) {
	next if /^\./;
	$mtime = ($mtime < -M "$mdirRef->{path}/new/$_")?$mtime:-M _;
    }
    closedir(DH);
    $mdirRef->{status} = 0;	# Default is no unread mail.
    if (defined($mtime)) {
	if ($mdirRef->{mtime} == 0 || $mtime < $mdirRef->{mtime}) {
	    $mdirRef->{mtime} = $mtime;	# Update mtime
	    $mdirRef->{status} = 3; # Ring bell
	} else {
	    $mdirRef->{status} = 1; # Unread mail
	}
    }
}

sub check_rpimchk(\%) {
    my $mchkRef = shift;

    # Send a check request to the server.
    $mchkRef->{sock}->send($mchkRef->{request});
}

sub handle_rpimchk {
    my $evt = shift;

    my $drop;
    foreach $drop (@drops) {
	if (($drop->{type} eq 'rpimchk') && ($drop->{sock} == $evt->{handle})) {
	    my $reply;
	    $evt->{handle}->recv($reply, 256);
	    last if (length($reply) != 6);
	    my ($h1,$h2,$bytes)=unpack("CCN",$reply);
	    last if ($h1 != 0x1 || $h2 != 0x2);
	    if ($bytes == 0) {
		$drop->{status} = 0;
	    } elsif ($bytes == $drop->{bytes}) {
		$drop->{status} = 1;
	    } else {
		$drop->{status} = 3;
	    }
	    $drop->{bytes} = $bytes;
	    last;
	}
    }
    # Since this happens after check_drops finishes, we have to update the
    # biff outselves.
    update_biff();
    return 0;
}

# Passed a hashref, outputs info about a drop to the UI.
sub print_drop {
    my $ui = shift;
    my %drop = %{shift()};

    if ($drop{type} eq 'mbox' || $drop{type} eq 'maildir') {
	$ui->print("($drop{type} $drop{path})\n");
    } elsif ($drop{type} eq 'rpimchk') {
	$ui->print("($drop{type} $drop{user}\@$drop{host}:$drop{port})\n");
    } else {
	$ui->print("(Unknown maildrop type $drop{type})\n");
    }
}

# Goes through the list of drops, checking each one.
sub check_drops {
    my $status = 0;
    my $drop;
    foreach $drop (@drops) {
	&{"check_$drop->{type}"}($drop);
    }
    update_biff();
}

sub update_biff {
    my $status = 0;
    my $ui = ui_name();

    my $drop;
    foreach $drop (@drops) {
	$status |= $drop->{status};
	$drop->{status} &= 1;	# Unset the bell bit.
    }
    if ($status) {
	$biff = "Mail";
	my $ui = ui_name();
	$ui->set(biff => $biff);
	$ui->bell() if ($status == 3);
    } else {
	$biff = '';
	$ui->set(biff => $biff);
    }
}

=item %biff

Turn mail drop checks on or off, or list drops.

=cut

sub biff_cmd {
    my($ui,$args) = @_;

    if ($args eq 'off') {
	if ($active) {
	    event_u($check_eventid) if ($check_eventid);
	    undef $check_eventid;
	    my $drop;
	    foreach $drop (@drops) {
		if ($drop->{type} eq 'rpimchk') {
		    $drop->{sock}->close();
		    TLily::Event::io_u($drop->{r_eventid});
		}
	    }
	    $biff = '';
	    $ui->set(biff => $biff);
	}
	$active = 0;
	$ui->print("(Mail notification off)\n");
	return 0;
    }

    if ($args eq 'on') {
	if ($active) {
	    $ui->print("(Mail notification already on)\n");
	} else {
	    $check_eventid = TLily::Event::time_r(interval => $check_interval,
						  call     => \&check_drops);

	    my $drop;
	    foreach $drop (@drops) {
		$drop->{status} = 0;
		if ($drop->{type} eq 'rpimchk') {
		    $drop->{port} = $drop->{port} || 1110;
		    $drop->{sock} = new IO::Socket::INET(
					  PeerAddr => "$drop->{host}",
					  PeerPort => "mailchk($drop->{port})",
				 	  Proto => "udp");
		    $drop->{request} = pack("CCCa*",0x1,0x1,0x1,$drop->{user});
		    $drop->{bytes} = 0;
		    $drop->{r_eventid} = TLily::Event::io_r(
                                          handle => $drop->{sock},
					  mode => 'r',
				          name => "mchk-$drop->{user}",
				          call => \&handle_rpimchk);
		}
	    }
	    $active = 1;
	}
	$ui->print("(Mail notification on)\n");
	check_drops();
	return 0;
    }

    if ($args eq 'list') {
	if (@drops == undef) {
	    $ui->print("(No maildrops are being monitored)\n");
	} else {
	    $ui->print("(The following maildrops are monitored:)\n");
	    map(print_drop($ui,$_),@drops);
	}
	if ($active) {
	    $ui->print("(Mail notification is on)\n");
	} else {
	    $ui->print("(Mail notification is off)\n");
	}
	return 0;
    }

    if ($args eq '') {
	map(print_drop($ui,$_), grep($_->{status} > 0, @drops)) ||
	  $ui->print("(No unread mail)\n");
	return 0;
    }

    $ui->print("Usage: %biff [on|off|list]\n");
    return 0;
}

# Called when extension is unloaded.  Explicitly deregisters the timed
# handler, due to a bug that prevents it from happening automatically.
sub unload() {
    my $ui = ui_name();
    biff_cmd($ui,'off');
}


# Initialization

# Biff not yet active
$active = 0;

my $ui = ui_name();
# Get maildrop list
if ($config{biff_drops}) {
    $ui->print("(Setting maildrop list from config file)\n");
    @drops = @{$config{biff_drops}};
} else {
    if ($ENV{MAILDIR}) {
	$ui->print("(Setting maildrop to MAILDIR environ)\n");
	push @drops, {'type' => 'maildir', 'path' => $ENV{MAILDIR}};
    } elsif ($ENV{MAIL}) {
	$ui->print("(Setting maildrop to MAIL environ)\n");
	push @drops, {'type' => 'mbox', 'path' => $ENV{MAIL}};
    } else {
	$ui->print("(Can not find a maildrop!)\n");
	return 1;
    }
}

$ui->define(biff => 'right');
$ui->set(biff => $biff);

command_r('biff' => \&biff_cmd);

=back

=cut

# Start biff by default when loaded.
biff_cmd($ui, "on");

1;
