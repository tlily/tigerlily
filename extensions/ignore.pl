# -*- Perl -*-
# $Id$

# Semi-ignore: Ignores a user's sends, but notifies you when they
# happen, so multi-person discussions are less confusing.

use strict;
use warnings;

=head1 NAME

ignore.pl - Ignore a user's sends, but still see when/where they send things.

=head1 DESCRIPTION

When loaded, this extension will drop specified users' messages, but
will display a message to you that they happened.  This is the fabled
"client-side ignore".

This extension does not handle private messages at all.  If you wish to
ignore someone privately, use the lily /ignore command.

See %help ignore (below) for additional information.

=head1 CHANGE LOG

10 Jul 2009 - Sue D. Nymme - First version.
22 Jul 2009 - packy        - Convert to using MOO IDs & added state persistence
24 Dec 2009 - Sue D. Nymme - Fix: CJ url shortening to emote discussions was broken.

=cut

my %blanket_ignore;    # user => boolean.  True implies user is blanket-ignored, possibly with exceptions.
my %ignore;            # user => {disc => bool}    True means user is being ignored in that disc.
my %except;            # user => {disc => bool}    True means user is explicitly NOT being ignored in that disc.
my $nl = "\n";
my $status_memo = '*ignoreStatus';
my $CJ = '#2482'; # CJ's object handle

my %fmt_cache = ();

###
### Conditionally display debug messages.
### $DEBUG is hardcoded (no way to change it dynamically).
### dbg($ui, @stuff) is like $ui->print(@stuff), but only if $DEBUG is true.
### dbg_store(@stuff) is for when you don't have a UI (yet).
### dbg_spew($ui) displays the stored-up stuff from dbg_store().
###
my $DEBUG = 0;
sub dbg
{
    return unless $DEBUG;
    my $ui = shift;
    $ui->print('DBG: ', @_, $nl);
}
{
    my @store;
    sub dbg_store { return unless $DEBUG; my @args = @_; push @store, \@args; }
    sub dbg_spew  { my $ui = shift; while (@store) { my $a = shift @store; dbg($ui, @$a); } }
    sub dbg_clear { @store = (); }
}

###
### debug_dump(): Dumps the state of the ignore variables, for debugging.
###
sub debug_dump
{
    my ($ui) = @_;
    dbg_spew($ui);

    $ui->print("debug dump:$nl");

    my @names = get_names(keys %blanket_ignore);
    my $blanket = join ',' => sort @names;
    $ui->print("Blanket ignore: $blanket$nl");

    $ui->print("Explicit ignores:$nl");
    foreach my $user (sort keys %ignore)
    {
        next if scalar keys %{ $ignore{$user} } == 0;
        my @list = get_names(grep $ignore{$user}{$_}, keys %{ $ignore{$user} });
        my $dl = join ',' => sort @list;
        my ($uname) = get_names($user);
        $ui->print("    $uname in $dl$nl");
    }

    $ui->print("Exceptions:$nl");
    foreach my $user (sort keys %except)
    {
        next if scalar keys %{ $except{$user} } == 0;
        my @list = get_names(grep $except{$user}{$_}, keys %{ $except{$user} });
        my $dl = join ',' => sort @list;
        my ($uname) = get_names($user);
        $ui->print("    $uname in $dl$nl");
    }

    $ui->print("Serialized:$nl");
    foreach my $line (serialize_ignore_status()) {
        $ui->print("    $line$nl");
    }
}

###
### Event handler for public and emote events.
###
### This is the routine that checks whether a user's message is to be
### ignored.  If so, it installs a custom formatter (\&ignore_message).
###
sub ignore_event_handler
{
    dbg_store("In event_handler");
    my($event, $handler) = @_;

    # Who's the sender?
    my $sender  = $event->{SOURCE};
    my $shandle = $event->{SHANDLE};

    # What are the recipients?
    my $recip   = $event->{RECIPS};
    my $rhandle = $event->{RHANDLE}; # arrayref
    my @recips = expand_mixed(undef, $recip);

    # Who am I?
    my $self_handle = $event->{server}->user_handle();

    my $type = $event->{type};

    dbg_store("Event ($type) from $sender ($shandle) to $recip (".
        join(",", @$rhandle).")");

    # if this is a send from CJ, check to see if it's a URL shortening.
    # if it is, then make the sender appear to be the user CJ is shortening for
    if ($shandle eq $CJ)
    {
        my $send = $event->{VALUE};
        $send =~ s/\A \s says, \s "//x;   # If emote send, remove leading junk

        if ($send =~ /^(.+)'s \s+ url \s+ is/x)
        {
            my $T_sender = $1;

            # rewrite the lexicals so the ignore logic checks the sender,
            # not CJ
            $sender  = $T_sender;
            $shandle = get_handle($sender);

            # rewrite the event's source so the resulting output has the
            # sender's name, not CJ
            ($event->{ORIG_SOURCE}, $event->{ORIG_SHANDLE}) = ($event->{SOURCE}, $event->{SHANDLE});
            ($event->{SOURCE},      $event->{SHANDLE}     ) = ($sender,          $shandle         );

            # stuff in a special format so you can see a CJ send was ignored
            if ($type eq 'public') {
                $event->{format} = defined $config{ignore_cj_public_fmt}
                    ? $config{ignore_cj_public_fmt}
                    : q{\n%[ -> ]%(Server )%Time CJ shortens a url }.
                      q{for %From in %To, but you don't care%|\n};
            }
            else {
                $event->{format} = defined $config{ignore_cj_emote_fmt}
                    ? $config{ignore_cj_emote_fmt}
                    : q{%[> ]%(Server )(to %To) CJ shortens a url for %From, }.
                      q{but you don't care%|\n};
            }
        }
    }

    # Is the user ignored in every one of those places?
    my $allowed;
    if ($blanket_ignore{$shandle})
    {
        # Exception?
        foreach my $recip (@$rhandle)
        {
            $allowed = 1, next  if $recip eq $self_handle;
            $allowed = 1, next  if exists $except{$shandle} && $except{$shandle}{$recip};
        }
        dbg_store("Sender blanket ignored, but exception found")    if  $allowed;
        dbg_store("Sender blanket ignored, and no exception found") if !$allowed;
    }
    else
    {
        # Allow it, unless sender is ignored in every one of the discs
        my $forbidden = 1;
        foreach my $recip (@$rhandle)
        {
            dbg_store("Checking [$recip] against [$self_handle]");
            $forbidden = 0, next if $recip eq $self_handle;
            $forbidden = 0 if !(exists $ignore{$shandle} && $ignore{$shandle}{$recip});

            dbg_store("exists \$ignore{$shandle}? [", exists($ignore{$shandle}), "]");
            dbg_store("\$ignore{$shandle}{$recip}? [", $ignore{$shandle}{$recip}, "]");
            dbg_store("CLEARING FORBIDDEN FLAG!") if !(exists $ignore{$shandle} && $ignore{$shandle}{$recip});
        }
        $allowed = ! $forbidden;
        dbg_store("Sender ignored all of ($recip)") if !$allowed;
        dbg_store("Send allowed")                   if  $allowed;
    }

    # Suppress message if not allowed.
    if (!$allowed)
    {
        dbg_store("Final verdict: NOT ALLOWED");
        $event->{formatter} = \&generic_fmt;
    }
    else
    {
        # If CJ-send, restore original source
        if ($event->{ORIG_SOURCE})
        {
            ($event->{SOURCE}, $event->{SHANDLE}) = ($event->{ORIG_SOURCE}, $event->{ORIG_SHANDLE});
        }
    }
    return;
}

###
### Formatter for ignored messages.
###
### This is currently the crappiest code in the whole extension.
### This could use some refactoring, man.
###
### Some of this code was copied from slcp_output.pl.  It basically
### tries to mimic normal sends, in a limited way.
###
sub ignore_message
{
    # We should only get here if this message is to be ignored.
    my ($ui, $event) = @_;

    my $type = $event->{type};
    my $serv_fmt = $event->{server_fmt} || "${type}_server";
    my $head_fmt = $event->{header_fmt} || "${type}_header";
    my $send_fmt = $event->{sender_fmt} || "${type}_sender";
    my $dest_fmt = $event->{dest_fmt}   || "${type}_dest";
    my $body_fmt = $event->{body_fmt}   || "${type}_body";

    # Server prefix
    my $server = (scalar(TLily::Server::find()) > 1)? '(' . $event->{server}->name() . ') ' : '';

    $ui->print($nl);
    dbg($ui, "event type is [$type]$nl");
    if ($type eq 'public')
    {
        dbg_store("formatting public message for ".$event->{SOURCE});
        my $ts = $event->{STAMP}? timestamp($event->{TIME}) : '';

        $ui->prints($serv_fmt => $server,
                    $head_fmt => " -> $ts",
                    $send_fmt => $event->{SOURCE},
                    $head_fmt => ' blathers something to ',
                    $dest_fmt => $event->{RECIPS},
                    $head_fmt => ", but you don't care$nl",
                   );
    }

    elsif ($type eq 'emote')
    {
        dbg_store("formatting emote message for ".$event->{SOURCE});
        my $ts = ($event->{STAMP} || $config{stampemotes})? etimestamp($event->{TIME}) : '';

        $ui->prints($serv_fmt => $server,
                    $body_fmt => "(${ts}to ",
                    $dest_fmt => $event->{RECIPS},
                    $body_fmt => ") ",
                    $send_fmt => $event->{SOURCE},
                    $body_fmt => " blathers something, but you don't care",
                   );
    }
}

###
### compile_fmt and generic_fmt are both cribbed from cformat.pl
###
sub compile_fmt {
    my($fmt) = @_;

    my $code = "sub {\n";
    $code .= '  my($ui, $vars, $fmts) = @_;' . "\n";
    $code .= '  my $default = $fmts->{header};' . "\n";

    pos($fmt) = 0;
    while ( pos($fmt) < length($fmt) ) {
        if ( $fmt =~ /\G \\n/xgc ) {
            $code .= '  $ui->print("\n");' . "\n";
        }

        elsif ( $fmt =~ /\G \\(.?)/xgc ) {
            my $arg = $1;
            $arg =~ s/([\'\\])/\\$1/g;
            $code .= '  $ui->prints($default => \'' . $arg . "\');\n"
              if defined($1);
        }

        elsif ($fmt =~ /\G %(\() ([^\)]*) \)/xgc
            || $fmt =~ /\G %(\{) ([^\}]*) \}/xgc
            || $fmt =~ /\G %() (\w+)/xgc )
        {
            my $type = $1;
            my $var  = $2;
            my $prefix;
            my $suffix;

            ( $prefix, $var, $suffix ) = $var =~ /^(\W*)(.*?)(\W*)$/;
            if ( $type eq '(' ) {
                $prefix .= "(";
                $suffix = ")" . $suffix;
            }

            $var = lc($var);
            $prefix =~ s/([\'\\])/\\$1/g;
            $suffix =~ s/([\'\\])/\\$1/g;

            $code .= '  $ui->prints($default => \'' . $prefix . "\',\n";
            $code .=
                '              $fmts->{'
              . $var
              . '} || $default => $vars->{'
              . $var . "},\n";
            $code .= '              $default => \'' . $suffix . "\')\n";
            $code .= '    if defined($vars->{' . $var . "});\n";
        }

        elsif ( $fmt =~ /\G %\| /xgc ) {
            $code .= '  $default = $fmts->{body};' . "\n";
        }

        elsif ( $fmt =~ /\G %\[ ([^\]]*) \]/xgc ) {
            my $arg = $1;
            $arg =~ s/([\'\\])/\\$1/g;
            $code .= '  $ui->indent($default => \'' . $arg . "\');\n";
        }

        elsif ( $fmt =~ /\G ([^%\\]+)/xgc ) {
            my $arg = $1;
            $arg =~ s/([\'\\])/\\$1/g;
            $code .= '  $ui->prints($default => \'' . $arg . "\');\n";
        }
    }

    $code .= '  $ui->indent();' . "\n";
    $code .= "}\n";
    dbg_store($code);

    return $code;
}

sub generic_fmt {
    my($ui, $e) = @_;

    my %vars;
    my %fmts;
    my $fmt;

    if (defined $e->{format}) {
	$fmt = $e->{format};
    }
    elsif ($e->{type} eq 'public') {
	$fmt = defined $config{ignore_public_fmt}
             ? $config{ignore_public_fmt}
	     : q{\n%[ -> ]%(Server )%Time%From blathers something to %To, }.
	       q{but you don't care%|\n};
    }
    elsif ($e->{type} eq 'emote') {
	$fmt = defined $config{ignore_emote_fmt}
             ? $config{ignore_emote_fmt}
	     : q{%[> ]%(Server )(to %To) %From blathers something, }.
	       q{but you don't care%|\n};
    }

    $fmts{server} = $e->{server_fmt} || "$e->{type}_server";
    $fmts{header} = $e->{header_fmt} || "$e->{type}_header";
    $fmts{from}   = $e->{sender_fmt} || "$e->{type}_sender";
    $fmts{to}     = $e->{dest_fmt}   || "$e->{type}_dest";
    $fmts{body}   = $e->{body_fmt}   || "$e->{type}_body";

    $vars{server} = $e->{server}->name()
        if (scalar(TLily::Server::find()) > 1);
    $vars{time} = timestamp($e->{TIME})
        if ($e->{STAMP});
    $vars{from} = $e->{SOURCE};
    $vars{blurb} = $e->{server}->get_blurb(HANDLE => $e->{SHANDLE});
    if (defined $vars{blurb} && $vars{blurb} ne "") {
	$vars{blurb} = "[" . $vars{blurb} . "]";
    }
    else {
	undef $vars{blurb};
    }
    $vars{to} = $e->{RECIPS};
    $vars{body} = $e->{VALUE};

    if (!$fmt_cache{$fmt}) {
	$fmt_cache{$fmt} = eval compile_fmt($fmt);
    }
    $fmt_cache{$fmt}->($ui, \%vars, \%fmts);

    return;
}

###
### The %ignore command handler.  Defers to both_command_handler.
###
sub ignore_command_handler
{
    both_command_handler('ignore', @_);
}
###
### The %unignore command handler.  Defers to both_command_handler.
###
sub unignore_command_handler
{
    both_command_handler('unignore', @_);
}

###
### Command handler for %ignore and %unignore.  Pretty simple.
###
sub both_command_handler
{
    my ($which, $ui, $args) = @_;
    my $do_user             = $which eq 'ignore'? \&ignore_user             : \&unignore_user;
    my $do_user_in_disc     = $which eq 'ignore'? \&ignore_user_in_disc     : \&unignore_user_in_disc;
    my $do_user_except_disc = $which eq 'ignore'? \&ignore_user_except_disc : \&unignore_user_except_disc;

    my $server = active_server() or return;
    my @args = split /\s+/, $args;

    # No arguments; just display current ignore status.
    if (@args == 0)
    {
        display_ignore_status($ui);
        return;
    }

    # One argument: either a special keyword (--dump, clear), or a
    # list of users.
    if (@args == 1)
    {
        if (lc $args[0] eq '--dump')
        {
            debug_dump($ui);
            return;
        }

        if (lc $args[0] eq '--debug')
        {
            $DEBUG = 1;
            $ui->print(q{Debug more on.}, $nl);
            return;
        }

        if (lc $args[0] eq '--nodebug')
        {
            $DEBUG = 0;
            $ui->print(q{Debug more off.}, $nl);
            return;
        }

        if (lc $args[0] eq 'clear')
        {
            ignore_clear($ui);
            store_status($ui);
            return;
        }

        $do_user->($ui, $args[0]);
        store_status($ui);
        return;
    }

    # Two arguments: Should be a list of users and a list of discussions.
    if (@args == 2)
    {
        $do_user_in_disc->($ui, $args[0], $args[1]);
        store_status($ui);
    }

    # Three arguments: Should be a list of users, "except", and a list
    # of discussions.
    if (@args == 3)
    {
        my $exc = $args[1];
        if (lc $exc ne "except"  &&  lc $exc ne "ex")
        {
            $ui->print(q{Can't figure out what you mean. See %help ignore'}, $nl);
            return;
        }
        $do_user_except_disc->($ui, $args[0], $args[2]);
        store_status($ui);
    }

    if (@args > 3)
    {
        $ui->print('Too many arguments. See %help ignore', $nl);
        return;
    }
}

###
### store the commands necessary to restore the current status in a memo
###
sub store_status
{
    my $ui = shift;
    my $server = TLily::Server::active();

    my @commands = serialize_ignore_status();

    $server->store(type   => "memo",
		   target => "me",
		   name   => $status_memo,
		   text   => \@commands);
}

###
### read commands from a memo
###
sub restore_status
{
    my $ui = shift;
    my $server = TLily::Server::active();

    my $restore = sub {
        my(%args) = @_;
        foreach my $line (@{ $args{text} }) {
            my @args = split /\s+/, $line;

            my $cmd = shift @args; # get rid of the %ignore
            unless ($cmd eq '%ignore') {
                $ui->print(q{Only %ignore commands are allows in ignoreStatus'}, $nl);
                return;
            }

            if (@args == 1) {
                ignore_user($ui, $args[0]);
            }
            elsif (@args == 2) {
                ignore_user_in_disc($ui, $args[0], $args[1]);
            }
            elsif (@args == 3) {
                my $exc = $args[1];
                if (lc $exc ne "except"  &&  lc $exc ne "ex")
                {
                    $ui->print(q{Can't figure out what you mean. See %help ignore'}, $nl);
                    return;
                }
                ignore_user_except_disc($ui, $args[0], $args[2]);
            }
        }
    };

    $server->fetch(ui     => $ui,
                   type   => "memo",
		   target => "me",
		   name   => $status_memo,
		   call   => $restore);
}

###
### Display the users who are being ignored, and where, in a nice
### readable way.
###
sub display_ignore_status
{
    my $ui = shift;
    my $count = 0;

    # Blanket ignores with no exceptions
    my @everywhere;
    foreach my $user (sort keys %blanket_ignore)
    {
        next unless $blanket_ignore{$user};
        push @everywhere, get_names($user)
            unless exists $except{$user} && scalar keys %{$except{$user}} > 0;
    }

    # Per-discussion ignores
    my %per_disc;
    foreach my $user (sort keys %ignore)
    {
        next if $blanket_ignore{$user};
        my $disc_ref = $ignore{$user};
        next unless scalar keys %$disc_ref > 0;
        my @discs = get_names(grep { $disc_ref->{$_} } keys %$disc_ref);
        my $disc_list = join ',' => sort @discs;
        push @{ $per_disc{$disc_list} }, get_names($user);
    }

    # Per-discussion exceptions
    my %disc_exc;
    foreach my $user (sort keys %except)
    {
        next unless $blanket_ignore{$user};
        my $disc_ref = $except{$user};
        next unless scalar keys %$disc_ref > 0;
        my @discs = get_names(grep { $disc_ref->{$_} } keys %$disc_ref);
        my $disc_list = join ',' => sort @discs;
        push @{ $disc_exc{$disc_list} }, get_names($user);
    }

    ## Output section:

    # Those who are ignored everywhere
    if (@everywhere)
    {
        ++$count;
        my $everywhere = join ',' => @everywhere;
        $ui->print("You are ignoring $everywhere everywhere$nl");
    }

    # Those who are ignored everywhere except certain places
    foreach my $disc_list (sort keys %disc_exc)
    {
        my $users = join ',' => @{ $disc_exc{$disc_list} };
        $ui->print("You are ignoring $users everywhere except $disc_list$nl");
        ++$count;
    }

    # Those who are ignored only in certain places.
    foreach my $disc_list (sort keys %per_disc)
    {
        my $users = join ',' => @{ $per_disc{$disc_list} };
        $ui->print("You are ignoring $users in $disc_list$nl");
        ++$count;
    }

    # Didn't hit any of the above?
    if ($count == 0)
    {
        $ui->print("Not ignoring anyone$nl");
    }
}

###
### Dump the users who are being ignored, and where, in a machine
### readable way.
###
sub serialize_ignore_status
{
    my $count = 0;

    # Blanket ignores with no exceptions
    my @everywhere;
    foreach my $user (sort keys %blanket_ignore)
    {
        next unless $blanket_ignore{$user};
        push @everywhere, $user
            unless exists $except{$user} && scalar keys %{$except{$user}} > 0;
    }

    # Per-discussion ignores
    my %per_disc;
    foreach my $user (sort keys %ignore)
    {
        next if $blanket_ignore{$user};
        my $disc_ref = $ignore{$user};
        next unless scalar keys %$disc_ref > 0;
        my @discs = grep { $disc_ref->{$_} } keys %$disc_ref;
        my $disc_list = join ',' => sort @discs;
        push @{ $per_disc{$disc_list} }, $user;
    }

    # Per-discussion exceptions
    my %disc_exc;
    foreach my $user (sort keys %except)
    {
        next unless $blanket_ignore{$user};
        my $disc_ref = $except{$user};
        next unless scalar keys %$disc_ref > 0;
        my @discs = grep { $disc_ref->{$_} } keys %$disc_ref;
        my $disc_list = join ',' => sort @discs;
        push @{ $disc_exc{$disc_list} }, $user;
    }

    ## Output section:
    my @commands;

    # Those who are ignored everywhere
    if (@everywhere)
    {
        my $everywhere = join ',' => @everywhere;
        push @commands, "%ignore $everywhere";
    }

    # Those who are ignored everywhere except certain places
    foreach my $disc_list (sort keys %disc_exc)
    {
        my $users = join ',' => @{ $disc_exc{$disc_list} };
        push @commands, "%ignore $users except $disc_list";
    }

    # Those who are ignored only in certain places.
    foreach my $disc_list (sort keys %per_disc)
    {
        my $users = join ',' => @{ $per_disc{$disc_list} };
        push @commands, "%ignore $users $disc_list";
    }

    return @commands;
}

###
### Clear all ignore settings.
###
sub ignore_clear
{
    my ($ui) = @_;
    %blanket_ignore = ();
    %ignore = ();
    %except = ();
    dbg_clear();
    $ui->print("All ignore settings cleared.$nl");
}

###
### Expand a list of users.  Defers to expand_things()
###
sub expand_users
{
    my ($ui, $userlist) = @_;
    return expand_things($ui, $userlist, 'user');
}

###
### Expand a list of discussions.  Defers to expand_things()
###
sub expand_discs
{
    my ($ui, $disclist) = @_;
    return expand_things($ui, $disclist, 'discussion');
}

###
### Expand a possibly-mixed list of users and discussions
###
sub expand_mixed
{
    my ($ui, $list) = @_;
    return expand_things($ui, $list, 'mixed');
}

###
### Expand a list of users or discussions.
### Takes a comma-separated list of things,
### Returns an array of those things, expanded appropriately.
###
sub expand_things
{
    my ($ui, $list, $what) = @_;
    my $finding_users = lc $what eq 'user';       # Users?  or discussions?
    my $finding_discs = lc $what eq 'discussion';
    my $finding_both  = lc $what eq 'mixed';
    $what = $finding_users? 'user' : 'discussion';

    # "Thing" here means "user or discussion"
    my @things = split /,/ => $list;
    my @expanded;

    local $config{expand_group} = 1;
    RawThing: foreach my $t (@things)
    {
        # Expand the thing
        if (substr($t,0,1) eq q{#}) {
            ($t) = get_names($t);
        }
        my ($et) = TLily::Server::SLCP::expand_name($t);
        if (!defined $et)
        {
            defined($ui) && $ui->print(qq{Cannot find match for "$t"$nl});
            next RawThing;
        }

        # expand_name can return a comma-separated list (when expanding a group)
        foreach my $indiv (split /,/ => $et)
        {
            if ( ($finding_users && substr($indiv,0,1) eq '-')
              || ($finding_discs && substr($indiv,0,1) ne '-'))
            {
                defined($ui) && $ui->print(qq{Cannot find $what named "$indiv"$nl});
                next RawThing;
            }
            push @expanded, $et;
        }
    }

    return @expanded;
}

sub get_handle
{
    my($thing) = @_;

    # if we're passed a handle, just hand it back
    return $thing if substr($thing, 0, 1) eq q{#};

    # remove the leading dash, if present
    substr($thing, 0, 1, q{}) if (substr($thing, 0, 1) eq q{-});

    my $server = TLily::Server::active();
    my @state  = TLily::Server::SLCP::state($server, NAME => $thing);
    unless (defined $state[0])
    {
        use Carp;
        carp qq{WTF! get_handle on "$thing" returned undef};
        return {};
    }
    my %state  = @state;

    return $state{HANDLE};
}

sub get_names
{
    my(@handles) = @_;
    my @names;

    my $server = TLily::Server::active();

    foreach my $handle (@handles) {
        my %state = TLily::Server::SLCP::state($server, HANDLE => $handle);
        push @names, exists $state{TITLE} ? q{-}.$state{NAME} : $state{NAME};
    }

    return @names;
}


###
### Ignore a user (or list of users), everywhere.
###
sub ignore_user
{
    my ($ui, $user) = @_;
    my @users = expand_users($ui, $user);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);
        dbg($ui, "blanket ignoring $u");
        $blanket_ignore{$uh} = 1;
        dbg($ui, "Removing individual ignores for $u");
        delete $ignore{$uh};
        dbg($ui, "Removing exceptions for $u");
        delete $except{$uh};
        $ui->print("You are now ignoring $u (globally)$nl");
    }
}

###
### Ignore a user (or users) in a discussion (or discussions).
###
sub ignore_user_in_disc
{
    my ($ui, $user, $disc) = @_;
    my @users = expand_users($ui, $user);
    my @discs = expand_discs($ui, $disc);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);
        foreach my $d (@discs)
        {
            my $dh = get_handle($d);
            if (!$blanket_ignore{$uh})
            {
                # Explicitly ignore if not blanket-ignored
                dbg($ui, "Explicitly ignoring $u in $d");
                $ignore{$uh}{$dh} = 1;
            }
            else
            {
                dbg($ui, "$u is blanket ignored, so no worries.");
            }

            # Delete ignore exception, if any
            dbg($ui, "Removing exception for $u in $d");
            delete $except{$uh}{$dh};
        }
    }

    my $U = join ',' => @users;
    my $D = join ',' => @discs;
    $ui->print("You are now ignoring $U in $D$nl");
}

###
### Ignore a user (or users) everywhere EXCEPT in a specified
### discussion (or discussions).
###
sub ignore_user_except_disc
{
    my ($ui, $user, $disc) = @_;
    my @users = expand_users($ui, $user);
    my @discs = expand_discs($ui, $disc);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);

        # Remove specific ignores
        dbg($ui, "Removing individual ignores for $u");
        delete $ignore{$uh};

        # Blanket ignore this user
        dbg($ui, "Blanket ignoring $u");
        $blanket_ignore{$uh} = 1;

        # Add exception
        foreach my $d (@discs)
        {
            my $dh = get_handle($d);
            dbg($ui, "Adding exception for $u in $d");
            $except{$uh}{$dh} = 1;
        }
    }

    my $U = join ',' => @users;
    my $D = join ',' => @discs;
    $ui->print("You are now ignoring $U everywhere except $D$nl");
}

###
### Unignore a user (or users), everywhere.
###
sub unignore_user
{
    my ($ui, $user) = @_;
    my @users = expand_users($ui, $user);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);
        dbg($ui, "Removing blanket-ignore for $u");
        delete $blanket_ignore{$uh};
        dbg($ui, "Removing specific ignores for $u");
        delete $ignore{$uh};
        dbg($ui, "Removing exceptions for $u");
        delete $except{$uh};
        $ui->print("You are not ignoring $u (globally)$nl");
    }
}

###
### Unignore a user (or users) in a specific discussion (or
### discussions).
###
sub unignore_user_in_disc
{
    my ($ui, $user, $disc) = @_;
    my @users = expand_users($ui, $user);
    my @discs = expand_discs($ui, $disc);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);
        foreach my $d (@discs)
        {
            my $dh = get_handle($d);
            if ($blanket_ignore{$uh})
            {
                dbg($ui, "Adding exception for $u in $d");
                $except{$uh}{$dh} = 1;
            }
            else
            {
                dbg($ui, "$u is blanket ignored, so no worries");
            }

            dbg($ui, "Removing explicit ignore for $u in $d");
            delete $ignore{$uh}{$dh};
        }
    }

    my $U = join ',' => @users;
    my $D = join ',' => @discs;
    $ui->print("You are now not ignoring $U in $D$nl");
}

###
### Unignore a user (or users) everywhere EXCEPT a specified
### discussion (or discussions).
###
sub unignore_user_except_disc
{
    my ($ui, $user, $disc) = @_;
    my @users = expand_users($ui, $user);
    my @discs = expand_discs($ui, $disc);

    foreach my $u (@users)
    {
        my $uh = get_handle($u);

        # Remove specific exceptions
        dbg($ui, "Removing exceptions for $u");
        delete $except{$uh};

        # Blanket unignore this user
        dbg($ui, "Removing blanket ignore for $u");
        delete $blanket_ignore{$uh};

        # Add exception
        foreach my $d (@discs)
        {
            my $dh = get_handle($d);
            dbg($ui, "Explicitly ignoring $u in $d");
            $ignore{$uh}{$dh} = 1;
        }
    }

    my $U = join ',' => @users;
    my $D = join ',' => @discs;
    $ui->print("You are now ignoring $U everywhere except $D$nl");
}


###
### Extension loader.  Just registers handlers and sets up help.
###
sub load
{
    my $ui = TLily::UI::name();
    restore_status($ui);

    event_r(type  => 'public',
            call  => \&ignore_event_handler,
            order => 'before');

    event_r(type  => 'emote',
            call  => \&ignore_event_handler,
            order => 'before');

    command_r('ignore'   => \&ignore_command_handler);
    command_r('unignore' => \&unignore_command_handler);

    shelp_r('ignore'   => 'Ignore a user, but still see when they post.');
    shelp_r('unignore' => 'Unignore a user previously ignored with %ignore.');

    help_r('ignore' => <<'END_HELP');
Usage: %ignore user[,user...]
       %ignore user[,user...] disc[,disc...]
       %ignore user[,user...] except disc[,disc...]
       %ignore
       %ignore clear

The lily /ignore command suppresses all notification of a user's
sends.  This is great for shutting up annoying people, but it does
tend to make things confusing when other users start replying to posts
you cannot see in public discussions.

%ignore will display a brief one-line notification when any ignored
user posts a message, but you don't see their message.

%ignore with no parameters will report which users you are ignoring,
and where.

%ignore with a list of users will ignore those users everywhere
(except private messages.  %ignore does not handle private messages).

%ignore with a list of users and discussions will ignore those users
but only in those discussions.  The word "private" can be used as a
pseudo discussion name to indicate private messages.

%ignore with the "except" keyword will ignore users everywhere
*except* the listed discussions.

%ignore clear will stop ignoring all users.

See also: %unignore

END_HELP

    help_r('unignore' => <<'END_HELP');
Usage: %unignore user[,user...]
       %unignore user[,user...] disc[,disc...]
       %unignore user[,user...] except disc[,disc...]

%unignore will stop %ignore'ing a user or users, or will provide
exceptions to a user's %ignore status.

%unignore with a list of users will stop ignoring those users' posts.

%unignore with a list of users and discussions will stop ignoring
those users but only in those discussions.

%unignore with the "except" keyword will ignore a user (or users)
*only* in the specified discussions.  This is essentially the same as
"%ignore [users] [discs]", except that it first clears the users'
ignore state.

END_HELP

}

###
### The following two were copied from slcp_output.pl.  -- SDN 7/10/2009
###
sub etimestamp
{
    my ($time) = @_;

    my @a = localtime($time);
    my $str = TLily::Utils::format_time(\@a, delta => "zonedelta",
					type => "zonetype",
                                        seconds => "stampseconds");
    return sprintf("%s, ", $str);
}

sub timestamp
{
    my ($time) = @_;

    my @a = localtime($time);
    my $str = TLily::Utils::format_time(\@a, delta => "zonedelta",
					type => "zonetype",
                                        seconds => "stampseconds");
    return sprintf("(%s) ", $str);
}
