# -*- Perl -*-
# $Header: /data/cvs/lily/tigerlily2/extensions/gag.pl,v 1.12 2003/05/10 21:52:20 coke Exp $ 

use strict;

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

=head1 NAME

profane.pl - Replace sends with profanity

=head1 DESCRIPTION

This extension contains the %profane command, which replaces the text of
sends from a given user with pure profanity.

=head1 COMMANDS

=over 10

=cut

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

my @rotcurselist = (
    undef,
    undef,
    undef,
    [ 'nff', 'tnl', 'phz' ],
    [ 'shpx', 'fuvg', 'phag', 'qnza', 'uryy', 'qvpx', 'gjng' ],
    [ 'fuvgr', 'chffl', 'ovgpu', 'juber', 'cevpx' ],
    [ 'shpxre', 'phzont', 'phzjnq' ],
    [ 'nffubyr', 'onfgneq', 'qvpxjnq', 'qvcfuvg', 'wnpxnff', 'nffjvcr' ],
    [ 'shpxgneq', 'fuvgurnq' ],
    [ 'sheshpxre', 'phzohooyr' ],
    [ 'cevpxovgre', 'ehzczbatre', 'ohggcvengr', 'pbpxfhpxre' ],
    [ 'cvyybjovgre', 'ohggzhapure', 'hapyrshpxre' ],
    [ 'zbgureshpxre' ] );

my @curselist;
for my $rotcurse (@rotcurselist) {
    if (defined($rotcurse)) {
	push @curselist, [ map { (tr/A-Za-z/N-ZA-Mn-za-m/, $_)[1] } @$rotcurse ];
    } else {
	push @curselist, undef;
    }
}

sub cursify {
    my ($input) = @_;

    if (length($input) < @curselist) {
        my $curses = $curselist[length($input)];
        return $input if (!defined($curses));
        my $pick = int rand (@$curses);
        return preserve_case($input, $curses->[$pick]);
    } else {
        return "[CENSORED]";
    }
}

my %profaned;

=item %profane

Filters a user's sends to add profanity.  See "%help profane" for details.

=cut

sub profane_command_handler {
    my($ui, $args) = @_;
    my $server = active_server();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
	if (scalar(keys(%profaned)) == 0) {
	    $ui->print("(no users are being profaned)\n");
	} else {
	    $ui->print("(profaned users: ",
		       join(', ', sort values(%profaned)),
		       ")\n" );
	}
	return;
    }

    if (@args > 2) {
	$ui->print("(%profane <name>>; type %help for help)\n");
	return;
    }

    my $tmp = $config{expand_group};

    $config{expand_group} =1;
    my $name = TLily::Server::SLCP::expand_name($args[0]);
    if ((!defined $name) || ($name =~ /^-/)) {
	$ui->print("(could find no match to \"$args[0]\")\n");
	return;
    }
    $config{expand_group} =$tmp;
    my @names;
    if (! (@names = split(/,/,$name))) {
      $names[0] = $name;
    }

    foreach my $nm (@names) {
        my %state = $server->state(NAME => $nm);
        if (!$state{HANDLE}) {
            if ($nm !~ /^#/) {
                # squawk only if $nm isn't an object id.
	        $ui->print("(could find no match to \"$nm\")\n");
            }
	    next;
        }

        if (defined $profaned{$state{HANDLE}}) {
	    delete $profaned{$state{HANDLE}};
	    $ui->print("($nm is no longer profaned.)\n");
        } else {
	    $profaned{$state{HANDLE}} = $nm;
	    $ui->print("($nm is now profaned.)\n");
        }
    }
    return;
}

sub profanizer {
    my($event, $handler) = @_;
    return unless (defined $profaned{$event->{SHANDLE}});
    $event->{VALUE} =~ s/\b(\w+)\b/cursify($1)/ge;
    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'before',
	    call  => \&profanizer);
    event_r(type  => 'public',
	    order => 'before',
	    call  => \&profanizer);
    event_r(type  => 'emote',
	    order => 'before',
	    call  => \&profanizer);

    command_r('profane' => \&profane_command_handler);
    shelp_r('profane' => 'Replace sends with profanity');
    help_r('profane' => "
Usage: %profane [user]

The %profane command replaces the text of all sends from a user with a \
stream of profanity. \
");
} 


1;

