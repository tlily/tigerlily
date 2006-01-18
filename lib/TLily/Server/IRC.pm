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
       should be refactored into the base class and SLCP and TOC should sit 
       side by side, since TOC is not REALLY a subclass of SLCP.

=head1 FUNCTIONS

=cut

#my $handlers_init = 0;

#sub init () {
    #return if $handlers_init;
    #$handlers_init = 1;
##
#}

# need an API to get at the one in TLily::Server.. generally need to refactor 
# the connect stuff out of that function, so we can use tlily::Server.
my %server;

sub new {
    my($proto, %args) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};
    bless $self, $class;

    # Generate a unique name for this server object.
    my $name = "IRC";
    if ($server{$name}) {
	my $i = 2;
	while ($server{$name."#$i"}) { $i++; }
	$name .= "#$i";
    }

    $self->{name}      = $name if (defined($args{name}));
    $self->{host}      = $args{host};
    @{$self->{names}}  = ($name);
    $self->{ui_name}   = $args{ui_name} || "main";
    $self->{proto}     = "irc";
    $self->{bytes_in}  = 0;
    $self->{bytes_out} = 0;
    $self->{last_message_from} = undef;
    $self->{last_message_to} = undef;

    # State database
    $self->{HANDLE}   = {};
    $self->{NAME}     = {};
    $self->{DATA}     = {};

    $self->{user}     = $args{user};
    $self->{password} = $args{password};

    #init();

    my $ui = TLily::UI::name($self->{ui_name});
    $ui->print("SETTING THE USER TO '$self->{user}'\n");

    $ui->print("Logging into IRC...\n");

    # remember ourselves..
    $self->state(HANDLE      => lc($self->{user}),
                 NAME        => $self->{user},
                 ONLINE      => 1,
                 EVIL        => 0,
                 ON_SINCE    => time,
                 IDLE        => 0,
                 LAST_UPDATE => time,
                 UNAVAILABLE => 0);

    eval {
        require Net::IRC;
    };
    die "Error loading Net::IRC: $@\n" if $@;

    eval {
        $self->{netirc} = Net::IRC->new();
        $self->{irc} = $self->{netirc}->newconn(
            Server   => $self->{host},
            Port     => 6667,
            Nick     => $self->{user}
        );
       
        die "Error creating Net::IRC object!')\n"
            unless defined($self->{irc});
    };
    if ($@) {
	     $ui->print("failed: $@");
  	     return;
    }

    # on_connect
    $self->{irc}->add_global_handler('376', sub {
      $ui->print("connected to $self->{host} as $self->{user}.\n\n");
    });

    $self->{irc}->add_handler('msg', sub {
      my ($conn,$event) = @_;
      TLily::Event::send({ server  => $self,
                           ui_name => $self->{'ui_name'},
                           type    => "private",
                           VALUE   => join(" ",@{$event->{args}}),
                           SOURCE  => $event->{nick},
                           SHANDLE => $event->{nick},
                           RECIPS  => $event->{to},
                           TIME    => time,
                           NOTIFY  => 1,
                           BELL    => 1,
                           STAMP   => 1 });
      $self->{last_message_from} = @{$event->{to}}[0];  #XXX Doesn't work
    });

    $self->{irc}->add_handler('public', sub {
      my ($conn,$event) = @_;
      TLily::Event::send({ server  => $self,
                           ui_name => $self->{'ui_name'},
                           type    => "public",
                           VALUE   => join(" ",@{$event->{args}}),
                           SOURCE  => $event->{nick},
                           SHANDLE => $event->{nick},
                           RECIPS  => join(" ", @{$event->{to}}),
                           TIME    => time,
                           NOTIFY  => 1,
                           BELL    => 0,
                           STAMP   => 1 });
      $self->{last_message_from} = @{$event->{to}}[0];  #XXX Doesn't work
    });

    # Nick Taken
    $self->{irc}->add_global_handler(433, sub {
      my ($conn) = @_;
      $ui->print("*** Your nick is already taken ***\n");
      # Keep adding _'s to our name! XXX need saner approach, neh?
      $self->{user} .= "_";  
      $conn->nick($self->{user});
      # XXX Generate a lily rename event.
    });

    $self->{irc}->add_handler('join', sub {
      my ($conn,$event) = @_;
      my ($channel) = ($event->to)[0];

      $ui->print("'$event->{nick}' vs. '$self->{user}'\n");
      if ($event->{nick} eq $self->{user}) {
        $ui->print("(you have joined $channel)\n");
      } else {  
        $ui->print("*** $event->{nick} has joined $channel ***\n");
      }

      # XXX Generate tlily join'd event.
    });


    # Add Net::IRC processing to tlily's events.
    $self->{netirc}->timeout(0.01);
    my $h = { 
       after => 0,
       interval => .02,
       call => sub {
           $self->{netirc}->do_one_loop(); 
       }
    };

    TLily::Event::time_r( $h );

    $self->add_server();

    # stash a "server name" for use in the status bar.
    $self->state(DATA   => 1,
                 NAME   => "IRC");

    TLily::Event::send(type   => 'connected',
		       server => $self);

    return $self;
}


sub command {
    my($self, $ui, $text) = @_;

    # Check global command bindings.
    TLily::Server::command($self, $ui, $text) && return 1;

    $self->cmd_process($text, sub { 
        my ($event) = @_;
        
        if (exists($event->{text})) {
            $ui->print($event->{text});
        }
        1;
    });

    return 1;
}

=item cmd_process()

Execute a lily command on a lily server, and process the output
through a passed-in callback.
Args:
    --  "lily" command to execute
    --  callback to process the output of the command

Used to custom-process the output of a lily command.  It will execute
the passed command, and call the callback given for each line returned
by the lily server.  The lines are passed into the callback as TLily
events.

=cut

my $cmdid = 1;
sub cmd_process {
    my($self, $command, $callback) = @_;

    return unless ($command =~ /\S/);

    my %commands = (join  => \&cmd_join,
                    joi   => \&cmd_join,
                    jo    => \&cmd_join,
                    j     => \&cmd_join,
                    help  => \&cmd_help,
                    hel   => \&cmd_help,
                    he    => \&cmd_help,
                    h     => \&cmd_help,
                    #who   => \&cmd_who,
                    #wh    => \&cmd_who,
                    #w     => \&cmd_who,
     );

    &$callback({type    => "begincmd",
                server  => $self,
                ui_name => $self->{ui_name},
                cmdid   => $cmdid++});

    my $result = "";
    if ($command =~ /^\s*\/(\w+)\s*(.*?)\s*$/) {
        my $func = \&cmd_default;               

        if (exists($commands{lc($1)})) {
            $func = $commands{lc($1)};
        }

        $result = &{$func}($self, $2);
    } elsif ($command =~ /^([^;:]+)([:;])(.*)$/) {
    my ($self, $sep, $target, $message) = @_;
        $result = $self->cmdsend($2, $1, $3);
    }

    foreach (split /\n/, $result) {
        &$callback({type    => "text",
                    server  => $self,
                    ui_name => $self->{ui_name},
                    text    => "$_\n",
                    cmdid   => $cmdid});
    }

    &$callback({type    => "endcmd",
                server  => $self,
                ui_name => $self->{ui_name},
                cmdid   => $cmdid});

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
    my($this, %args) = @_;
    my $ui     = $args{ui};

    $ui->print("(fetch operation is not available on IRC connections)\n") if $ui;
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
    my($this, %args) = @_;
    my $ui     = $args{ui};

    $ui->print("(store operation is not available on IRC connections)\n") if $ui;
    return;
}

sub send_message {
    my ($self, $recips, $separator, $message) = @_;

    my @recips = split ',',$recips;
    if (! @recips) {
        if ($separator eq ":") {
            @recips = ($self->{last_message_from});
        } else {
            @recips = ($self->{last_message_to});
        }
    }

    my $ui = TLily::UI::name($self->{ui_name});
    
    foreach my $recip (@recips) {
        #my $target  = $self->{irc}->norm_uname($recip);
        #next unless ($target =~ /\S/);

        $self->{irc}->privmsg("$recip",$message);
        $ui->print("(message sent to $recip)\n");
    }
}


###############################################################################
# Private methods

sub cmd_join {
    my ($self, $disc) = @_;
  
    if ($disc !~ /^#/) { $disc = "#$disc" };

    $self->{irc}->join("$disc");
    return;
}

sub cmd_help {
    my ($self, $argstr) = @_;

    return <<EOF;

The following commands are available:

    /help
    /join

EOF
}

sub cmd_who {
    my ($self, $argstr) = @_;

    my $all = 0;
       $all = 1 if ($argstr =~ /all/);

    my $ret = "Buddy List (online only):\n";
       $ret = "Buddy List (all):\n" if $all;

    foreach my $group (sort keys %{$self->{BUDDY_GROUP}}) {
        my $gr;
        my $c = 0;

        $gr .= "\nGroup '$group':\n";
        $gr .= "  Name                                      On Since   Idle  State\n";
        $gr .= "  ----                                   -----------   ----  -----\n";    

        foreach my $buddy (sort keys %{$self->{BUDDY_GROUP}{$group}}) {
            my %r = $self->state(HANDLE => lc($buddy));

            my $state = $r{UNAVAILABLE} ? "away" : "here";
            $state = "offline" unless $r{ONLINE};

            # support "/who all"- don't show offline folks with a regular /who.
            next if ($state eq "offline" && ! $all);

            $c++;

            my @t = localtime($r{ON_SINCE});
            my $onsince_str = sprintf("%02d/%02d/%02d", 
                                      $t[4]+1, $t[3], substr($t[5]+1900,2,2));
            if (time - $r{ON_SINCE} < 24*60*60) {
                $onsince_str = sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0]);
            }

            my $idle_str = idle_str($r{IDLE} + (time - $r{LAST_UPDATE}));

            if ($state eq "offline") {
                $onsince_str = "n/a";
                $idle_str    = "n/a";
            }

            $gr .= sprintf("  %-38s %11s %6s  %s\n",
                            $r{NAME}, $onsince_str, $idle_str, $state);
        }

        $ret .= $gr if ($c > 0);
    }

    return $ret;
}


sub cmd_buddy {
    my ($self, $argstr) = @_;

    # XXX a real argstr parser with quoting and such would be wise.

    my @args = split /\s+/, $argstr;

    my $op = shift @args;

    if ($op eq "add" && @args == 2) {
        my ($group, $buddy) = @args;
        #$self->send_sflap(toc_add_buddy => $buddy);
        $self->{BUDDY_GROUP}{$group}{$buddy} = 1;
        return "(added $buddy to buddy list)\n";

    } elsif ($op eq "delete" && @args == 1) {
        my ($buddy) = @args;

        #$self->send_sflap(toc_remove_buddy => $buddy);
        foreach my $group (keys %{$self->{BUDDY_GROUP}}) {
            delete $self->{BUDDY_GROUP}{$group}{$buddy};
        }
        return "(removed $buddy from buddy list)\n";
    } else {
        return "(/buddy [add <group> <buddy name>] [delete <buddy name>])\n";
    }
}


# clumsily ported from lily..
sub idle_str {
    my ($idle) = @_;

    my $idle_str = "";
    my $secs_per_day = 60*60*24;
    if ($idle >= 3 * (365 * $secs_per_day)) {
        my $ww = int($idle % (365 * $secs_per_day) / (7 * $secs_per_day));
        $idle_str = int($idle / (365 * $secs_per_day)) . "y" . ($ww ne "0" ? $ww . "w" : "");
    } elsif ($idle >= 10 * (7 * $secs_per_day)) {
        my $dd = int($idle % (30 * $secs_per_day) / $secs_per_day);
        $idle_str = int($idle / (30 * $secs_per_day)) . "M" . ($dd ne "0" ? $dd . "d" : "");
    } elsif ($idle >= (7 * $secs_per_day)) {
        my $dd = int($idle % (7 * $secs_per_day) / $secs_per_day);
        $idle_str = int($idle / (7 * $secs_per_day)) . "w" . ($dd ne "0" ? $dd . "d" : "");
    } elsif ($idle >= $secs_per_day) {
        my $hh = int($idle % $secs_per_day / 60*60);
        $idle_str = int($idle / $secs_per_day) . "d" . $hh . "h";
    } elsif ($idle >= 60*60) {
        my $ss = int($idle % 60*60 / 60);
        $idle_str = int($idle / 60*60) . ":" . (length($ss) == 1 ? "0" : "") . $ss;
    } elsif ($idle >= 60) {
        $idle_str = int($idle / 60) . "m";
    }

    return $idle_str;
}

sub cmd_default {
    my ($self, $argstr) = @_;

    return "(unrecognized command)";    
}


1;

