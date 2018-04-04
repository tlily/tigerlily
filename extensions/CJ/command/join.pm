package CJ::command::join;
use strict;

our $TYPE     = "private";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\b(join|quit|leave)\s+(.+)/i;

sub response {
    my ($event) = @_;

    $event->{VALUE} =~ $RE;
    my $cmd  = lc $1;
    my $disc = $2;

    if ( $cmd eq "leave" ) {
        $cmd = "quit";
    }

    CJ::asModerator(
        $event, $disc,
        sub {
            TLily::Server->active()->cmd_process("/$cmd $disc");
        }
    );
}

sub help {
    return <<END_HELP;
As a moderator or owner of a discussion, you can have me join or quit a discussion.
Usage: (join|quit|leave) <disc>
END_HELP
}
1;
