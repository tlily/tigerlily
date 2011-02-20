# -*- Perl -*-
# $Id$

use strict;
use vars qw(%config);

use TLily::Config qw(%config);

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

=cut

my %keep;
$keep{USER} = {HANDLE   => 1,
               LOGIN    => 1,
               NAME     => 1,
               BLURB    => 1,
               PRONOUN  => 1,
               STATE    => 1};
$keep{DISC} = {HANDLE   => 1,
               CREATION => 1,
               NAME     => 1,
               TITLE    => 1,
               ATTRIB   => 1};

my %events =
  (
   'connect'     => undef,
   disconnect    => undef,
   drename       => undef,
   attach        => undef,
   detach        => undef,
   here          => undef,
   away          => undef,
   'rename'      => undef,
   blurb         => undef,
   info          => undef,
   ignore        => undef,
   unignore      => undef,
   unidle        => undef,
   public        => undef,
   private       => undef,
   create        => undef,
   destroy       => undef,
   permit        => undef,
   depermit      => undef,
   appoint       => undef,
   unappoint     => undef,
   'join'        => undef,
   quit          => undef,
   retitle       => undef,
   review        => undef,
   sysmsg        => undef,
   sysalert      => undef,
   emote         => undef,
   pa            => undef,
   game          => undef,
   consult       => undef,
  );

my $SLCP_WARNING =
  "This server does not appear to support SLCP properly.  Tigerlily \
now requires SLCP support to function properly.  Either upgrade your Lily \
server to the latest version or use another (1.x) version of tlily.\n";

# Take raw server output, and deal with it.
sub parse_raw {
    my($event, $handler) = @_;

    my $serv = $event->{server};

    # Divide into lines.
    $serv->{pending} .= $event->{data};
    my @lines = split /\r?\n/, $serv->{pending}, -1;
    $serv->{pending}  = pop @lines;

    # Catch the login and password prompts.  (The only things tlily will
    # ever receive that are not \n-terminated.  Thank you, Christian!)
    if (!$serv->{logged_in} &&
        $serv->{pending} =~ s/^((?:login|password): )//) {
        push @lines, $1;
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
    $ui = ui_name($serv->{'ui_name'}) if ($serv->{'ui_name'});

    #print STDERR "=", $line, "\n";
    $ui->print("=", $serv->name(), "=", $line, "\n") if ($TLily::Config::config{parser_debug});

    my %event;
    my $cmdid = "";
    # prompts #############################################################

    if (!$serv->{logged_in}) {
        if ($line =~ /^login: /) {
            %event = (type => 'prompt',
                      text => $line);
            goto found;
        } elsif ($line =~ /^password: /) {
            %event = (type     => 'prompt',
                      password => 1,
                      text     => $line);
            goto found;
        }
    }


    # prefixes ############################################################

    # %g
    if ($line =~ s/^%g//) {
        $serv->{BELL} = 1;
    }

    # %command, (command leafing)
    if ($line =~ /^%command \[(\d+)\] (.*)/) {
        $cmdid = $1;
        $line = $2;
    }

    # SLCP ################################################################

    # SLCP "%USER" and "%DISC" messages, used to sync up the
    # initial client state database.
    if ($line =~ /^%USER /) {

        $ui->print("(please wait, syncing with SLCP)\n")
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

    # SLCP "%GROUP" messages.
    if ($line =~ /^%GROUP /) {
        my %args = SLCP_parse($line);
        $serv->state(%args);

        return;
    }

    # SLCP "%DATA" messages.
    if ($line =~ /^%DATA /) {
        my %args = SLCP_parse($line);

        # Sanity check: do we know all these events?
        if ($args{NAME} eq "events") {
            my $e;
            foreach $e (split /,/, $args{VALUE}) {
                if (!exists($events{lc($e)})) {
                    warn "Unknown event type: \"$e\".\n";
                }
            }
        }

        $serv->state(DATA => 1, %args);

        return;

        # Debugging. :>
        return if ($serv->{logged_in});
        %event = (type   => 'text',
                  NOTIFY => 1,
                  text   => $line);
        goto found;
    }

    # SLCP-SYNC messages
    if ($line =~ /^%SLCP-SYNC (.*)/) {
        my $be = lc($1);
        %event = (type   => "slcp-sync",
                  NOTIFY => 1,
                  text   => "(SLCP sync ${be}ing)");
        goto found;
    }

    # SLCP %NOTIFY messages.  We pretty much just push these through to
    # tlily's internal event system.
    if ($line =~ /^%NOTIFY /) {

        %event = SLCP_parse($line);

        # treat event name case-insensitively
        $event{EVENT} = lc($event{EVENT});

        # SLCP bug?!
        # Fixed, I think.  -DN
        if ($event{EVENT} =~ /emote|public|private/) {
            $event{NOTIFY} = 1;
        }

        $event{SHANDLE} = $event{SOURCE};
        $event{SOURCE}  = $serv->get_name(HANDLE => $event{SOURCE});

        if ($event{EVENT} =~ /unidle/ &&
            $event{SOURCE} eq $serv->user_name) {
            $event{NOTIFY} = 0;
        }

        if ($event{RECIPS}) {
            $event{RHANDLE} = [ split /,/, $event{RECIPS} ];
            $event{RECIPS}  =
              join(", ",
                   map { $serv->get_name(HANDLE => $_) }
                   @{$event{RHANDLE}});
        }

        if ($event{TARGETS}) {
            $event{THANDLE} = [ split /,/, $event{TARGETS} ];
            $event{TARGETS}  =
              join(", ",
                   map { $serv->get_name(HANDLE => $_) }
                   @{$event{THANDLE}});
        }

        # Um.  Undef?  Don't set it at all?
        $event{VALUE} = undef if $event{EMPTY};

        if (exists($events{$event{EVENT}})) {
            $event{type} = $event{EVENT};
        } else {
            $event{type}  = "slcp_unknown";
        }

        # This will only be used if no formatter rewrites the text.
        $event{text}  = "(notify: $event{SOURCE}";
        $event{text} .= " -> $event{RECIPS}"       if ($event{RECIPS});
        $event{text} .= ": $event{EVENT}";
        $event{text} .= " = \"$event{VALUE}\""     if ($event{VALUE});
        $event{text} .= ")";

        if ($event{SOURCE} eq $serv->user_name) {
            $event{isuser} = 1;
        }

        goto found;
    }


    # other %server messages ##############################################

    # %server
    if ($line =~ /^%server /) {
        %event = SLCP_parse($line);

        foreach my $name (keys %event) {
            $serv->state(DATA => 1, NAME => $name, VALUE => $event{$name});
        }
        return;
    }

    # %prompt
    if ($line =~ /^%prompt2? (.*)/) {
        %event = (type => 'prompt',
                  text => $1);
        $event{password} = 1 if (/password/);
        goto found;
    }

    # %begin (command leafing)
    if ($line =~ /^%begin \[(\d+)\] (.*)/) {
        %event = (type    => 'begincmd',
                  cmdid   => $1,
                  command => $2);
        goto found;
    }

    # %end (command leafing)
    if ($line =~ /^%end \[(\d+)\]/) {
        %event = (type => 'endcmd',
                  cmdid => $1);
        goto found;
    }

    # %connected
    if ($line =~ /^%connected/) {
        $serv->{logged_in} = 1;
        %event = (type => 'connected',
                          text => $line);
        goto found;
    }

    # %export_file
    if ($line =~ /^%export_file (\w+)/) {
        %event = (type => 'export',
                  response => $1,
                  NOTIFY => 1,
                  text => $line);
        goto found;
    }

    # %import_file
    if ($line =~ /^%import_file/) {
        %event = (type => 'import',
                  response => $1,
                  NOTIFY => 1,
                  text => $line);
        goto found;
    }

    # %pong
    if ($line =~ /^%pong/) {
        %event = (type => 'pong');
        goto found;
    }

    # The options notification.
    if ($line =~ /%options\s+(.*?)\s*$/) {

        my @o = split /\s+/, $1;
        %event = (type    => 'options',
                  options => \@o,
                  text => $line);

        if (! $serv->{SEEN_OPTIONS}) {
            $serv->{SEEN_OPTIONS}=1;
            # flush out any pending send data at this point.  We queue the
            # initial sends from the user for a bit so that the options
            # negotiation can happen properly.
            foreach (@{$serv->{send_buffer}}) {
                $serv->sendln($_);
            }
            undef $serv->{send_buffer};

            goto found if $serv->{SLCP_OK};

            if (! ($line =~ /\+leaf-notify/ &&
                   $line =~ /\+leaf-cmd/ &&
                   $line =~ /\+connected/) ) {
                warn $SLCP_WARNING . "[Error Code -1]\n";
            } else {
                $serv->{SLCP_OK} = 1;
            }
        }

        goto found;
    }

    # check for old cores
    if  ($line =~ /type \/HELP for an introduction/) {
        warn $SLCP_WARNING . "[Error Code -2]\n" unless $serv->{SLCP_OK};
    }

    # login stuff #########################################################

    # Welcome...
    if ($line =~ /^Welcome to (lily|Rowboat).*?at (.*?)\s*$/) {
        $serv->state(DATA => 1, NAME => "NAME", VALUE => $2);
        # Set servername to $2.
        $serv->name($2);
    }

    # something completely unknown ########################################

    %event = (type   => 'text',
              NOTIFY => 1,
              text   => $line);

    # An event has been parsed.
  found:
    $event{cmdid}     = $cmdid if ($cmdid);
    $event{BELL}      = 1 if ($serv->{BELL});
    $event{server}    = $serv;
    $event{'ui_name'} = $serv->{'ui_name'};

    $serv->{BELL} = undef;

    TLily::Event::send(\%event);
    return;
}

sub load {
    event_r(type => 'slcp_data',
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

        # OPT=VAL
        } elsif ($line =~ /\G\s*([^\s=]+)=(\S+)/gc) {
            $ret{$1} = $2;

        # OPT
        } elsif ($line =~ /\G\s*(\S+)/gc) {
            $ret{$1} = 1;

        } else {
            last;
        }
    }

    return %ret;
}

shelp_r('parser_debug' => '(boolean) Debug the SLCP parser', 'variables');

help_r('parser_debug' => '
Setting this to true causes the SLCP parser to output the raw protocol
from the lily server.  Setting to 0 turns this off.
');


1;
