# XXX need to handle SIGNON packets which are sent after a PAUSE
# XXX (re-signon and tell the user)
#
# Need to handle toc_set_config to persist buddy settings.

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

package TLily::Server::AIM;

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

TLily::Server::AIM - TLily interface to AOL Instant Messenger (TOC Protocol)

=head1 SYNOPSIS

use TLily::Server::AIM;

=head1 DESCRIPTION

This class interfaces tlily to the AIM service.  It also provides a set of 
/commands for use with AIM messenging.

Note:  For compatibility, this is subclassed from SLCP, and all the state
       database-related code is left unmolested.   Ideally though, this code
       should be refactored into the base class and SLCP and TOC should sit 
       side by side, since TOC is not REALLY a subclass of SLCP.

=head1 FUNCTIONS

=cut

my $handlers_init = 0;

sub init () {
    return if $handlers_init;
    $handlers_init = 1;

    event_r(type => 'toc_data',
            call => \&parse_sflap);
}

# need an API to get at the one in TLily::Server.. generally need to refactor 
# the connect stuff out of that function, so we canuse tlily::Server.
my %server;

sub new {
    my($proto, %args) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};
    bless $self, $class;

    # Generate a unique name for this server object.
    my $name = "AIM";
    if ($server{$name}) {
	my $i = 2;
	while ($server{$name."#$i"}) { $i++; }
	$name .= "#$i";
    }

    $self->{name}      = $name if (defined($args{name}));
    @{$self->{names}}  = ($name);
    $self->{ui_name}   = $args{ui_name} || "main";
    $self->{proto}     = "toc";
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

    init();

    my $ui = TLily::UI::name($self->{ui_name});

    $ui->print("Logging into AIM...");

    unless ($self->{user} =~ /\S/ &&
            $self->{password} =~ /\S/) {
        $ui->print("\nLogin Error: Username/Password Not Specified!\n");
        return $self;
    }

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
        require Net::AOLIM;
    };
    die "Error loading Net::AOLIM: $@\n" if $@;

    eval {
        $self->{aim} = Net::AOLIM->new(
            username => $self->{user},
            password => $self->{password},
            allow_srv_settings => 0,  # prevent it from calling toc_set_config
            callback => sub {
                die "Net::AOLIM callback was invoked - this should not happen.\n";
            }
        );
        
        die "Error creating Net::AOLIM object! (user='$self->{user}')\n"
            unless defined($self->{aim});

        $self->{aim}->add_buddies("friends", $self->{user});

        if (! defined($self->{aim}->signon())) {
            my $ERROR = $Net::AOLIM::ERROR_MSGS{$main::IM_ERR};
            $ERROR =~ s/\$ERR_ARG/$main::IM_ERR_ARGS/g;

            die "AIM Signon Error: $ERROR\n";
        }
        $self->{sock} = ${$self->{aim}->srv_socket};
    };
    if ($@) {
	$ui->print("failed: $@");
	return;
    }

    $ui->print("connected.\n\n");

    TLily::Server::tl_nonblocking($self->{sock});

    $self->{io_id} = TLily::Event::io_r(handle => $self->{sock},
					mode   => 'r',
					obj    => $self,
					call   => \&TLily::Server::reader);

    $self->add_server();

    # stash a "server name" for use in the status bar.
    $self->state(DATA   => 1,
                 NAME   => "AIM");

    # Tell AIM we're here..
    $self->send_sflap(toc_set_idle => 0);

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
    --  lily command to execute
    --  callback to process the output of the command

Used to custom-process the output of a lily command.  It will execute
the passed command, and call the callback given for each line returned
by the lily server.  The lines are passed into the callback as TLily
events.

Example:

    my $server = TLily::Server::active(); # get current active server

    my $count = 0;

    $server->cmd_process("/who here",  sub {
        my($event) = @_;

        # Don't want user to see output from /who
        $event->{NOTIFY} = 0;

        if ($event->{type} eq 'endcmd') {
          # If type is 'endcmd', command is finished, print out result.
          $ui->print("(There are $count people here)\n");
        } elsif ($event->{type} ne 'begincmd') {
          # Command has started, match only lines ending in 'here';
          # increment counter for each found.
          $count++ if ($event->{text} =~ /here$/);
        }

        return 0;
    });

=cut

my $cmdid = 1;
sub cmd_process {
    my($self, $command, $callback) = @_;

    return unless ($command =~ /\S/);

    my %commands = (away  => \&cmd_away,
                    awa   => \&cmd_away,
                    aw    => \&cmd_away,
                    a     => \&cmd_away,
                    buddy => \&cmd_buddy,
                    budd  => \&cmd_buddy,
                    bud   => \&cmd_buddy,
                    bu    => \&cmd_buddy,
                    b     => \&cmd_buddy,
                    here  => \&cmd_here,
                    her   => \&cmd_here,
                    help  => \&cmd_help,
                    hel   => \&cmd_help,
                    who   => \&cmd_who,
                    wh    => \&cmd_who,
                    w     => \&cmd_who);

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
    $self->send_sflap(toc_set_idle => 0);
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

    $ui->print("(fetch operation is not available on AIM connections)") if $ui;
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

    $ui->print("(store operation is not available on AIM connections)") if $ui;
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

    $message = qq(<html><body><font face="Helvetica" color="#000000">$message</font></body></html>);
    my $ui = TLily::UI::name($self->{ui_name});
    
    foreach my $recip (@recips) {
        my $target  = $self->{aim}->norm_uname($recip);
        next unless ($target =~ /\S/);

        $self->send_sflap(toc_send_im => $target, $message);
        $ui->print("(message sent to $recip)\n");
    }

    # unidle ourselves on the server.
    $self->send_sflap(toc_set_idle => 0);
}


###############################################################################
# Private methods


# This code is derived from Net::AOLIM- i couldn't use their code directly
# because it was not compatible with our non-blocking IO.
sub parse_sflap {
    my($event, $handler) = @_;
    
    my $serv = $event->{server};
    my $hlen = $Net::AOLIM::SFLAP_HEADER_LEN;

    $serv->{pending} .= $event->{data};

    return if (length($serv->{pending}) < $hlen);

    my $rsp_header = substr($serv->{pending}, 0, $hlen);
    
    my ($rsp_ast,$rsp_type,$rsp_seq_new,$rsp_dlen) =
        unpack "aCnn", $rsp_header;

    # is the whole packet in the pending buffer?
    if ($rsp_dlen && (length($serv->{pending}) < $hlen + $rsp_dlen)) {
        return;
    }
    
    # Yes?  OK, grab it out of the buffer.
    my $rsp_recv_packet = substr($serv->{pending}, $hlen, $hlen+$rsp_dlen);
    
    # .. and take it out of the buffer.
    substr($serv->{pending}, 0, $hlen+$rsp_dlen) = '';

    my $packet;

    # ignore keepalive events
    if (($rsp_type == $Net::AOLIM::SFLAP_TYPE_KEEPALIVE)) {
        return;
    }

    # if it's a signon packet, we read the version number
    if (($rsp_type == $Net::AOLIM::SFLAP_TYPE_SIGNON) &&
        ($rsp_dlen == 4)) {
        ($packet) = unpack "N", $rsp_recv_packet;
    } else {
        # otherwise, we just read it as ASCII
        ($packet) = unpack "a*", $rsp_recv_packet;
    }

    my ($msg, $rest) = split(/:/, $packet, 2);
    my @msg_args = split(/:/, $rest, $Net::AOLIM::SERVER_MSG_ARGS{$msg});

    warn "Received toc_$msg: [@msg_args]\n" if $config{toc_debug};

    TLily::Event::send(server  => $serv,
                       ui_name => $serv->{'ui_name'},
                       type    => "toc_$msg",
                       args    => \@msg_args);

    1;  # stop processing this event, we're done.
}

sub cmd_away {
    my ($self, $awaymsg) = @_;
    
    my $awaymsg ||= "Currently Away";

    $self->send_sflap(toc_set_away => $awaymsg);

    $self->state(HANDLE      => lc($self->{user}),
                 BLURB       => $awaymsg);

    return "(you are now away with the message '$awaymsg')\n";
}

sub cmd_here {
    my ($self, $argstr) = @_;
    
    $self->send_sflap('toc_set_away');

    $self->state(HANDLE      => lc($self->{user}),
                 BLURB       => "");

    return "(you are now here)\n";
}

sub cmd_help {
    my ($self, $argstr) = @_;

    return <<EOF;

The following commands are available:

    /who
    /here
    /away
    /help
    /buddy (not implemented yet)

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
        $self->send_sflap(toc_add_buddy => $buddy);
        $self->{BUDDY_GROUP}{$group}{$buddy} = 1;
        return "(added $buddy to buddy list)\n";

    } elsif ($op eq "delete" && @args == 1) {
        my ($buddy) = @args;

        $self->send_sflap(toc_remove_buddy => $buddy);
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


# adapted from Net::AOLIM as well..
sub send_sflap {
    my ($self, $command, @args) = @_;
    warn "toc_send($command [@args])\n" if $config{toc_debug};

    my $sflap_data = Net::AOLIM::toc_format_msg(undef, $command, @args);
    my $sflap_type = $Net::AOLIM::SFLAP_TYPE_DATA;

    # internal variables
    my ($ssp_header, $ssp_data, $ssp_packet, $ssp_datalen);

    # we need to be sure that there's only one \0 at the end of
    # the string
    $sflap_data =~ s/\0*$//;
    $sflap_data .= "\0";

    # now we calculate the length and make the packet
    $ssp_datalen = length $sflap_data;
    $ssp_data = pack "a".$ssp_datalen, $sflap_data;
    $ssp_header = pack "aCnn", "*", $sflap_type, $self->{aim}{client_seq_number}, $ssp_datalen;
    $ssp_packet = $ssp_header . $ssp_data;

    # if the packet is too long, return an error
    # our connection will be dropped otherwise
    if ((length $ssp_packet) >= $Net::AOLIM::SFLAP_MAX_LENGTH) {
       die "TOC packet exceeds maximum allowed length- dropping.\n";
    }

    $self->send($ssp_packet);
    $self->{aim}{client_seq_number}++;
}

1;

