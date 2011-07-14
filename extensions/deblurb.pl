use strict;

#
# The deblurb extension adds the ability to remove a given user's blurb
# from your sight.
#

=head1 NAME

deblurb.pl - Remove another user's blurbs from your sight.

=head1 DESCRIPTION

This extension contains the %deblurb command, which allows you to make another
user appear (to you) not to have a blurb at all.  This will also mask BLURB
SLCP messages from that user.

=head1 COMMANDS

=over 10

=cut

my %deblurbed;

=item %deblurb

Deblurbs a user.  See "%help deblurb" for details.

=cut

sub deblurb_command_handler {
    my($ui, $args) = @_;
    my $server = active_server();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
        if (scalar(keys(%deblurbed)) == 0) {
            $ui->print("(no users are being deblurbed)\n");
        } else {
            $ui->print("(deblurbed users: ",
                join(', ', sort values(%deblurbed)),
                ")\n" );
        }
        return;
    }

    if (@args > 2) {
        $ui->print("(%deblurb <name> ; type %help for help)\n");
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

        if (defined $deblurbed{$state{HANDLE}}) {
            delete $deblurbed{$state{HANDLE}};
            $server->state(HANDLE => $state{HANDLE},
                           OLDBLURB => undef,
                           BLURB => $state{OLDBLURB},
                           UPDATED => 1);
            $ui->print("($nm is no longer deblurbed.)\n");
        } else {
            $deblurbed{$state{HANDLE}} = $nm ;
            $server->state(HANDLE => $state{HANDLE},
                           OLDBLURB => $state{BLURB},
                           BLURB => '',
                           UPDATED => 1);
            $ui->print("($nm is now deblurbed.)\n");
        }
    }
    return;
}

sub deblurbifier {
    my($event, $handler) = @_;
    my $deblurbthis = 0;
    $deblurbthis = 1 if defined $deblurbed{$event->{SHANDLE}};
    return unless ($deblurbthis);
    return unless ($event->{EVENT} =~ /blurb/i);
    delete $event->{NOTIFY} if ($event->{NOTIFY});
    $event->{server}->state(HANDLE => $event->{SHANDLE},
                            OLDBLURB => $event->{VALUE},
                            BLURB => '',
                            UPDATED => 1);
    $event->{VALUE} = undef;
    return;
}

sub load {
    event_r(type  => 'blurb',
            order => 'before',
            call  => \&deblurbifier);

    command_r('deblurb' => \&deblurb_command_handler);
    shelp_r('deblurb' => 'Remove a user\'s blurb from your sight');
    help_r('deblurb' => "
Usage: %deblurb [user]

The %deblurb command allows you to remove all notice of a user's blurb from \
your sight; it removes the user's blurb from all public and private sends \
and SLCP events. \
");
}


1;

