# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/expand.pl,v 1.1 1999/02/24 08:24:53 neild Exp $ 

use strict;

use LC::UI;
use LC::Server;
use LC::Global qw($event);


my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

my @past_sends = ();

my $last_send;

my $server;
$event->event_r(type => "server_connected",
		call => sub { $server = $_[0]->{server}; return });

sub exp_set {
	my($a,$b) = @_;
	$expansions{$a} = $b;
}


sub exp_expand {
	my($ui, $command, $key) = @_;
	my($pos, $line) = $ui->get_input;

	if ($pos == 0) {
		my $exp;
		if ($key eq '=') {
			$exp = $expansions{'sendgroup'};
			return unless ($exp);
			$key = ';';
		} elsif ($key eq ':') {
			$exp = $expansions{'sender'};
		} elsif ($key eq ';') {
			$exp = $expansions{'recips'};
		} else {
			return;
		}

		$exp =~ tr/ /_/;
		$ui->set_input(length($exp) + 1, $exp . $key . $line);
	} elsif (($key eq ':') || ($key eq ';') || ($key eq ',')) {
		my $fore = substr($line, 0, $pos);
		my $aft  = substr($line, $pos);
		
		return if ($fore =~ /[:;]/);
		return if ($fore =~ /^\s*[\/\$\?%]/);
		
		my @dests = split(/,/, $fore);
		foreach (@dests) {
			my $full = $server->expand_name($_);
			next unless ($full);
			$_ = $full;
			$_ =~ tr/ /_/;
		}
		
		$fore = join(',', @dests);
		$ui->set_input(length($fore) + 1, $fore . $key . $aft);
	}
	
	return;
}


sub exp_complete {
	my($ui, $command, $key) = @_;
	my($pos, $line) = $ui->get_input;

	my $partial = substr($line, 0, $pos);
	my $full;

	if (length($partial) == 0) {
		$full = $past_sends[0] . ';';
	} elsif ($partial !~ /[\@\[\]\;\:\=\"\?\s]/) {
		$partial =~ m/^(.*,)?(.*)/;
		$full = $1 . $server->expand_name($2);
		$full =~ tr/ /_/;
	} elsif (substr($partial, 0, -1) !~ /[\@\[\]\;\:\=\"\?\s]/) {
		chop $partial;
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
		$pos += length($full) - length($partial);
		$ui->set_input($pos, $line);
	}

	return;
}


my $ui = LC::UI::name("main");

$ui->command_r("expand"   => \&exp_expand);
$ui->command_r("complete" => \&exp_complete);
$ui->bind(','   => "expand");
$ui->bind(':'   => "expand");
$ui->bind(';'   => "expand");
$ui->bind('='   => "expand");
$ui->bind('C-I' => "complete");

__END__

register_eventhandler(Type => 'usend',
		      Call => sub {
			  my($event,$handler) = @_;
			  my $dlist = join(',', @{$event->{To}});
			  @past_sends = grep { $_ ne $dlist } @past_sends;
			  unshift @past_sends, $dlist;
			  pop @past_sends if (@past_sends > 5);
			  exp_set('recips', $dlist);
			  $last_send = $event->{Body};
			  return 0;
		      });

register_eventhandler(Type => 'send',
		      Call => sub {
			  my($event,$handler) = @_;
#			  return 0 unless ($event->{First});
			  return 0 unless ($event->{Form} eq 'private');
			  exp_set('sender', $event->{From});
			  my $me = $::servers[0]->user_name();
			  my @group = @{$event->{To}};
			  if (@group > 1) {
			      push @group, $event->{From};
			      @group = grep { $_ ne $me } @group;
			      exp_set('sendgroup', join(',',@group));
			  }
			  return 0;
		      });
