# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/gag.pl,v 1.3 1999/10/02 02:45:17 mjr Exp $ 

use strict;

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

my %gagged;

# Original by Nathan Torkington, massaged by Jeffrey Friedl
# Taken from perl FAQ by Brad Jones (brad@kazrak.com)
#
sub preserve_case($$) {
    my ($old, $new) = @_;
    my ($state) = 0; # 0 = no change; 1 = lc; 2 = uc
    my ($i, $oldlen, $newlen, $c) = (0, length($old), length($new));
    my ($len) = $oldlen < $newlen ? $oldlen : $newlen;

    for ($i = 0; $i < $len; $i++) {
        if ($c = substr($old, $i, 1), $c =~ /[\W\d_]/) {
            $state = 0;
        } elsif (lc $c eq $c) {
            substr($new, $i, 1) = lc(substr($new, $i, 1));
            $state = 1;
        } else {
            substr($new, $i, 1) = uc(substr($new, $i, 1));
            $state = 2;
        }
    }
    # finish up with any remaining new (for when new is longer than old)
    if ($newlen > $oldlen) {
        if ($state == 1) {
            substr($new, $oldlen) = lc(substr($new, $oldlen));
        } elsif ($state == 2) {
            substr($new, $oldlen) = uc(substr($new, $oldlen));
        }
    }
    return $new;
}

sub gag_command_handler {
    my($ui, $args) = @_;
    my $server = TLily::Server::active();
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
    $event->{VALUE} =~ s/\b(\w)\b/preserve_case($1, "m")/ge;
    $event->{VALUE} =~ s/\b(\w\w)\b/preserve_case($1, "mm")/ge;
    $event->{VALUE} =~ s/\b(\w\w\w)\b/preserve_case($1, "mrm")/ge;
    $event->{VALUE} =~
        s/\b((\w+)\w\w\w)\b/preserve_case($1, 'm'.('r'x length($2)).'fl')/ge;
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

