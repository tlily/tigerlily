package CJ::command::morse;
use strict;

use Convert::Morse qw(is_morse as_ascii as_morse);

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bmorse\s+(.*)/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    my $text = $1;

    if (is_morse($text)) {
        return as_ascii($text);
    } else {
        return as_morse($text);
    } 
}

sub help {
    return "Usage: morse <val>; I'll (de)convert the text you give me.";
}

1;
