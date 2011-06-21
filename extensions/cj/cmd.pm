package CJ::command::cmd;
use strict;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bcmd\s+(.*)$/i;

#our $PRIVELEGE = "admin";

sub asAdmin {
    my ( $event, $sub ) = @_;
    my $server = TLily::Server::active();

    my $isAdmin = grep { $event->{SHANDLE} eq $_ }
        split( /,/, $server->{NAME}->{'admins'}->{'MEMBERS'} );

    if ($isAdmin) {
        $sub->();
    }
    else {
        CJ::dispatch( $event, "I'm a frayed knot." );
    }
}

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $cmd = $1;

    asAdmin(
        $event,
        sub {
            my @response;
            TLily::Server->active()->cmd_process(
                $cmd,
                sub {
                    my ($newevent) = @_;
                    $newevent->{NOTIFY} = 0;
                    return if ( $newevent->{type} eq 'begincmd' );
                    if ( $newevent->{type} eq 'endcmd' ) {
                        CJ::dispatch( $event, CJ::wrap(@response) );
                    }
                    if ( $newevent->{text} ne q{} ) {
                        push @response, $newevent->{text};
                    }
                }
            );
        }
    );
}

sub help {
    return <<'END_HELP',
If you're a cj admin, use this command to boss me around.
Usage: cmd <lily command>
END_HELP
}

1;
