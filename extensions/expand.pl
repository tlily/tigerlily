# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/expand.pl,v 1.14 1999/03/31 03:47:38 mjr Exp $ 

use strict;

use TLily::UI;
use TLily::Server::SLCP;


my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

my @past_sends = ();

my $last_send;

sub exp_expand {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    
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
	
	$exp =~ tr/ /_/;
	$ui->set_input(length($exp) + 1, $exp . $key . $line);
	return;
    } elsif (($key eq ':') || ($key eq ';') || ($key eq ',')) {
	my $fore = substr($line, 0, $pos);
	my $aft  = substr($line, $pos);
	
	goto end if ($fore =~ /[:;]/);
	goto end if ($fore =~ /^\s*[\/\$\?%]/);
	
	my @dests = split(/,/, $fore);
	foreach (@dests) {
	    my $full = TLily::Server::SLCP::expand_name($_);
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
    
    my $partial = substr($line, 0, $pos);
    my $full;
    
    if ($pos == 0) {
	return unless @past_sends;
	$full = $past_sends[0] . ';';
    } elsif ($partial !~ /[\@\[\]\;\:\=\"\?\s]/) {
	my($fore, $aft) = ($partial =~ m/^(.*,)?(.*)/);
	$aft = TLily::Server::SLCP::expand_name($aft);
	return unless $aft;
	$full = $fore if (defined($fore));
	$full .= $aft;
	$full =~ tr/ /_/;
    } elsif (substr($partial, 0, -1) !~ /[\@\[\]\;\:\=\"\?\s]/) {
	chop $partial;
	return unless (@past_sends);
	$full = $past_sends[0];
	for (my $i = 0; $i < @past_sends; $i++) {
	    if ($past_sends[$i] eq $partial) {
		$full = $past_sends[($i+1)%@past_sends];
		last;
	    }
	}
	$full .= ';';
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
    $expansions{sender} = $event->{SOURCE};
    
    my $me = $event->{server}->user_name();
    return unless (defined $me);
    
    my @group = split /, /, $event->{RECIPS};
    if (@group > 1) {
	push @group, $event->{SOURCE};
	@group = grep { $_ ne $me } @group;
	$expansions{sendgroup} = join(",", @group);
    }
    
    return;
}
event_r(type => 'private',
		      call => \&private_handler);

sub user_send_handler {
    my($event, $handler) = @_;
    my $dlist = join(",", @{$event->{RECIPS}});
    
    $expansions{recips} = $dlist;
	$last_send = $event->{text};
    
    @past_sends = grep { $_ ne $dlist } @past_sends;
    unshift @past_sends, $dlist;
    pop @past_sends if (@past_sends > 5);

	return;
}
event_r(type => 'user_send',
		      call => \&user_send_handler);

sub rename_handler {
	my ($event, $handler) = @_;

	foreach my $k (keys %expansions) {
		$expansions{$k} =~ s/\Q$event->{SOURCE}\E/$event->{VALUE}/;
	}
	return;
}

event_r(type => 'rename',
		call => \&rename_handler);

sub oops_cmd {
	my ($ui, $args) = @_;
	my $serv = TLily::Server::name();

	my (@dests) = split (/,/, $args);
	foreach (@dests) {
		my $full = TLily::Server::SLCP::expand_name($_);
		next unless $full;
		$full =~ tr/ /_/;
		$_ = $full;
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
	my $serv = TLily::Server::name();

	my (@dests) = split (/,/, $args);
	foreach (@dests) {
		my $full = TLily::Server::SLCP::expand_name($_);
		$full =~ tr/ /_/;
		$_ = $full;
	}
	$expansions{recips} = join (",", $expansions{recips}, @dests);
	$serv->sendln("/also " . $args);
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



