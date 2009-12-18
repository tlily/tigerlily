# -*- Perl -*-
# $Id$

use strict;
use Text::ParseWords qw(quotewords);
use TLily::Bot;

#
# This is a rewrite of the old %on.pl for clarity and features.  Unfortunately,
# one feature was lost in the rewrite: \n doesn't work in actions any more.
# (Assuming it ever did; the old on.pl had a note that it might not work.)
#

my $usage = "(/on list | clear <id> | <event> <action>)";

command_r(on => \&on_cmd);
shelp_r(attr=> "see %on");
help_r(attr=> "see %on");
shelp_r(on => "execute a command when a specific event occurs");
help_r('on', qq[
   %on list
   %on clear <id>
   %on [<event> [options...] <what to do>]

<event> is any standard tlily event.  A few useful events are:
  public        - Public sends.
  private       - Private sends.
  emote         - Public sends to emote discussions.
  server_change - The active server has changed.

There are a number of options to limit the events acted upon.
  from <source>  - Events from a given user or group.
  to <target>    - Events sent to a given user or discussion.
  value <string> - The VALUE field of the event is identical to <string>.
  like <regexp>  - The VALUE field of the event matches the given pattern.
  server <name>  - Events sent to a specific server.
  notify <value> - The NOTIFY value of the event is on ('yes'), off ('no'),
                   or ignored ('always').  (Default is 'yes')
  random <N>     - Randomly take action approximately every 1-in-N matches.

%on supports the following special characters in "what to do":

\$1 .. \$9  variable matches in the regexp, if "like" is used.
\$sender   for "public", "private", or "emote" events, the sender of the
          message.
\$value    the value of the original event

Alternatively, you may use "%attr <attribute> <value>" in "what to do"
to set attributes on the event being matched.  Of particular interest
are the "header_fmt", "sender_fmt", "dest_fmt", "body_fmt", and
"slcp_fmt" attributes, which control how sends are displayed.  (Note
that these attributes take styles as arguments -- see %help style for
more information.)

You may also use "%eval <code>" to run arbitrary code in reaction to some
event.  The result of the code will be sent to the initiator of that event,
if defined.

Examples:

  %on unidle from appleseed "appleseed;[autonag] Gimme my scsi card!"
  %on emote to beener like "fluffs almo" "beener;auto-spurts feathers"
  %on emote to beener like "ping (.*)" "$1;ping!"
  %on emote to beener like "ice cream" random 10 "$1;screams for ice cream!"
  %on public to news %attr dest_fmt significant
  %on attach from SignificantOther %attr slcp_fmt significant
  %on attach from JoshTest "%eval `banner wazzup?`"  
]);

shelp_r('on_quiet' => 'Don\'t display %on notifications', 'variables');


my @on_handlers;


#
# %on command handler
# %on list
# %on clear <id>
#
sub on_cmd {
    my($ui, $args, $startup) = @_;

    eval {
	my @args = quotewords('\s+', 0, $args);
	die "usage" if (@args == 0 && $args =~ /\S/);

	#
	# %on list
	#
	if (@args == 0 || $args[0] =~ /^list$/s) {
	    die "usage" if (@args > 1);

	    if (!@on_handlers) {
		$ui->print("(no %on handlers are currently registered)\n");
		return;
	    }

	    $ui->printf("%5.5s %-70.70s\n", "Id", "Description");
	    $ui->printf("%5.5s %-70.70s\n", "-" x 5, "-" x 70);
	    foreach (@on_handlers) {
		my $mask = $_->[1];
		my $desc = "TYPE $mask->{EVENT}";

		$desc .= " SERVER " . $mask->{SERVER}->name
		  if defined($mask->{SERVER});

		if (defined $mask->{SHANDLE}) {
		    my %state =
		      $mask->{SERVER}->state(HANDLE => $mask->{SHANDLE});
		    $desc .= " FROM $state{NAME}";
		}

		$desc .= " FROM GROUP $mask->{SGROUP}" if
		  defined($mask->{SGROUP});

		if (defined $mask->{RHANDLE}) {
		    my %state =
		      $mask->{SERVER}->state(HANDLE => $mask->{RHANDLE});
		    $desc .= " TO $state{NAME}";
		}

		$desc .= " TO GROUP $mask->{RGROUP}" if
		  defined($mask->{RGROUP});

		$desc .= " LIKE \"$mask->{LIKE}\""
		  if defined($mask->{LIKE});

		$desc .= " RANDOM $mask->{RANDOM}"
		  if defined($mask->{RANDOM});

		$desc .= " VALUE \"$mask->{VALUE}\""
		  if defined($mask->{VALUE});

		$ui->printf("%5.5s %-70.70s\n", $_->[0], $desc);
		$ui->print("      " . join(" ", @{$mask->{ACTION}}) . "\n");
	    }
	    return;
	}


	#
	# %on clear <id>
	#
	if ($args[0] =~ /^clear$/) {
	    die "usage" if (@args != 2);

	    if (grep { $_->[0] == $args[1] } @on_handlers) {
		event_u($args[1]);
		$ui->print("(%on handler id $args[1] removed)\n");
		@on_handlers = grep { $_->[0] != $args[1] } @on_handlers;
	    } else {
		$ui->print("(%on handler id $1 not found)\n");
	    }

	    return;
	}


	#
	# %on <type> [<mask> <value>] ... <action>
	#
	die "usage" if (@args < 2);

	my %mask;
	my $event_type = shift @args;

	while (@args && $args[0] =~ /^(notify|from|to|value|like|server|random)$/i) {
	    my $masktype = uc(shift @args);
	    my $maskval  = shift @args;
	    $mask{$masktype} = $maskval;
	}

	# The following design requires that a connection exist to a given
	# server in order to set actions relating to it.  This makes it
	# impossible to set up actions prior to contacting the server.
	my $server;
	if (defined $mask{SERVER}) {
	    $server = TLily::Server::find($mask{SERVER});
	    if (!$server) {
		$ui->print("(server \"$mask{SERVER}\" not found)\n");
		return;
	    }
	} else {
	    $server = TLily::Server::active();
	    if (!$server && ($mask{FROM} || $mask{TO})) {
		$ui->print("(no server is active)\n");
		return;
	    }
	}
	$mask{SERVER} = $server;

	for my $mask (qw(FROM TO)) {
	    next unless defined($mask{$mask});

	    my $char = ($mask eq "FROM") ? "S" : "R";

	    # This is a hideous hack.  Perhaps expand_name() should be
	    # changed to take an option indicating that groups are not
	    # to be expanded?
	    local $config{expand_group} = 0;

	    # Look up the name in question.
	    my $name = $server->expand_name($mask{$mask});
	    if (!defined $name) {
		$ui->print("($mask{$mask} not found)\n");
		return;
	    }
	    $name =~ s/^-//;

	    # Fetch the state associated with this name.
	    my %state = $server->state(NAME => $mask{$mask});

	    # Matched a group?
	    if ($state{MEMBERS}) {
		$mask{"${char}GROUP"} = $state{NAME};
	    }
	    # Matched a destination?
	    elsif ($state{HANDLE}) {
		$mask{"${char}HANDLE"} = $state{HANDLE};
	    } else {
		$ui->print("($mask{$mask} not found)\n");
		return;
	    }

	    $mask{$mask} = $state{NAME};
	}

	$mask{EVENT} = $event_type;
	$mask{ACTION} = \@args;

	$mask{NOTIFY} = "always" if (!$mask{NOTIFY});

	# Print an accounting of what we're doing, unless this is being
	# run out of a startup file.
	if (!$startup) {
	    my $str;

	    $str  = "(on $event_type events";
	    $str .= " from $mask{FROM}"       if defined($mask{SHANDLE});
	    $str .= " from group $mask{FROM}" if defined($mask{SGROUP});
	    $str .= " to $mask{TO}"           if defined($mask{RHANDLE});
	    $str .= " to group $mask{TO}"     if defined($mask{RGROUP});

	    if ($mask{NOTIFY} eq 'always') {
	      $str .= " always";
	    } else {
	      $str .= " when";
	      $str .= " not" if $mask{NOTIFY} eq 'no';
	      $str .= " notified";
	    }

	    $str .= " with a value like \"$mask{LIKE}\""
	      if defined($mask{LIKE});
	    $str .= " with a value of \"$mask{VALUE}\""
	      if defined($mask{VALUE});
	    $str .= ", I will " . ($mask{RANDOM}?"randomly ":"") .
	      "run \"@args\")\n";

	    $ui->print($str);
	}

	delete $mask{FROM};
	delete $mask{TO};

	# The %on handler runs in the 'after' phase, except for %attr actions.
	my $order = ($args[0] =~ /^%attr$/i) ? "before" : "after";

	my $handler = event_r(type  => $event_type,
			      order => $order,
			      call  => sub { on_evt_handler(@_, \%mask); });
	push @on_handlers, [ $handler, \%mask ];
    };

    # Catch usage errors here.  Any other error is propagated.
    if ($@) {
	die if ($@ !~ /^usage/);
	$ui->print("$usage\n");
    }

    return;
}


# Event handler to dispatch %on commands.
sub on_evt_handler {
    my($e, $h, $mask) = @_;
    my $ui = $e->{ui} || ui_name();
    my %vars;

    # Server matches?
    return if (!$e->{server} || $e->{server} != $mask->{SERVER});

    # Regexp value match?
    if (defined $mask->{LIKE}) {
	return if ($e->{VALUE} !~ /$mask->{LIKE}/i);

	my $i = 1;
	for my $m ($1,$2,$3,$4,$5,$6,$7,$8,$9) {
	    $vars{$i++} = $m;
	}
    }

    # Notify value match?
    if (defined $mask->{NOTIFY}) {
	return if ($mask->{NOTIFY} eq 'yes' and !defined($e->{NOTIFY}));
	return if ($mask->{NOTIFY} eq 'no' and defined($e->{NOTIFY}));
    } else {
	return if (!defined($e->{NOTIFY}));
    }

    # Literal value match?
    if (defined $mask->{VALUE}) {
	return if ($e->{VALUE} ne $mask->{VALUE});
    }

    # Sender match?
    if (defined $mask->{SHANDLE}) {
	return unless ($e->{SHANDLE} eq $mask->{SHANDLE});
    }

    # Sender group match?
    if (defined $mask->{SGROUP}) {
	my %state = $e->{server}->state(NAME => $mask->{SGROUP});
	return unless ($state{MEMBERS});

	my %from;
	@from{split /,/, $state{MEMBERS}} = undef;
	return unless exists($from{$e->{SHANDLE}});
    }

    # Destination match?
    if (defined $mask->{RHANDLE}) {
	return unless grep($_ eq $mask->{RHANDLE}, @{$e->{RHANDLE}});
    }

    # Destination group match?
    if (defined $mask->{RGROUP}) {
	my %state = $e->{server}->state(NAME => $mask->{RGROUP});
	return unless ($state{MEMBERS});

	my %to;
	@to{split /,/, $state{MEMBERS}} = undef;
	return unless grep(exists($to{$_}), @{$e->{RHANDLE}});
    }

    # Apply randomization if present
    if (defined $mask->{RANDOM}) {
      return unless (rand() < 1 / int($mask->{RANDOM}));
    }

    # Match successful.
    $vars{sender} = $e->{server}->expand_name($e->{SOURCE});
    $vars{sender} =~ s/^-//;
    $vars{sender} =~ s/ /_/g;
    $vars{value} = $e->{VALUE};

    my @cmd = @{$mask->{ACTION}};
    @cmd = map { ($_ =~ s/^\$//g) ? $vars{$_} : $_ } @cmd;

    return unless @cmd;

    if ($cmd[0] =~ /^%attr$/i) {
	shift @cmd;
	my $attr = shift @cmd;
	$e->{$attr} = join(" ", @cmd);
	return;
    }

    # Ignore events from myself, unless I specifically define them.
    return if (!$mask->{SHANDLE} &&
	       !$mask->{SGROUP} &&
	       ($e->{SHANDLE} eq $e->{server}->user_handle));

    if ($cmd[0] =~ /^%eval$/i) {
	shift @cmd;
	my $res = eval "@cmd";
	$res .= "ERROR: $@" if $@;
	$res = "$vars{sender};" . TLily::Bot::wrap_lines($res);
	@cmd = ($res);
    }

    $ui->prints(on => "[%on] @cmd\n") unless $config{on_quiet};

    TLily::Event::send({type => 'user_input',
			ui   => $ui,
			text => "@cmd\n"});

    return 0;
}


sub on_disconnect {
    my($e, $h) = @_;

    my $ui = ui_name();
    my @on_temp = @on_handlers;
    for my $on (@on_temp) {
	if ($on->[1]->{SERVER} == $e->{server}) {
	    on_cmd($ui, "clear $on->[0]");
	}
    }
}
TLily::Event::event_r(type => 'server_disconnected',
		      call => \&on_disconnect);

sub unload {
    my $ui = ui_name();
    while (@on_handlers) {
	on_cmd($ui, "clear $on_handlers[0]->[0]");
    }
}


1;
