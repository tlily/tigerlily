# -*- Perl -*-
# $Id$

use strict;
use warnings;

use TLily::UI;
use TLily::Server::SLCP;

=head1 NAME

expand.pl - Provides send expansion and other utilities

=head1 DESCRIPTION

This extension provides expansion of sendgroups, users, and discussions.

=head1 COMMANDS

=over 10

=item %oops

=item %also

=cut

my %expansions = ('sendgroup' => '',
                  'sender'    => '',
                  'recips'    => '');

my @past_sends = ();

my $last_send;

sub mserv_expand_name {
    my($name) = @_;

    my $active  = TLily::Server::active();
    my @servers = ($active, grep($_ != $active, TLily::Server::find()));
    my @exps;

    # Look for an exact match somewhere.
    @exps = map { my @e = $_->expand_name($name, exact => 1);
          @e ? [ $_, @e ] : () } @servers;
    if (@exps) {
        if (@exps > 1 || $exps[0]->[0] != $active ||
        $config{always_add_server}) {
            $exps[0]->[1] =~ s/(?=,|$)/'@'.$exps[0]->[0]->name()/eg;
        }
        return $exps[0]->[1];
    }

    # Look for partial matches.
    @exps = map { my @e = $_->expand_name($name);
          @e ? [ $_, @e ] : () } @servers;

    return unless @exps; # Nothing matches anywhere.
    return if (@exps > 1 && $exps[0]->[0] != $active); # Too much confusion.
    return if (@{$exps[0]} > 2); # Too many matches on this server.

    if (@exps > 1 || $exps[0]->[0] != $active || $config{always_add_server}) {
        $exps[0]->[1] =~ s/(?=,|$)/'@'.$exps[0]->[0]->name()/eg;
    }
    return $exps[0]->[1];
}

sub exp_expand {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;

    goto end if (!TLily::Server::active());
    
    if ($pos == 0) {
        my $exp;
        if ($key eq '=') {
            $exp = $expansions{'sendgroup'};
            goto end unless ($exp);
            $key = ';';
        } elsif ($key eq ':') {
            $exp = $expansions{'sender'};
        } elsif ($key eq ';') {
            $exp = $expansions{'recips'};
        } else {
            goto end;
        }

        my $serv = active_server();
        my $serv_name = $serv->name();
        $exp =~ s/\@\Q$serv_name\E(?=$|,)//g;
        
        $exp =~ tr/ /_/;
        $ui->set_input(length($exp) + 1, $exp . $key . $line);
        return;
    } elsif (($key eq ':') || ($key eq ';') || ($key eq ',')) {
        my $fore = substr($line, 0, $pos);
        my $aft  = substr($line, $pos);
    
        goto end if ($fore =~ /[:;\/]/);
        goto end if ($fore =~ /^\s*[\/\$\?%]/);
    
        my @dests = split(/,/, $fore);
        foreach (@dests) {
            my $full = mserv_expand_name($_);
            next unless ($full);
            $_ = $full;
            $_ =~ tr/ /_/;
        }
    
        $fore = join(',', @dests);
        $ui->set_input(length($fore) + 1, $fore . $key . $aft);
        return;
    }
    
  end:
    $ui->command("insert-self", $key);
    return;
}


sub exp_complete {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    
    my $serv = active_server();
    my $serv_name = $serv->name();

    my $partial = substr($line, 0, $pos);
    my $full;

    if ($pos == 0) {
        return unless @past_sends;
        $full = $past_sends[0] . ';';
        $full =~ s/\@\Q$serv_name\E(?=[;:,])//g;
    } elsif ($partial !~ /[\[\]\;\:\=\"\?\s]/) {
        my($fore, $aft) = ($partial =~ m/^(.*,)?(.*)/);
        $aft = mserv_expand_name($aft);
        return unless $aft;
        $full = $fore if (defined($fore));
        $full .= $aft;
        $full =~ tr/ /_/;
    } elsif (substr($partial, 0, -1) !~ /[\[\]\;\:\=\"\?\s]/) {
        chop $partial;
        return unless (@past_sends);
        $full = $past_sends[0];
        for (my $i = 0; $i < @past_sends; $i++) {
            my $past = $past_sends[$i];
            $past =~ s/\@\Q$serv_name\E(?=$|[;:,])//g;
            if ($past_sends[$i] eq $partial || $past eq $partial) {
                $full = $past_sends[($i+1)%@past_sends];
                last;
            }
        }
        $full .= ';';
        $full =~ s/\@\Q$serv_name\E(?=[;:,])//g;
    } else {
        # Is this a command expansion?
        # XXX: Only supports limited commands
        # XXX: doesn't distinguish between users/discussions
        if ($line =~ m{^/(who|ignore|unignore|finger|also|oops|join|quit|where|what|block|destroy)\s+(\w+)}i && length($line) == $pos) {
          my ($command,$partial) = ($1,$2);
          my $expanded = mserv_expand_name($partial);
          if ($expanded) {
              $expanded =~ s/ /_/g;
              $full = "/$command $expanded";
          }
        }
    } 
    if ($full) {
        substr($line, 0, $pos) = $full;
        $pos = length($full);
        $ui->set_input($pos, $line);
    }
    
    return;
}


TLily::UI::command_r("intelligent-expand" => \&exp_expand);
TLily::UI::command_r("complete-send"      => \&exp_complete);
TLily::UI::bind(','   => "intelligent-expand");
TLily::UI::bind(':'   => "intelligent-expand");
TLily::UI::bind(';'   => "intelligent-expand");
TLily::UI::bind('='   => "intelligent-expand");
TLily::UI::bind('C-i' => "complete-send");

sub private_handler {
    my($event,$handler) = @_;

    my $me = $event->{server}->user_name();
    return unless (defined $me);
    
    my $serv_name = $event->{server}->name();
  
    # recalc from SHANDLE, since some extensions may muck with the SOURCE 
    my $sender = $event->{server}->{HANDLE}->{$event->{SHANDLE}}->{NAME} .
        "@" . $serv_name;

    if ($event->{SOURCE} ne $me) {
        $expansions{sender} = $sender;

        @past_sends = grep { $_ ne $sender } @past_sends;
        unshift @past_sends, $sender;
        pop @past_sends if (@past_sends > ($config{tab_ring_size}||5));
    }
    
    my @group = split /, /, $event->{RECIPS};
    if (@group > 1) {
        push @group, $event->{SOURCE};
        @group = grep { $_ ne $me } @group;
        $expansions{sendgroup} = join(",", map($_."@".$serv_name, @group));
    }
    
    return;
}
event_r(type => 'private',
    call => \&private_handler);

sub user_send_handler {
    my($event, $handler) = @_;
    my $serv_name = $event->{server}->name();
    my $dlist =
        join(",", map(/@/ ? $_ : ($_."@".$serv_name), @{$event->{RECIPS}}));
    
    $expansions{recips} = $dlist;
    $last_send = $event->{text};
    
    @past_sends = grep { $_ ne $dlist } @past_sends;
    unshift @past_sends, $dlist;
    pop @past_sends if (@past_sends > ($config{tab_ring_size}||5));

    return;
}
event_r(type => 'user_send',
    call => \&user_send_handler);

sub rename_handler {
    my ($event, $handler) = @_;

    foreach my $k (keys %expansions) {
        $expansions{$k} =~ s/\Q$event->{SOURCE}\E/$event->{VALUE}/;
    }
    return 0;
}

event_r(type => 'rename',
    call => \&rename_handler);

sub server_change_handler {
    my($event, $handler) = @_;
    my $ui = $event->{ui} || ui_name();

    my($pos, $line) = $ui->get_input;
    my $sname = $event->{old_server}->name();
    my $newsname = $event->{server}->name();
    my $nline = "";

    return if ($line eq "");

    while ($line =~ /\G([^,:;=\/%]*)([,:;=])/g) {
    my($tgt, $sym) = ($1, $2);

    if ($tgt !~ /@/) {
        $pos += 1+length($sname) if (pos($line) <= $pos);
        $nline .= $tgt . "@" . $sname . $sym;
    } elsif ($tgt =~ /^([^@]*)@\Q$newsname\E/i &&
         !$config{always_add_server}) {
        $nline .= $1 . $sym;

        if ($pos > length($nline)) {
            $pos -= length($newsname) + 1;
            if ($pos < length($nline)) {
                $pos = length($nline)-1;
            }
        }
    } else {
        $nline .= $tgt . $sym;
    }

    last if ($sym ne ',');
    }

    $nline .= substr($line, pos($line));
    $ui->set_input($pos, $nline);
    $ui->print("");
    return;
}
event_r(type => 'server_change',
    call => \&server_change_handler);

sub oops_cmd {
    my ($ui, $args) = @_;
    my $serv = active_server();
    my $serv_name = $serv->name();

    my (@dests) = split (/,/, $args);
    foreach (@dests) {
        my $full = TLily::Server::SLCP::expand_name($_);
        next unless $full;
        $full =~ tr/ /_/;
        $_ = $full . "@" . $serv_name;
    }
    
    $expansions{recips} = join(",", @dests);

    if ($config{emote_oops}) {
        if (!defined $last_send) {
            $ui->print ("(but you haven't said anything)");
            return;
        }

        foreach my $d (split /,/, $past_sends[0]) {
            $d = TLily::Server::SLCP::expand_name($d);
            next unless ($d =~ s/^-//);
            my %st;
            %st = $serv->state(NAME => $d) or next;
            if ($st{ATTRIB} =~ /emote/) {
                $serv->sendln($past_sends[0] . ";" . $config{emote_oops});
                $serv->sendln($args . ";" . $last_send);
                return;
            }
            last;
        }
    }

    $serv->sendln ("/oops " . $args);
    return;
}

sub also_cmd {
    my ($ui, $args) = @_;
    my $serv = active_server();
    my $serv_name = $serv->name();

    my (@dests) = split (/,/, $args);
    foreach (@dests) {
        my $full = TLily::Server::SLCP::expand_name($_);
        $full =~ tr/ /_/;
        $_ = $full . "@" . $serv_name;
    }
    $expansions{recips} = join (",", $expansions{recips}, @dests);
    $serv->sendln("/also " . $args);
    return;
}

command_r('oops' => \&oops_cmd);
command_r('also' => \&also_cmd);

shelp_r('oops' => "/oops with fixed sendlist");
help_r ('oops' => "
Usage: %oops user
       /oops user

/oops does not fix your sendlist correctly.  This command will \
send your /oops, as well as update your sendlist so ';' \
will expand to the new user.

In addition, if the \$emote_oops config variable is set, \
then %oops will use that string as your oops message, if \
it would be sent to an emote discussion.

If 'oops' is in your \@slash config variable, then /oops will have \
the same effect.

(see also /oops, %also)
");

shelp_r('also' => "/also with fixed sendlist");
help_r ('also' => "
Usage: %also user
       /also user

/also does not fix your sendlist correctly.  This command will \
send your /also, as well as add user to your sendlist so ';' \
will expand to both users.

If 'also' is in your \@slash config variable, then /also will have \
the same effect.

(see also /also, %oops)
");

shelp_r('always_add_server' =>
    'Always append the server name to destinations.',
    'variables');

shelp_r('tab_ring_size' =>
        'Number of destinations to keep in tab ring',
        'variables');
