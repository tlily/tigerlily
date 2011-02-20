# -*- Perl -*-

use strict;

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

=head1 NAME

gag.pl - Gag sends from given user

=head1 DESCRIPTION

This extension contains the %gag command, which replaces the text of sends
from a given user with onomatopoeic mrffls.

=head1 COMMANDS

=over 10

=cut

my %gagged;
my %gagtopics;

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

=item %gag

Gags a user.  See "%help gag" for details.

=cut

sub gag_command_handler {
    my($ui, $args) = @_;
    my $server = active_server();
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
        if (scalar(keys(%gagtopics)) == 0) {
            $ui->print("(no topics are being gagged)\n");
        } else {
            $ui->print("(gagged topics: ",
                       join(', ', sort values(%gagtopics)), ")\n" );
        }
        return;
    }

    if (@args > 2 and @args[0] ne 'topic') {
        $ui->print("(%gag <name> or %gag topic <topic>; type %help for help)\n");
        return;
    }

    # Gag topics.
    if (@args == 2) {
        my $topic = $args[1];
        if (defined($gagtopics{$topic})) {
            delete $gagtopics{$topic};
            $ui->print("(Topic $topic is no longer gagged.)\n");
        } else {
            $gagtopics{$topic} = $topic;
            $ui->print("(Topic $topic is now gagged.)\n");
        }
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
        # The call above to expand_name has preprended a ~
        $nm =~ s/^~//;

        my %state = $server->state(NAME => $nm);

        if (!$state{HANDLE}) {
            if ($nm !~ /^#/) {
                # squawk only if $nm isn't an object id.
                $ui->print("(could find no match to \"$nm\")\n");
            }
            next;
        }

        if (defined $gagged{$state{HANDLE}}) {
            delete $gagged{$state{HANDLE}};
            $ui->print("($nm is no longer gagged.)\n");
        } else {
            $gagged{$state{HANDLE}} = $nm;
            $ui->print("($nm is now gagged.)\n");
        }
    }
    return;
}

sub gagger {
    my($event, $handler) = @_;
    my $gagthis = 0;
    for my $key (keys %gagtopics) {
        $gagthis = 1 if ($event->{VALUE} =~ /\b$key\b/i);
    }
    $gagthis = 1 if defined $gagged{$event->{SHANDLE}};
    return unless ($gagthis);
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
    event_r(type  => 'emote',
            order => 'before',
            call  => \&gagger);

    command_r('gag' => \&gag_command_handler);
    shelp_r('gag' => 'Affix a gag to a user');
    help_r('gag' => "
Usage: %gag [user]
       %gag topic [topic]

The %gag command replaces the text of all sends from a user, or all sends \
that match a given topic, with an amusing string of mrfls.  Once upon a \
time, it was possible to retroactively ungag someone -- this is no longer \
supported.
");
}


1;

