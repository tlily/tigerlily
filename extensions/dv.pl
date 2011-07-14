use strict;

#
# The dv extension adds the ability to disemvowel all sends from a given user.
#

=head1 NAME

dv.pl - Disemvowel sends from given user

=head1 DESCRIPTION

This extension contains the %dv command, which disemvowels sends from a given user.

=head1 COMMANDS

=over 10

=cut

my %dved;
my %dvtopics;

# Hacked from gag.pl by Mike Jones (mike.jones@ilk.org)
#

=item %dv

Disemvowels a user.  See "%help dv" for details.

=cut

sub dv_command_handler {
    my($ui, $args) = @_;
    my $server = active_server();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
        if (scalar(keys(%dved)) == 0) {
            $ui->print("(no users are being disemvoweled)\n");
        } else {
            $ui->print("(disemvoweled users: ",
                       join(', ', sort values(%dved)),
                       ")\n" );
        }
        if (scalar(keys(%dvtopics)) == 0) {
            $ui->print("(no topics are being disemvoweled)\n");
        } else {
            $ui->print("(disemvoweled topics: ",
                       join(', ', sort values(%dvtopics)), ")\n" );
        }
        return;
    }

    if (@args > 2 and @args[0] ne 'topic') {
        $ui->print("(%dv <name> or %dv topic <topic>; type %help for help)\n");
        return;
    }

    # Disemvowel topics.
    if (@args == 2) {
        my $topic = $args[1];
        if (defined($dvtopics{$topic})) {
            delete $dvtopics{$topic};
            $ui->print("(Topic $topic is no longer disemvoweled.)\n");
        } else {
            $dvtopics{$topic} = $topic;
            $ui->print("(Topic $topic is now disemvoweled.)\n");
        }
        return;
    }

    my $tmp = $config{expand_group};

    $config{expand_group} = 1;
    my $name = TLily::Server::SLCP::expand_name($args[0]);
    if ((!defined $name) || ($name =~ /^-/)) {
        $ui->print("(could find no match to \"$args[0]\")\n");
        return;
    }
    $config{expand_group} = $tmp;
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

        if (defined $dved{$state{HANDLE}}) {
            delete $dved{$state{HANDLE}};
            $ui->print("($nm is no longer disemvoweled.)\n");
        } else {
            $dved{$state{HANDLE}} = $nm;
            $ui->print("($nm is now disemvoweled.)\n");
        }
    }
    return;
}

sub dver {
    my($event, $handler) = @_;
    my $dvthis = 0;
    for my $key (keys %dvtopics) {
        $dvthis = 1 if ($event->{VALUE} =~ /\b$key\b/i);
    }
    $dvthis = 1 if defined $dved{$event->{SHANDLE}};
    return unless ($dvthis);
     $event->{VALUE} =~ s/[aeiou]//gi;
    return;
}

sub load {
    event_r(type  => 'private',
            order => 'before',
            call  => \&dver);
    event_r(type  => 'public',
            order => 'before',
            call  => \&dver);
    event_r(type  => 'emote',
            order => 'before',
            call  => \&dver);

    command_r('dv' => \&dv_command_handler);
    shelp_r('dv' => 'Disemvowel a user');
    help_r('dv' => "
Usage: %dv [user]
       %dv topic [topic]

The %dv command disemvowels the text of all sends from a user, \
or all sends that match a given topic.\
");
}


1;

