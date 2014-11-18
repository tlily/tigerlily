package CJ::command::hug;
use strict;

our $TYPE     = "emote";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bhug\s+(.+)/i;

sub response {
    my ($event) = @_;

    if ($event->{VALUE} =~ $RE) {
        CJ::dispatch( $event, "hugs $1", 1 );
    }
}

sub help { return "Usage: hug <someone>" }

1;
