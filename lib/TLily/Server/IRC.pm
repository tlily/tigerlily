# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
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

    eval { require TLily::Server::IRC::Driver; };
    die "Error loading Net::IRC: $@\n" if $@;

    eval {
        $self->{'netirc'} = TLily::Server::IRC::Driver->new();
        $self->{'irc'}    = $self->{'netirc'}->newconn(
            Server => $self->{'host'},
            Port   => $self->{'port'},
            Nick   => $self->{'user'},
            SSL    => $args{'ssl'},
        );

        die "Error creating Net::IRC object!')\n"
          unless defined( $self->{'irc'} );
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

            if ( $event->{nick} eq $self->{user} ) {
                $ui->print("(you have joined $channel)\n");
            }
            else {
                $ui->print(
                    "*** $event->{nick} is now a member of $channel ***\n");
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

            # XXX Generate tlily rename'd event, update our DB.
        }
    );

    $self->{irc}->add_handler(
        'part',
        sub {
            my ( $conn, $event ) = @_;
            my ($channel) = ( $event->to )[0];

            if ( $event->{nick} eq $self->{user} ) {
                $ui->print("(you have quit $channel)\n");
            }
            else {
                $ui->print(
                    "*** $event->{nick} is no longer a member of $channel ***\n"
                );
            }

            # XXX Generate tlily quit event.
        }
    );

    # names
    $self->{irc}->add_handler(
        353,
        sub {
            my ( $conn, $event ) = @_;

            my ( @list, $channel ) = ( $event->args ); # eat yer heart out, mjd!

            # splice() only works on real arrays. Sigh.
            ( $channel, @list ) = splice @list, 2;

           # XXX Store this information in our local DB of who is where, instead
           # of printing it out.
            $ui->print( "Users on $channel: " . join( ", ", @list ) . "\n" );

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
        join   => \&cmd_join,
        joi    => \&cmd_join,
        jo     => \&cmd_join,
        j      => \&cmd_join,
        help   => \&cmd_help,
        hel    => \&cmd_help,
        he     => \&cmd_help,
        h      => \&cmd_help,
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
        my ( $self, $sep, $target, $message ) = @_;
        $result = $self->cmdsend( $2, $1, $3 );
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
        $self->{irc}->privmsg( "$recip", $message );
        $ui->print("(message sent to $recip)\n");
    }
}

###############################################################################
# Private methods

sub cmd_detach {
    my ( $self, $message ) = @_;

    $self->terminate($message);
}

sub cmd_join {
    my ( $self, $disc, $pw ) = @_;

    if ( $disc !~ /^#/ ) { $disc = "#$disc" }

    $self->{irc}->join( "$disc", $pw );
    return;
}

sub cmd_quit {
    my ( $self, $disc ) = @_;

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

sub cmd_help {
    my ( $self, $argstr ) = @_;

    return <<EOF;

The following commands are available:

    /away
    /help
    /join
    /quit
    /rename

EOF
}

sub cmd_default {
    my ( $self, $argstr ) = @_;

    return "(unrecognized command)";
}

# Since lily-style sends can be very verbose, we make a small effort to
# collapse multiple sends that occcur in a very short span of time into
# a single user visible send. (For IRC only at the moment.)

# XXX - If we can avoid the delay caused by the combinations, then there
# shouldn't be an issue with turning this on (perhaps optionally) for
# SLCP servers either. For now, the delay required for SLCP (1.25s based
# on empirical testing) is too much for many
# users. If this code ever becomes more generic, move it out of IRC.pm

my $queued_event;           # There can be at most one queued event.
my $handle_queued_event;    # A timer that will fire and publish the event
                            #   if a new event isn't received in a short
                            #   amount of time.
my $queued_interval = 0.1;  # Fractional # of seconds to wait until a queued
                            # event is dumped.

sub queued_event_handler {
    my ($e) = @_;

    # XXX For now, only process these events for irc-style servers.
    if ( exists $e->{server} && $e->{server}->{proto} ne "irc" ) { return }

    # Disable the timer.
    TLily::Event::time_u($handle_queued_event);

    # Skip events that aren't user level. (XXX not necessary for irc-only)
    # return if $e->{type} eq "slcp_data";

    my $ui = TLily::UI->name( $e->{ui_name} );

    my $publish_queued = 0;
    my $set_timer      = 0;
    my $enqueue_event  = 0;

    # is there a queued event already?
    if ($queued_event) {

        #  If this event matches the queued_event, then
        # prepend the previous event into this one, and
        # delete the last event. Replace the queued event with
        # this one.
        #  An event matches if the type, source, and target match.

        # This recips handling is annoying, and may be too overprotective.
        my ( $recips_new, $recips_old );
        if ( $e->{RECIPS} ) {
            if ( ref $e->{RECIPS} eq "ARRAY" ) {
                $recips_new = join( ',', @{ $e->{RECIPS} } );
            }
            else {
                $recips_new = ( ref $e->{RECIPS} ) . $e->{RECIPS};
            }
        }
        if ( $queued_event->{RECIPS} ) {
            if ( ref $queued_event->{RECIPS} eq "ARRAY" ) {
                $recips_old = join( ',', @{ $queued_event->{RECIPS} } );
            }
            else {
                $recips_old = $queued_event->{RECIPS};
            }
        }

        if (    $e->{type} eq $queued_event->{type}
            and $e->{SOURCE} eq $queued_event->{SOURCE}
            and $recips_new  eq $recips_old )
        {

            # combine the events and set the timer.
            $e->{VALUE} = $queued_event->{VALUE} . "\n" . $e->{VALUE};
            undef $queued_event;
        }
        else {
            # doesn't match: publish the old event.
            $publish_queued = 1;
        }
    }

    #is the new event queueable? (new and of the right type)
    #  If the new event is a public, private, or emote send,
    # then queue it.

    if (
            ( $e->{NOTIFY} == 1 )
        and ( !exists $e->{_enqueued} )
        and (  $e->{type} eq "public"
            or $e->{type} eq "private"
            or $e->{type} eq "emote" )
      )
    {
        $enqueue_event = 1;
    }
    else {

        # don't touch it.
    }

    if ($publish_queued) {
        $queued_event->{NOTIFY} = 1;
        TLily::Event::send($queued_event);
        undef $queued_event;
    }
    if ($enqueue_event) {
        $e->{NOTIFY}    = 0;
        $e->{_enqueued} = 1;
        $queued_event   = $e;

       # Add a timer: If this timer goes off, the event will be re-published
       # This prevents the last event from being perpetually stuck in the queue.
        my $h = {
            after => $queued_interval,
            call  => sub {
                $queued_event->{NOTIFY} = 1;
                TLily::Event::send($queued_event);
                undef $queued_event;
              }
        };
        $handle_queued_event = TLily::Event::time_r($h);
        return 1;    # eat the event.
    }
    return 0;        # let the event propagate.
}
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
