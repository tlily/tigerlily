#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Server/Attic/SLCP.pm,v 1.49 2003/08/17 01:49:20 steve Exp $

package TLily::Server::SLCP;

use strict;
use vars qw(@ISA %config);

use Carp;

use TLily::Version;
use TLily::Server;
use TLily::Extend;
use TLily::Config qw(%config);
use TLily::UI;
use TLily::Utils qw(&save_deadfile &get_deadfile);

@ISA = qw(TLily::Server);

=head1 NAME

TLily::Server::SLCP - TLily SLCP lily server module

=head1 SYNOPSIS

use TLily::Server::SLCP;

=head1 DESCRIPTION

This class implements the SLCP lily client server interface.  This,
coupled with the SLCP extensions, allow TLily to communicate with a
modern SLCP-based lily server.

=head1 FUNCTIONS

=cut
my $cmd_handlers_init = 0;

sub init () {
    return if ($cmd_handlers_init);
    $cmd_handlers_init = 1;

    # The order of these handlers is important!
    TLily::Event::event_r(type => 'begincmd',
            call => sub {
                my($e) = @_;
                my $server = $e->{server};
                my $cmd = $e->{command};
                my $id = $e->{cmdid};

                if (defined $server->{pending_cmds}{$cmd}) {
                    $server->{active_cmds}{$id} = $server->{pending_cmds}{$cmd};
                    delete $server->{pending_cmds}{$cmd};
                }
                return 0;
            });

    TLily::Event::event_r(type => 'all',
            call => sub {
                my($e) = @_;
                my $server = $e->{server};
                my $id = $e->{cmdid};

                return 0 if ($e->{type} eq 'endcmd');
                return 0 unless ($id);
                my $f = $server->{active_cmds}{$id};
                &$f($e) if (defined $f);
                return 0;
            });

    TLily::Event::event_r(type => 'endcmd',
            call => sub {
                my($e) = @_;
                my $server = $e->{server};
                my $id = $e->{cmdid};

                if (defined $server->{active_cmds}{$id}) {
                    my $f = $server->{active_cmds}{$id};
                    &$f($e) if (defined $f);
                    delete $server->{active_cmds}{$id};
                }
                return 0;
            });

    TLily::Event::event_r(type => 'export',
                          call => sub {
        my($event, $handler) = @_;

        my $ex = shift @{$event->{server}->{_export_queue}};
        return 0 unless $ex;

        my $ui = ui_name($ex->{ui_name}) if (defined $ex->{ui_name});

        if ($event->{response} eq 'OKAY') {
            foreach my $l (@{$ex->{text}}) {
                $event->{server}->sendln($l);
            }
        } else {
            $ui->print("(Unable to set $ex->{type} \"$ex->{name}\")\n")
                unless ! $ui;
            unless (save_deadfile($ex->{type}, $event->{server},
                                  $ex->{name}, $ex->{text})) {
	        $ui->print("(Unable to save \"$ex->{name}\"; changes lost)\n")
                    unless ! $ui;
            }
        }

        return 1;
    });

#    TLily::Event::event_r(type => 'import',
#                          call => sub {
#        my($event, $handler) = @_;
#
#        my $ex = shift @{$event->{server}->{_export_queue}};
#        return 0 unless $ex;
#
#        my $ui;
#        $ui = ui_name($ex->{ui_name}) if (defined $ex->{ui_name});
#
#    });
}


sub new {
    my($proto, %args) = @_;
    my $class = ref($proto) || $proto;

    $args{port}     ||= 7777;
    $args{protocol}   = "slcp";
    $args{ui_name}    = "main" unless exists($args{ui_name});

    my $self = $class->SUPER::new(%args);

    $self->{HANDLE}   = {};
    $self->{NAME}     = {};
    $self->{DATA}     = {};

    $self->{active_cmds} = {};
    $self->{pending_cmds} = {};

    $self->{user}     = $args{user};
    $self->{password} = $args{password};

    # Initialize the command processing handlers
    init();

    # set the client name once we're %connected.
    my $sub = sub {
	my ($e,$h) = @_;

	return 0 unless ($e->{server} == $self);

	$self->set_client_name();
	$self->get_user_perms();
	TLily::Event::event_u($h->{id});

	return 0;
    };
    TLily::Event::event_r(type => "connected",
			  call => $sub);
	
    # set the client options at the first prompt.
    $sub = sub {
	my ($e,$h) = @_;
	return 0 unless ($e->{server} == $self);
	my $ui = TLily::UI::name($self->{ui_name});

	TLily::Event::event_u($h->{id});

	$self->set_client_options();
	
	# allow the user's input to go to the server now.
	$self->{ALLOW_SEND} = 1;
	
	if (defined $self->{user}) {
	    $ui->print("(using autologin information)\n") if ($ui);
	    $self->send($self->{user});
	    $self->send(" ".$self->{password}) if defined ($self->{password});
	    $self->sendln();
	    delete $self->{user};
	    delete $self->{password};
	    return 1;
	}

	return 0;
    };
    TLily::Event::event_r(type => "prompt",
			  call => $sub);

    bless $self, $class;
}


sub command {
    my($self, $ui, $text) = @_;

    # Check global command bindings.
    $self->SUPER::command($ui, $text) && return 1;

    # We don't allow any the user to send any text to the server until
    # The options sent.   This prevents the "Error -2" condition with slow
    # links.
    
    if ($self->{ALLOW_SEND}) {
        foreach (@{$self->{send_buffer}}) {
            $self->sendln($_);
        }
	undef $self->{send_buffer};
	
        # Send the line on to the server.
        $self->sendln($text);

    } else {
        $self->{send_buffer} ||= [];
        push @{$self->{send_buffer}}, $text;
    }
    
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

sub cmd_process {
    my($self, $c, $f) = @_;
    $self->{pending_cmds}{$c} = $f;
    $self->sendln($c);

}

=item expand_name()

Translates a name into a full lily name.  For example, 'cougar' might become
'Spineless Cougar', and 'comp' could become '-computer'.  The name returned
will be identical to canonical one used by lily for that abberviation,
with the exception that discussions are returned with a preceding '-'.
If the name is an exact match (modulo case) for a group, the group name
is returned.  Substrings of groups are not, however, expanded.  This is
in line with current lily behavior.

If $config{expand_group} is set, groups will be expanded into a
comma-separated list of their members.

    expand_name('comp');

=cut

sub expand_name {
    unshift @_, scalar(TLily::Server::active()) if (@_ < 2);
    my($self, $name, %opts) = @_;
    my $disc;
    my $user;

    $name = lc($name);
    $name =~ tr/_/ /;
    $disc = 1 if ($name =~ s/^-//);
    $user = 1 if ($name =~ s/^~//);

    # Check for "me".
    if (!$disc && $name eq 'me') {
	return $self->user_name || 'me';
    }

    # Check for a group match.
    if (!$user && !$disc && $self->{NAME}->{$name}->{MEMBERS}) {
    	if ($config{expand_group}) {
	    return join ',', map { $self->get_name(HANDLE => $_) }
 	                         split /,/,$self->{NAME}->{$name}->{MEMBERS};
	} else {
	    return $self->{NAME}->{$name}->{NAME};
	}
    }
    
    # Check for an exact match.
    if ($self->{NAME}->{$name}) {
	if ($self->{NAME}->{$name}->{LOGIN} && !$disc) {
	    return $self->{NAME}->{$name}->{NAME};
	} elsif ($self->{NAME}->{$name}->{CREATION} && !$user) {
	    return '-' . $self->{NAME}->{$name}->{NAME};
	}
    }

    return if $opts{exact};

    # Check the "preferred match" list.
    if (ref($config{prefer}) eq "ARRAY") {
	my $m;
	foreach $m (@{$config{prefer}}) {
            next unless $m =~ /^-?(.*)/;
            next unless $self->{NAME}->{$1};

	    $m = lc($m);
	    $m =~ tr/_/ /;
	    return $m if (index($m, $name) == 0);
	    return $m if ($m =~ /^-/ && index($m, $name) == 1);
	}
    }

    my(@unames, @dnames);
    foreach (keys %{$self->{NAME}}) {
	push @unames, $_ if ($self->{NAME}->{$_}->{LOGIN});
	push @dnames, $_ if ($self->{NAME}->{$_}->{CREATION});
    }

    my @m;
    # Check for a prefix match.
    unless ($disc) {
	@m = grep { index($_, $name) == 0 } @unames;
	return if (@m > 1 && !wantarray);
	return map($self->{NAME}->{$_}->{NAME}, @m) if (@m);
    }
    unless ($user) {
	@m = grep { index($_, $name) == 0 } @dnames;
	return if (@m > 1 && !wantarray);
	return map('-'.$self->{NAME}->{$_}->{NAME}, @m) if (@m);
	return if (@m > 1);
    }

    # Check for a substring match.
    my $n;
    unless ($disc) {
	@m = grep { index($_, $name) != -1 } @unames;
	return if (@m > 1 && !wantarray);
	# If a user /renamed from a name that's like a discussion,
	# it may be found in @m.  We don't want that.
	if (@m && ($m[0] ne $self->{NAME}->{$m[0]}->{NAME})) {
	    $n = \@m;
	}
	elsif (@m) {
	    return map($self->{NAME}->{$_}->{NAME}, @m);
	}
    }
    unless ($user) {
	@m = grep { index($_, $name) != -1 } @dnames;
	return if (@m > 1 && !wantarray);
	return map('-'.$self->{NAME}->{$_}->{NAME}, @m) if (@m);
    }

    return map($self->{NAME}->{$_}->{NAME}, @$n) if $n;

    return;
}


=item user_name

The pseudo used by the current user.  Example:

    $Me = $serv->user_name;

=cut

sub user_name () {
    my ($self) = @_;

    my $hdl = $self->user_handle();
    return unless (defined $hdl);

    my %rec = $self->state(HANDLE => $hdl);
    return defined($rec{NAME}) ? $rec{NAME} : $hdl;
}


=item user_handle

The MOO object ID for the current user.

=cut

sub user_handle () {
    my ($self) = @_;

    return $self->{DATA}{whoami};
}


=item state()

This function provides access to the Server module's User State database.
It allows creating, updating, and retrieval of records from this db.

The syntax is a little special because of this flexibility, but I think
it will make sense.  Parameter names map directly to SLCP's, in case
you were curious.  Extra parameters will be ignored.  Currently
HANDLE and NAME are the database keys, and any other data is stored.

Note that this state database makes no distinction between users, groups,
and discussions.  All can be stored here, which is convenient.

Example:

    # add "Josh"
    $serv->state(HANDLE => "#123",
                 NAME => "Josh",
                 BLURB => "@work");

    # retrieve Josh's record by Handle
    %josh = $serv->state(HANDLE => "#123");

    # retrieve Josh's record by Name
    %josh = $serv->state(NAME => "Josh");

    # set a DATA item:
    $serv->state(DATA => 1,
                 NAME => "whoami",
                 VALUE => "#850");

    # retrieve a DATA item:
    $val = $serv->state(DATA => 1,
                        NAME => "whoami");

or

    $val = $serv->{DATA}{whoami};

=cut

sub state {
    my ($self,%args) = @_;
    
    # Deal with DATA items.
    # The DATA arg must be set if you want to use these.
    if ($args{DATA}) {
	if ($args{VALUE}) {
	    $self->{DATA}{$args{NAME}} = $args{VALUE};      
	}
	return $self->{DATA}{$args{NAME}};
    } 
    
    # OK, the rest of this function refers to the normal records, which
    # are indexed by HANDLE and NAME.
    
    carp "bad state call: HANDLE=\"$args{HANDLE}\", NAME=\"$args{NAME}\""
      unless ($args{HANDLE} || $args{NAME});
    
    # figure out if the user is querying or insert/updating.
    my $query = 1;
    foreach (keys %args) {
	if ( ! /^(HANDLE|NAME)$/ ) {
	    $query = 0;
	}
    }
    
    if ($query) {
	# ok, it's a query.  return a copy of the record (preferring
	# the HANDLE index, but using either.
	if ($args{HANDLE}) {
	    my $h = $self->{HANDLE}{$args{HANDLE}};
	    return $h ? %$h : undef;
	} else {
	    my $h = $self->{NAME}{lc($args{NAME})};
	    return $h ? %$h : undef;
	}
    } else {
	# OK.  So now we have either an insert or an update.
	# First check to see if we have a record in the
	# database (in which case it's an update)
	
	my $record;
	if ($args{HANDLE}) {
	    $record = $self->{HANDLE}{$args{HANDLE}};
	} else {
	    $record = $self->{NAME}{lc($args{NAME})};
	}
	
	if (! ref($record)) {
	    # create a new record if one was not found.
	    $record = {};
	}

	# If the handle (unlikely) or name are being updated, remove the
	# old entry from the indices.  (Note: save_crufty_renames is
	# intentionally undocumented.)
	delete $self->{HANDLE}->{$record->{HANDLE}}
	  if (defined($args{HANDLE}) && !$config{save_crufty_renames});
	delete $self->{NAME}->{$record->{NAME}} if defined ($args{NAME});

	return undef if $args{__DELETE};

	# OK, now update the record with our arguments.
	foreach (keys %args) {
	    $record->{$_}=$args{$_};
	}
	
	# And recreate the indices to make sure things are nice and 
	# consistent.
	$self->{HANDLE}{$record->{HANDLE}} = $record
	  if ($record->{HANDLE});
	$self->{NAME}{lc($record->{NAME})} = $record
	  if ($record->{NAME});
	
	# and return a copy of the new record.
	return %{$record};
    }
}


=item get_name()

=cut

sub get_name {
    my ($self,%args) = @_;
    
    my %rec = $self->state(%args);
    
    return $rec{NAME} if ($rec{NAME} =~ /\S/);
    return $args{HANDLE} || "[unknown]";
}


=item get_blurb()

=cut

sub get_blurb {
    my ($self,%args) = @_;
    
    my %rec = $self->state(%args);
    return $rec{BLURB};
}


=item get_title()

=cut

sub get_title {
    my ($self,%args) = @_;
    
    my %rec = $self->state(%args);
    return $rec{TITLE};
}


=item get_pronoun()

=cut

sub get_pronoun {
    my ($self,%args) = @_;
    
    my %rec = $self->state(%args);
    return $rec{PRONOUN} || "their";
}

=item get_user_perms()

=cut

sub get_user_perms {
    my ($serv) = @_;

    my $id = TLily::Event::event_r(type => 'text', order => 'before',
                     call => sub {
                         my($event,$handler) = @_;
                         if ($event->{text} =~ /%user_type ([pah]+)/) {
                             $event->{NOTIFY} = 0;
                             $serv->state(DATA => 1,
                                          NAME => 'perms',
                                          VALUE => $1);
                             TLily::Event::event_u($handler);
                         }
                         return 0;
                     }
             );

    TLily::Event::event_r(type => 'options',
            call => sub {
                my($event,$handler) = @_;
                if (grep(/usertype/, @{$event->{options}})) {
                    $event->{NOTIFY} = 0;
                    TLily::Event::event_u($handler);
                    TLily::Event::event_u($id);
                }
                return 1;
            }
    );

    $serv->sendln("\#\$\# options +usertype");
}

=item set_client_options()

=cut

sub set_client_options {
  my ($serv) = @_;

  $serv->sendln("\#\$\# options +version +prompt +prompt2 +leaf-notify +leaf-cmd +connected");
}


=item set_client_name()

=cut

sub set_client_name {
  my ($serv) = @_;

  $serv->sendln("\#\$\# client TigerLily $TLily::Version::VERSION");
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

    my $server = $this;
    my $call   = $args{call};
    my $type   = defined($args{type}) ? $args{type} : "info";
    my $target = defined($args{target}) ? $args{target} : "me";
    my $name   = $args{name};
    my $ui     = $args{ui};

    my $uiname;
    $uiname    = $ui->name() if ($ui);

    $name =~ s/:/ /g if ($type =~ /help/);
    my @data = ();
    my $sub = sub {
        my($event) = @_;
        $event->{NOTIFY} = 0;
        # If $event->{text} is defined, it's not the end of the cmd yet
        if (defined($event->{text})) {
            if ($type =~ /memo|info/) {
                  push @data, substr($event->{text},2)
                      if ($event->{text} =~ /^\* /);
            } elsif ($type =~ /help/) {
                # Remove the ?sethelp line the server returns
                return if ($event->{text} =~ /^\?sethelp/ && !@data);
                # Remove the terminal "."
                return if ($event->{text} =~ /^\.$/);
                push @data, $event->{text};
            } else {
                push @data, $event->{text};
            }
        } elsif ($event->{type} eq 'endcmd') {
            $call->(server => $event->{server},
                    ui     => TLily::UI::name($uiname),
                    type   => $type,
                    target => $target,
                    name   => $name,
                    text   => \@data);
        }
        return;
    };

    my $servername = $server->{DATA}{NAME};
    if ($type eq "info") {
        $ui->print("(fetching info for $target from server $servername)\n") if ($ui);
        $server->cmd_process("/info $target", $sub);
    } elsif ($type eq "memo") {
        $ui->print("(fetching memo $name on $target from server $servername)\n") if ($ui);
        $server->cmd_process("/memo $target $name", $sub);
    } elsif ($type eq "verb") {
        $ui->print("(fetching verb $target from server $servername)\n") if ($ui);
        $server->cmd_process("\@list $target:$name", $sub);
    } elsif ($type eq "help") {
        $ui->print("(fetching help $target $name from server $servername)\n") if ($ui);
        $server->cmd_process("?gethelp $target \"$name\"", $sub);
    }
    elsif ($type eq "config") {
#        $server->sendln("\#\$\# import_file config $name");

#        push @{$server->{_import_queue}},
#          { uiname => $uiname, call => $call, type => $type, name => $name };
    }

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

    my $server = $this;
    my $text   = $args{text};
    my $type   = defined($args{type}) ? $args{type} : "info";
    my $target = defined($args{target}) ? $args{target} : "me";
    my $name   = $args{name};

    my $uiname;
    $uiname    = $args{ui}->name() if ($args{ui});

    if ($type eq "info") {
        my $size = @$text;
        my $t = $target;  $t = "" if ($target eq "me");
        $server->sendln("\#\$\# export_file info $size $t");

        push @{$server->{_export_queue}},
          { uiname => $uiname, text => $text, type => $type, name => $target };
    }
    elsif ($type eq "memo") {
        my $size = 0;
        foreach (@$text) { $size += length($_); }
        my $t = $target;  $t = "" if ($target eq "me");
        my $lines = @$text;
        $server->sendln("\#\$\# export_file memo $size $lines $name $t");

        push @{$server->{_export_queue}},
          { uiname => $uiname, text => $text, type => $type, name => $target.$name };
    }
    elsif ($type eq "config") {
        my $size = @$text;
        $server->sendln("\#\$\# export_file config $size $name");

        push @{$server->{_export_queue}},
          { uiname => $uiname, text => $text, type => $type, name => $name };
    }
    elsif ($type eq "verb") {
        # If the server detected an error, try to save the verb to a dead file.
        # This can not be done with a cmd_process, unfortunately, because
        # @program is a hard-coded MOO function.  There is no leaf-cmd enabled
        # way of programming verbs at this time.  There is also some wisdom
        # to not relying on command leafing in this instance: if leafing
        # was broken, you wouldn't be able to program verbs!
        TLily::Event::event_r(type => 'text', order => 'after', call => sub {
            my($event,$handler) = @_;
            if ($event->{text} =~ /^Verb (not )?programmed\./) {
                TLily::Event::event_u($handler);

                if ($1) {
                    $args{ui}->print("(Unable to program \"$target:$name\")\n") if ($args{ui});
                    unless (save_deadfile($type, $server, "$target:$name", $text)) {
	                $args{ui}->print("(Unable to save \"$target:$name\"; changes lost)\n") if ($args{ui});
                    }
                }
            }
            return 0;
        });

	$args{ui}->print("(Programming \"$target:$name\"\n") if ($args{ui});
        $server->sendln("\@program $target:$name");
        foreach (@{$text}) { chomp; $server->sendln($_) }
        $server->sendln(".");
    }
    elsif ($type eq "help") {
        my $target = defined($args{target}) ? $args{target} : "lily";
        $name =~ s/:/ /g if ($type =~ /help/);

        if (@$text > 24) {
	    $args{ui}->print("(Help \"$target $name\" is too long (max 24 lines), saving to deadfile)\n") if ($args{ui});
            unless (save_deadfile($type, $server, "$target:$name", $text)) {
	        $args{ui}->print("(Unable to save \"$target $name\"; changes lost)\n") if ($args{ui});
            }
            return;
        }

        my $success = 0;
        my $sub = sub {
            my ($event) = @_;
            # $event->{NOTIFY} = 0;
            if ($event->{'type'} eq 'begincmd') {
                foreach (@$text) { next if /^\.$/; $server->sendln($_); }
                $server->sendln(".") unless (@$text == 24);
                return;
            } elsif ($event->{type} eq 'endcmd' && !$success) {
	        $args{ui}->print("(Store of help \"$target $name\" failed)\n") if ($args{ui});
                unless (save_deadfile($type, $server, "$target:$name", $text)) {
	            $args{ui}->print("(Unable to save \"$target $name\"; changes lost)\n") if ($args{ui});
                }
                return;
            } else {
                $success++ if ($event->{text} =~ /\(help for \"$name\" in index \"$target\" has been (?:changed|added)\)$/);
            }
            return;
        };
        $server->cmd_process("?sethelp $target \"$name\"", $sub);
    }

    return;
}

1;

