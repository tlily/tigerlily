# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/autoreply.pl,v 1.3 2000/09/09 06:07:26 mjr Exp $ 

use strict;

=head1 NAME

autoreply.pl - Auto-reply to private messages

=head1 DESCRIPTION

This extension contains the %autoreply command, which allows you to set up
an automatic response to all private messages sent to you.

=head1 COMMANDS

=over 10

=item %autoreply [<message> | <piped command> | off]
 
  Sets the autoreplay message, piped command (e.g., fortune), or turns
off autoreply.  See "%help %autoreply" for more details.

=cut

my $autoreply_help = "
Usage: %autoreply I'm not here right now, call me at my office, x7777.
       %autoreply |/usr/games/fortune -o
       %autoreply off
       %autoreply

Sends an automated reply when private messages are received.
";

# Not currently implemented.
my $autoreply_status='';

my $reply = "";
my %last_reply;
my $send_count = 0;

sub autoreply_event {
    my($event,$handler) = @_;

    my $ui = ui_name("main");

    return if ($event->{VALUE} =~ /^\[automated reply\]/);

    my $from=$event->{SOURCE};
    $from=~s/\s/_/g;
    if ($reply) {
        if (!$last_reply{$from} || (time()-$last_reply{$from} > 30)) {
	    $last_reply{$from}=time();
	    my $r;
	    if ($reply =~ /[\|\!](.*)/) {
		$r=`$1`;
		$r=~s/[\n\r\s]/ /g;
	    } else {
		$r=$reply;
            }
	    $ui->print("(sending automated reply to $from: \"$r\")\n");
	    $send_count++;
	    $ui->set(autoreply => "(autoreply $send_count)");
	    $event->{server}->sendln("$from:[automated reply] $r");
        } else {
	    $last_reply{$from}=time();
	}
    }

    return 0;
}
event_r(type => 'private',
	call => \&autoreply_event);

sub autoreply_cmd {
    my($ui, $args) = @_;
    if ($args eq "") {
	if ($reply) {
	    $ui->print("(current automated reply is \"$reply\")\n");
	} else {
	    $ui->print("(automated reply currently disabled)\n");
	}
    } elsif ($args eq "off") {
	$reply="";
	$ui->print("(disabling automated reply to private messages)\n");
	$send_count=0;
	$ui->set(autoreply => undef);
    } else {
	$send_count=0;
	$reply=$args;
	$ui->print("(will send automated reply to private messages)\n");
	$ui->set(autoreply => "(autoreply $send_count)");
    }
}
command_r(autoreply => \&autoreply_cmd);
shelp_r(autoreply => "send a canned reply to private sends");
help_r('autoreply', $autoreply_help);


sub unload {
    my $ui = ui_name("main");
    $ui->set(autoreply => undef);
}

sub load {
    my $ui = ui_name("main");
    $ui->define(autoreply => 'right');
    return;
}

1;
