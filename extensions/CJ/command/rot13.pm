package CJ::command::rot13;
use strict;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\brot13\s+(.*)/i;

sub response {
    my ($event) = @_;

    $event->{VALUE} =~ $RE;
    my $args = $1;
    $args =~ tr/[A-Za-z]/[N-ZA-Mn-za-m]/;

    return $args;
}

sub help { return "Usage: rot13 <val>" }

1;
