# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Id$

package TLily::Server::IRC;

use strict;
use vars qw(@ISA %config);

use Carp;

use TLily::Version;
use TLily::Server;
use TLily::Extend;
use TLily::Event qw(event_r);
use TLily::Config qw(%config);
use TLily::UI;
use TLily::Server::IRC::Driver;

@ISA = qw(TLily::Server::SLCP);

=head1 NAME

TLily::Server::IRC - TLily interface to IRC

=head1 SYNOPSIS

use TLily::Server::IRC;

=head1 DESCRIPTION

This class interfaces tlily to an IRC server.  It also provides a set of 
/commands for use with IRC messenging.

Note:  For compatibility, this is subclassed from SLCP, and all the state
database-related code is left unmolested.   Ideally though, this code
should be refactored into the base class and SLCP and IRC should sit 
side by side, since IRC is not REALLY a subclass of SLCP.

=head1 FUNCTIONS

=over

=cut

# need an API to get at the one in TLily::Server.. generally need to refactor
# the connect stuff out of that function, so we can use tlily::Server.
my %server;

sub new {
    my ( $proto, %args ) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};
    bless $self, $class;

    # Generate a unique name for this server object.
    my $name = $args{'host'};
    if ( $server{$name} ) {
        my $i = 2;
        while ( $server{ $name . "#$i" } ) { $i++; }
        $name .= "#$i";
    }

    $args{port}     ||= 6667;

    $self->{name} = $name if ( defined( $args{name} ) );
    $self->{host} = $args{host};
    $self->{ssl}  = $args{ssl};
    $self->{port} = $args{port} || 6667;
    @{ $self->{names} } = ($name);
    $self->{ui_name}           = $args{ui_name} || "main";
    $self->{proto}             = "irc";
    $self->{bytes_in}          = 0;
    $self->{bytes_out}         = 0;
    $self->{last_message_from} = undef;
    $self->{last_message_to}   = undef;

    # State database
    $self->{HANDLE} = {};
    $self->{NAME}   = {};
    $self->{DATA}   = {};

    $self->{user}     = $args{user};
    $self->{password} = $args{password};

    my $ui = TLily::UI::name( $self->{ui_name} );

    $ui->print("Logging into IRC...\n");

    # remember ourselves..
    $self->state(
        HANDLE      => lc( $self->{user} ),
        NAME        => $self->{user},
        ONLINE      => 1,
        EVIL        => 0,
        ON_SINCE    => time,
        IDLE        => 0,
        LAST_UPDATE => time,
        STATE       => 'here',
    );
    $self->state(DATA  => 1,
                 NAME  => "whoami",
                 VALUE => $self->{user});

    eval {
        $self->{'netirc'} = TLily::Server::IRC::Driver->new();
        die "Error creating Net::IRC object! (Are you sure Net::IRC is installed?)\n"
          unless defined $self->{'netirc'} ;
        $self->{'irc'}    = $self->{'netirc'}->newconn(
            Server => $self->{'host'},
            Port   => $self->{'port'},
            Nick   => $self->{'user'},
            SSL    => $args{'ssl'},
        );
        # XXX carp here about being unable to connect...
    };
    if ($@) {
        $ui->print("failed: $@");
        return;
    }

# If uncommented, will dump all received Net::IRC events that do
# not have handlers registered.  Useful for development.
#    $self->{'irc'}->add_default_handler(
#        sub {
#            my ( $conn, $event ) = @_;
#            $ui->print("IRCEVENT: " . Dumper($event));
#        }
#    );

    # on_connect
    $self->{'irc'}->add_global_handler(
        '376',
        sub {
            $ui->print("connected to $self->{host} as $self->{user}.\n\n");
        }
    );

    # on disconnect - this is required; if there is no handler for
    # a disconnect event, Net::IRC's default action is to call die().
    $self->{'irc'}->add_global_handler(
        'disconnect',
        sub {
            $ui->print(
                "*** Closed connection to $self->{host} as $self->{user} ***\n"
            );
        }
    );

    $self->{irc}->add_handler(
        'msg',
        sub {
            my ( $conn, $event ) = @_;
            TLily::Event::send(
                {
                    server  => $self,
                    ui_name => $self->{'ui_name'},
                    type    => "private",
                    VALUE   => join( " ", @{ $event->{args} } ),
                    SOURCE  => $event->{nick},
                    SHANDLE => $event->{nick},
                    RECIPS  => $event->{to}->[0],
                    TIME    => time,
                    NOTIFY  => 1,
                    BELL    => 1,
                    STAMP   => 1
                }
            );
            $self->{last_message_from} = @{ $event->{to} }[0]; #XXX Doesn't work
        }
    );

    $self->{irc}->add_handler(
        'public',
        sub {
            my ( $conn, $event ) = @_;
            TLily::Event::send(
                {
                    server  => $self,
                    ui_name => $self->{'ui_name'},
                    type    => "public",
                    VALUE   => join( " ", @{ $event->{args} } ),
                    SOURCE  => $event->{nick},
                    SHANDLE => $event->{nick},
                    RECIPS  => $event->{to}->[0],
                    TIME    => time,
                    NOTIFY  => 1,
                    BELL    => 0,
                    STAMP   => 1
                }
            );
            $self->{last_message_from} = @{ $event->{to} }[0]; #XXX Doesn't work
        }
    );

    # Nick Taken
    $self->{irc}->add_global_handler(
        433,
        sub {
            my ($conn) = @_;
            $ui->print("*** That nick is already taken ***\n");

            # Keep adding _'s to our name! XXX need saner approach, neh?
            $self->{user} .= "_";
            $conn->nick( $self->{user} );
            $self->state(DATA  => 1,
                         NAME  => "whoami",
                         VALUE => $self->{user});
            $ui->print("(you are now named $self->{user})\n");

            # XXX Generate a lily rename event.
        }
    );

    $self->{irc}->add_handler(
        'join',
        sub {
            my ( $conn, $event ) = @_;
            my ($channel) = ( $event->to )[0];
            $channel =~ s/^-?#?//;

            if ( $event->{nick} eq $self->{user} ) {
                $ui->print("(you have joined $channel)\n");
            }
            else {
                $ui->print(
                    "*** $event->{nick} is now a member of $channel ***\n");
                my $user = $event->{nick};
                $user =~ s/^(@|^)//;
                if (defined $self->{NAME}->{$user}) {
                    $self->{NAME}->{$user}->{COUNT}++;
                }
                else {
                    $self->state(NAME => $user, LOGIN => 1, COUNT => 1);
                }
                $self->{NAME}->{$channel}->{MEMBERS} .= "," . $user;
            }

            # XXX Generate tlily join'd event.
        }
    );

    $self->{irc}->add_handler(
        'nick',
        sub {
            my ( $conn, $event ) = @_;
            my $from = $event->{nick};
            my $to   = $event->{args}->[0];
            $ui->print("*** $from is now named $to ***\n");

            # XXX Generate tlily rename'd event

            $self->{NAME}->{$to} = $self->{NAME}->{$from};
            $self->{NAME}->{$to}->{NAME} = $to;
            delete $self->{NAME}->{$from};
        }
    );

    $self->{irc}->add_handler(
        'quit',
        sub {
            my ( $conn, $event ) = @_;
            my ($channel) = ( $event->to )[0];
            $channel =~ s/^-?#?//;

            if ( $event->{nick} eq $self->{user} ) {
                $ui->print("(thank you for using IRC)\n");
            }
            else {
                $ui->print(
                    "*** $event->{nick} has left IRC ***\n"
                );
                $self->state(NAME => $event->{nick}, __DELETE => 1);
            }

            # XXX Generate tlily quit event.
        }
    );

    $self->{irc}->add_handler(
        'part',
        sub {
            my ( $conn, $event ) = @_;
            my ($channel) = ( $event->to )[0];
            $channel =~ s/^-?#?//;

            if ( $event->{nick} eq $self->{user} ) {
                $ui->print("(you have quit $channel)\n");

                for my $nick (split ',', $self->{NAME}->{$channel}->{MEMBERS}) {
                    next if $nick eq $self->user_name;
                    
                    $self->state(NAME => $nick, __DELETE => 1)
                        if --$self->{NAME}->{$nick}->{COUNT} == 0;
                }
                $self->state(NAME => $channel, __DELETE => 1);
            }
            else {
                $ui->print(
                    "*** $event->{nick} is no longer a member of $channel ***\n"
                );
                $self->state(NAME => $event->{nick}, __DELETE => 1)
                    if --$self->{NAME}->{ $event->{nick} }->{COUNT} == 0;
            }

            # XXX Generate tlily quit event.
        }
    );

    # names
    $self->{irc}->add_handler(
        353,
        sub {
            my ( $conn, $event ) = @_;

            my @list = ( $event->args ); # eat yer heart out, mjd!

            my $channel = $list[2];
            $channel =~ s/^-?#?//;
            my @users   = map { s/^(@|\+)//; $_; } split ' ', $list[3];

            $self->state(NAME => $channel, CREATION => 1, MEMBERS => join(',', @users));
            for my $user (@users) {
                if (defined $self->{NAME}->{$user}) {
                    $self->{NAME}->{$user}->{COUNT}++;
                }
                else {
                    $self->state(NAME => $user, LOGIN => 1, COUNT => 1);
                }
            }
        }
    );

    # /finger
    $self->{irc}->add_handler(
        'whoisuser',
        sub {
            my ( $conn, $event ) = @_;
            $ui->print( "* Pseudo: " . $event->{args}[1] . "\n" .
                        "* Name: " . $event->{args}[5] . "\n" .
                        "* Host: " . $event->{args}[3] . "\n" .
                        "\n" );
        }
    );

    # rudimentary show mode handler.
    $self->{irc}->add_handler(
        'mode',
        sub {
            my ( $conn, $event ) = @_;

            $ui->print( "Mode: $event->{from} set " . 
                join(" ",@{$event->{args}}) . " (" .
                join(" ",@{$event->{to}})   . ")\n" );

        }
    );
 
    # (no permissions to op, among others)
    $self->{irc}->add_handler(
        482,
        sub {
            my ( $conn, $event ) = @_;

            my ( $id, $channel, $msg) = ( $event->args);
            $channel =~ s/^#/-/g;

            $ui->print( "$channel: $msg\n");

        }
    );

    # Add Net::IRC processing to tlily's events.
    $self->{netirc}->timeout(0.01);

    $self->add_server();

    # stash a "server name" for use in the status bar.
    # XXX not sufficient.
    $self->state(DATA   => 1,
                 NAME   => "NAME",
                 VALUE  => $self->{'host'});

    TLily::Event::send(
        type   => 'connected',
        server => $self
    );

    return $self;
}

sub command {
    my ( $self, $ui, $text ) = @_;

    # Check global command bindings.
    TLily::Server::command( $self, $ui, $text ) && return 1;

    $self->cmd_process(
        $text,
        sub {
            my ($event) = @_;

            if ( exists( $event->{text} ) ) {
                $ui->print( $event->{text} );
            }
            1;
        }
    );

    return 1;
}

=item cmd_process()

Execute a lily-like command on an IRC server, and process the output
through a passed-in callback.

Args:
    --  "lily" command to execute
    --  callback to process the output of the command

Used to custom-process the output of a "lily" command.  It will execute
the passed command, and call the callback given for each line returned
by the lily server.  The lines are passed into the callback as TLily
events.

=cut

my $cmdid = 1;

sub cmd_process {
    my ( $self, $command, $callback ) = @_;

    return unless ( $command =~ /\S/ );

    my %commands = (
        away   => \&cmd_away,
        awa    => \&cmd_away,
        aw     => \&cmd_away,
        a      => \&cmd_away,
        bye    => \&cmd_detach,
        by     => \&cmd_detach,
        b      => \&cmd_detach,
        detach => \&cmd_detach,
        detac  => \&cmd_detach,
        deta   => \&cmd_detach,
        det    => \&cmd_detach,
        de     => \&cmd_detach,
        d      => \&cmd_detach,
        finger => \&cmd_finger,
        finge  => \&cmd_finger,
        fing   => \&cmd_finger,
        fin    => \&cmd_finger,
        fi     => \&cmd_finger,
        f      => \&cmd_finger,
        join   => \&cmd_join,
        joi    => \&cmd_join,
        jo     => \&cmd_join,
        j      => \&cmd_join,
        kick   => \&cmd_kick,
        kic    => \&cmd_kick,
        ki     => \&cmd_kick,
        k      => \&cmd_kick,
        help   => \&cmd_help,
        hel    => \&cmd_help,
        he     => \&cmd_help,
        h      => \&cmd_help,
        mode   => \&cmd_mode,
        mod    => \&cmd_mode,
        mo     => \&cmd_mode,
        m      => \&cmd_mode,
        quit   => \&cmd_quit,
        qui    => \&cmd_quit,
        qu     => \&cmd_quit,
        q      => \&cmd_quit,
        rename => \&cmd_rename,
        renam  => \&cmd_rename,
        rena   => \&cmd_rename,
        ren    => \&cmd_rename,
        re     => \&cmd_rename,
        r      => \&cmd_rename,
        who    => \&cmd_who,
        wh     => \&cmd_who,
        w      => \&cmd_who,
    );

    &$callback(
        {
            type    => "begincmd",
            server  => $self,
            ui_name => $self->{ui_name},
            cmdid   => $cmdid++
        }
    );

    my $result = '';
    if ( $command =~ /^\s*\/(\w+)\s*(.*?)\s*$/ ) {
        my $func = \&cmd_default;

        if ( exists( $commands{ lc($1) } ) ) {
            $func = $commands{ lc($1) };
        }

        $result = &{$func}( $self, $2 );
    }
    elsif ( $command =~ /^([^;:]+)([:;])(.*)$/ ) {
        my ( $target, $sep, $msg ) = ($1, $2, $3);
        $result = $self->cmdsend( $sep, $target, $msg );
    }

    foreach ( split /\n/, $result ) {
        &$callback(
            {
                type    => "text",
                server  => $self,
                ui_name => $self->{ui_name},
                text    => "$_\n",
                cmdid   => $cmdid
            }
        );
    }

    &$callback(
        {
            type    => "endcmd",
            server  => $self,
            ui_name => $self->{ui_name},
            cmdid   => $cmdid
        }
    );

    # unidle ourselves on the server.
    #$self->send_sflap(toc_set_idle => 0);

    return;
}

=item fetch()

Fetch a file from the server.
Args(as hash):
    call    --  sub to call with returned data
    type    --  info or memo or (coming soon) config
    target  --  user or discussion to apply to; leave out for yourself
    name    --  if type == memo, the memo name
    ui      --  the ui to print a message to

=cut

sub fetch {
    my ( $this, %args ) = @_;
    my $ui = $args{ui};

    $ui->print("(fetch operation is not available on IRC connections)\n")
      if $ui;
    return;
}

=item store()

Store a file on the server.
Args(as hash):
    text    --  text to save
    type    --  info or memo or (coming soon) config
    target  --  user or discussion to apply to; leave out for yourself
    name    --  if type == memo, the memo name
    ui      --  the ui to print a message to

=cut

sub store {
    my ( $this, %args ) = @_;
    my $ui = $args{ui};

    $ui->print("(store operation is not available on IRC connections)\n")
      if $ui;
    return;
}

sub send_message {
    my ( $self, $recips, $separator, $message ) = @_;

    my @recips = split ',', $recips;
    if ( !@recips ) {
        if ( $separator eq ":" ) {
            @recips = ( $self->{last_message_from} );
        }
        else {
            @recips = ( $self->{last_message_to} );
        }
    }

    my $ui = TLily::UI::name( $self->{ui_name} );

    foreach my $recip (@recips) {
        $recip =~ s/^-#?/#/; # - marks a tlily discussion
        $self->{irc}->privmsg( "$recip", $message );
        $ui->print("(message sent to $recip)\n");
    }

    return;
}

###############################################################################
# Private methods

sub cmd_detach {
    my ( $self, $message ) = @_;

    $self->terminate($message);
    return;
}

sub cmd_finger {
    my ( $self, $user ) = @_;
    
    $self->{irc}->whois($user);
    return;
}

sub cmd_mode {
    my ( $self, $message ) = @_;

    $self->{irc}->mode($message);
    return;
}

sub cmd_kick {
    my ( $self, $message ) = @_;

    $self->{irc}->kick(split ('',$message));
    return;
}

sub cmd_join {
    my ( $self, $disc, $pw ) = @_;

    $disc =~ s/^-//;
    if ( $disc !~ /^#/ ) { $disc = "#$disc" }

    $self->{irc}->join( "$disc", $pw );
    return;
}

sub cmd_quit {
    my ( $self, $disc ) = @_;

    $disc =~ s/^-//;
    if ( $disc !~ /^#/ ) { $disc = "#$disc" }

    $self->{irc}->part("$disc");
    return;
}

sub cmd_away {
    my ( $self, $blurb ) = @_;

    $self->{irc}->away($blurb);
    return;
}

sub cmd_rename {
    my ( $self, $nick ) = @_;

    my $ui = TLily::UI::name( $self->{ui_name} );

    $self->{user} = $nick;
    $self->{irc}->nick($nick);
    $self->state(DATA  => 1,
                 NAME  => "whoami",
                 VALUE => $self->{user});
    $ui->print("(you are now named $nick)\n");

    # XXX Generate a lily rename event.
    return;
}

sub cmd_who {
    my ($self, $channel) = @_;

    $channel =~ s/^-?#?//;    

    my $ui = TLily::UI::name( $self->{ui_name} );
    
    if ($self->{NAME}->{$channel}->{CREATION}) {
        $ui->print(" Name\n");
        $ui->print(" ----\n");
        for my $user (split ",", $self->{NAME}->{$channel}->{MEMBERS}) {
            $ui->print(" ", $user, "\n");
        }
        $ui->print("\n");
    }
    else {
        $ui->print("(could find no discussion to match to \"$channel\")\n");
    }
    
    return;
}

sub cmd_help {
    my ( $self, $argstr ) = @_;

    return <<"END_HELP";

The following commands are available:

    /away      /bye
    /detach    /finger
    /help      /join
    /kick      /mode
    /quit      /rename
    /who

END_HELP
}

sub cmd_default {
    my ( $self, $argstr ) = @_;

    return "(unrecognized command)";
}

=for comment

Since lily-style sends can be very verbose, we make a small effort to
collapse multiple sends that occcur in a a brief span of time into
a single user visible send.

Right now, we do this by stripping off the first line of the followup
messages.  Ideally, we should allow the user to specify a "first send" 
and "followup send" format which would each be applied as necessary.
Users should also be able to specify the throttle speed at which a new
send (and, in most cases, a new *timestamp* is therefore used.

This could potentially be turned on with an option for other server
types. There is some pushback to enabling this by default everywhere,
and to be honest, the type of sends one sees on IRC more commonly *need*
this sort of collapse, while lily does not, to the same degree.

Because of the limited use of IRC support, however, we can pretty much
do whatever we want to IRC sends. Muahahah. 

If this does become a generic server thing, move it to a more appropriate
location.
--Coke

=cut

my $last_event;             # Keep track of the last event received.
my $last_event_ts = -1;     # When did we last process an event?
my $collapse_interval = 5;  # of seconds before a new send isn't collapsed. 

sub queued_event_handler {
    my ($e) = shift;

    # Immediately save off the last event - if we decide not to collapse
    # anymore, we can just exit out of the sub at this point.
    my $old_e      = $last_event;
    $last_event    = $e;
    my $now = time();

    # XXX For now, ONLY process these events for irc servers.
    if ( exists $e->{server} && $e->{server}->{proto} ne "irc" ) { return }

    # Skip events that aren't user level. (XXX not necessary for irc-only)
    # return if $e->{type} eq "slcp_data";

    my $ui = TLily::UI->name( $e->{ui_name} );

    my $publish_queued = 0;
    my $set_timer      = 0;
    my $enqueue_event  = 0;

    # Is the interval since our last event short enough to merit
    # checking for collapsable sends?
    my $interval = $now - $last_event_ts;
    $last_event_ts = $now;  # remember this as we might exit here...
    if ( $interval > $collapse_interval) { return }

    # Does this new event match the last event, in: server, source,
    # recipients, type? If the answer to any of these is no, then
    # simply exit this handler and let the normal print process
    # handle it. If it *does* match, then check our time delay.

    if ( $e->{server} != $old_e->{server}) { return }
    if ( $e->{SOURCE} != $old_e->{SOURCE}) { return }
    if ( $e->{RECIPS} != $old_e->{RECIPS}) { return }
    if ( $e->{type}   != $old_e->{type}  ) { return }
    # Only handle public/private messages for now
    if ( $e->{type} ne 'public' && $e->{type} ne 'private') { return }

    # Ok. All conditions are met. Let the normal event handlers know that this
    # is an event that can be collapsed.
    $e->{_collapsable} = 1;
    return;
}

# Register our event collapser.
event_r( type => 'all', order => 'before', call => \&queued_event_handler );

=item terminate()

Shuts down a server instance. Override our parent version, as we don't
have a {sock} ATM.

=cut

sub terminate {
    my ( $self, $message ) = @_;

    $self->{irc}->quit($message) if $self->{irc};
    $self->{irc} = undef;

    $self->TLily::Server::terminate();

    return;
}

1;
