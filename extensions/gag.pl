# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/gag.pl,v 1.1 1999/03/03 18:34:15 neild Exp $ 

use strict;

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

my %gagged;


sub gag_command_handler {
    my($ui, $args) = @_;
    my $server = TLily::Server::name();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
	if (scalar(keys(%gagged)) == 0) {
	    $ui->print("(no users are being gagged)\n");
	} else {
	    $ui->print("(gagged users: ",
		       join(', ', sort values(%gagged)),
		       ")\n" );
	}
	return;
    }

    if (@args != 1) {
	$ui->print("(%gag name; type %help for help)\n");
	return;
    }

    my $name = TLily::Server::SLCP::expand_name($args[0]);
    if ((!defined $name) || ($name =~ /^-/)) {
	ui_output("(could find no match to \"$args[0]\")");
	return;
    }

    my %state = $server->state(NAME => $name);
    if (!$state{HANDLE}) {
	ui_output("(could find no match to \"$args[0]\")");
	return;
    }

    if (defined $gagged{$state{HANDLE}}) {
	delete $gagged{$state{HANDLE}};
	$ui->print("($name is no longer gagged.)\n");
    } else {
	$gagged{$state{HANDLE}} = $name;
	$ui->print("($name is now gagged.)\n");
    }

    return;
}

sub gagger {
    my($event, $handler) = @_;
    return unless (defined $gagged{$event->{SHANDLE}});
    $event->{VALUE} =~ s/\b\w\b/m/g;
    $event->{VALUE} =~ s/\b\w\w\b/mm/g;
    $event->{VALUE} =~ s/\b\w\w\w\b/mrm/g;
    $event->{VALUE} =~ s/\b(\w+)\w\w\w\b/'m'.('r'x length($1)).'fl'/ge;
    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'before',
	    call  => \&gagger);
    event_r(type  => 'public',
	    order => 'before',
	    call  => \&gagger);

    command_r('gag' => \&gag_command_handler);
    shelp_r('gag' => 'Affix a gag to a user');
    help_r('gag' => "
Usage: %gag [user]

The %gag command replaces the text of all sends from a user with an \
amusing string of mrfls.  Once upon a time, it was possible to retroactively \
ungag someone -- this is no longer supported.
");
} 


1;
