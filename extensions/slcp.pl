# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/Attic/slcp.pl,v 1.1 1999/02/24 01:12:14 neild Exp $

use strict;

use LC::Global qw($event);

=head1 NAME

slcp.pl - The lily event parser

=head1 DESCRIPTION

The parse module translates all output from the server into internal
TigerLily events.  All server protocol support resides here.  We now support
the SLCP protocol.

=head1 KNOWN BUGS

- need to queue events until SLCP sync is complete
- UI escaping is breaking SLCP parser.
- Discussion destruction handler

=back

=cut

my %keep;
%{$keep{USER}} = (HANDLE => 1,
		  NAME => 'rename',
		  BLURB => 'blurb',
		  STATE => 1);
%{$keep{DISC}} = (HANDLE => 1, 
		  NAME => 1,
		  TITLE => 'retitle');

my @login_prompts   = ('.*\(Y\/n\)\s*$',  # ' (Emacs parser hack)
		       '^--> ',
		       '^login: ',
		       '^password: ');

my @connect_prompts = ('^\&password: ',
		       '^--> ',
		       '^\* ');

my $SLCP_WARNING =
  "This server does not appear to support SLCP properly.  Tigerlily \
now requires SLCP support to function properly.  Either upgrade your Lily \
server to the latest version or use another (1.x) version of tlily.\n";


sub set_client_options {
	my($serv) = @_;
	$serv->sendln('#$# options +leaf-notify +leaf-cmd +connected');
	$serv->{OPTIONS_SET} = 1;
	return;
}


# Take raw server output, and deal with it.
sub parse_raw {
	my($event, $handler) = @_;

	my $serv = $event->{server};

	# Divide into lines.
	$serv->{pending} .= $event->{data};
	my @lines = split /\r?\n/, $serv->{pending}, -1;
	$serv->{pending}  = pop @lines;

	# Try to handle prompts; a prompt is a non-newline terminated line.
	# The difficulty is that we need to distinguish between prompts (which
	# are lines lacking newlines) and partial lines (which are lines which
	# we haven't completely read yet).
	my $prompt;
	for $prompt ($serv->{logged_in} ? @connect_prompts : @login_prompts) {
		if ($serv->{pending} =~ /($prompt)/) {
			push @lines, $1;
			substr($serv->{pending}, 0, length($1)) = "";
		}
	}

	# For general efficiency reasons, I'm not sending these as
	# events.  Should I, perhaps?  This could easily be false
	# efficiency.  Parsing everything like this is definately
	# going to kill interactive latancy, however: I recommend
	# implementing idle events, and parsing these when idle.
	foreach (@lines) {
		parse_line($serv, $_);
	}

	return;
}


# The big one: take a line from the server, and decide what it is.
sub parse_line {
	my($serv, $line) = @_;
	chomp $line;

	my $ui;
	$ui = LC::UI::name($serv->{ui_name}) if ($serv->{ui_name});

	my $cmdid = undef;
	my $review = undef;

	my $hidden;

	my %event = ();

	# prompts #############################################################

	my $p;
	foreach $p ($serv->{logged_in} ? @connect_prompts : @login_prompts) {
		if ($line =~ /$p/) {
			set_client_options($serv) if (!$serv->{OPTIONS_SET});
			$ui->prompt($line) if ($ui);
			%event = (type => 'prompt',
				  text => $line);
			goto found;
		}
	}


	# prefixes ############################################################

	# %command, all cores.
	if ($line =~ s/^%command \[(\d+)\] //) {
		$cmdid = $1;
	}

	# %g
	if ($line =~ s/^%g//) {
		$serv->{SIGNAL} = 1;
	}


	# SLCP ################################################################

	# SLCP "%USER" and "%DISC" messages, used to sync up the
	# initial client state database.
	if ($line =~ /^%USER /) {

		$ui->print("(please wait, synching with SLCP)\n")
		  if ($ui && !$serv->{SLCP_SYNC});
		$serv->{SLCP_SYNC} = 1;

		my %args = SLCP_parse($line);
		foreach (keys %args) {
			delete $args{$_} unless $keep{USER}{$_};
		}

		$serv->state(%args);

		return;
	}

	if ($line =~ /^%DISC /) {
		my %args = SLCP_parse($line);
		foreach (keys %args) {
			delete $args{$_} unless $keep{DISC}{$_};
		}

		$serv->state(%args);

		return;
	}

	# SLCP "%DATA" messages. 
	if ($line =~ /^%DATA /) {
		my %args = SLCP_parse($line);

		$serv->state(DATA => 1, %args);

		# Debugging. :>
		return if ($serv->{logged_in});
		%event = (type => 'text',
			  text => $line);
		goto found;
	}

	# SLCP %NOTIFY messages.  We pretty much just push these through to 
	# tlily's internal event system.
	if ($line =~ /^%NOTIFY /) {
		my %args = SLCP_parse($line);

		$serv->{SIGNAL} = 1 if ($args{BELL});
		$hidden = 1 if (!$args{NOTIFY});

		# SLCP bug?!
		if ($args{EVENT} =~ /emote|public|private/) {
			$hidden = 0;
		}

		$args{HANDLE} = $args{SOURCE};
		$args{SOURCE} =~ s(([^,]+))($serv->get_name(HANDLE => $1))ge;
		$args{SOURCE} =~ s/,/, /g;

		if ($args{RECIPS}) {
			$args{RECIPS} =~
			  s(([^,]+))($serv->get_name(HANDLE => $1))ge;
			$args{RECIPS} =~ s/,/, /g if ($args{RECIPS});
		}

		$args{VALUE} = undef if $args{EMPTY};

		delete $args{EMPTY};
		delete $args{BELL};
		delete $args{NOTIFY};
		delete $args{TIME};

#		delete $args{TIME};
#		delete $args{STAMP};
		delete $args{COMMAND};

		$event{type} = $args{EVENT};
		@event{keys %args} = @args{keys %args};

		if ($event{SOURCE} eq $serv->user_name) { 
			$event{isuser} = 1;
		}

		goto found;
	}


	# other %server messages ##############################################

	# %begin (command leafing)
	if ($line =~ /^%begin \[(\d+)\] (.*)/) {
		$cmdid = $1;
		$hidden = 1;
		%event = (type    => 'begincmd',
			  command => $2);
		goto found;
	}

	# %end, all cores.
	if ($line =~ /^%end \[(\d+)\]/) {
		$cmdid = $1;
		$hidden = 1;
		%event = (type => 'endcmd');
		goto found;
	}

	# %connected
	if ($line =~ /^%connected/) {
		$serv->{logged_in} = 1;
		$hidden = 1;
		%event = (type => 'connected',
			  text => $line);
		goto found;
	}

	# %export_file
	if ($line =~ /^%export_file (\w+)/) {
		$hidden = 1;
		%event = (type => 'export',
			  response => $1);
		goto found;
	}

	# The options notification.  (OK, not a %command...but it fits here.)
	if ($line =~ /^\[Your options are/ ||
	    $line =~ /^%options/) {
		$hidden = 1;
		%event = (Type => 'options');

		goto found if $serv->{SLCP_OK};

		if (! ($line =~ /\+leaf-notify/ &&
		       $line =~ /\+leaf-cmd/ &&
		       $line =~ /\+connected/) ) {
			warn $SLCP_WARNING;
		} else {
			$serv->{SLCP_OK} = 1;
		}
		goto found;
	}

	# check for old cores
	if  ($line =~ /type \/HELP for an introduction/) {
		warn $SLCP_WARNING unless $serv->{SLCP_OK};
	}

	if ($line =~ /^%/) {
		%event = (type => 'servercmd');
		goto found;
	}


	# /review #############################################################

	if (($line =~ /^\#\s*$/) ||
	    ($line =~ /^\# [\>\-\*\(]/) ||
	    ($line =~ /^\# \\\</) ||
	    ($line =~ /^\# \#\#\#/)) {

		if ((substr($line, 2, 1) eq '*') ||
		    ((substr($line, 2, 1) eq '>') &&
		     (substr($line, 2, 2) ne '>>'))) {
			$line = substr($line, 2);
			$review = '# ';
		} else {
			$line = substr($line, 1);
			$review = '#';
		}
	}

	# login stuff #########################################################

	# Welcome...
	if ($line =~ /^Welcome to lily.*?at (.*?)\s*$/) {
		# Set servername to $1.
	}

	# something completely unknown ########################################

	%event = (type => 'text',
		  text => $line);

	# An event has been parsed.
      found:
	if ($review) {
		$line = '<review>' . $review . '</review>' . $line;
		$event{RevType} = $event{Type};
		$event{Type} = 'review';
		$event{WrapChar} = '# ' . ($event{WrapChar} || '');
	}

	#$event{ToUser} = 1 unless ($hidden);
	$event{signal} = 'default' if ($serv->{SIGNAL});
	$event{id}     = $cmdid;
	$event{text}   = $line;
	$event{server} = $serv;

	$serv->{SIGNAL} = undef;

	$event{type} ||= "foo";
	$event->send(\%event);
	return;
}


sub load {
	$event->event_r(type => 'slcp_data',
			call => \&parse_raw);

}


sub SLCP_parse {
    my ($line) = @_;
    my %ret;

    $line =~ /^%\S+/gc;
    while (1) {
	    # OPT=len=VAL
	    if ($line =~ /\G\s*([^\s=]+)=(\d+)=/gc) {
		    $ret{$1} = substr($line, pos($line), $2);
		    last if (pos($line) + $2 >= length($line));
		    pos($line) += $2;
	    }

	    # OPT=VAL
	    elsif ($line =~ /\G\s*([^\s=]+)=(\S+)/gc) {
		    $ret{$1} = $2;
	    }

	    # OPT
	    elsif ($line =~ /\G\s*(\S+)/gc) {
		    $ret{$1} = 1;
	    }

	    else {
		    last;
	    }
    }

    return %ret;
}


1;
