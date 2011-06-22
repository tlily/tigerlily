package CJ::command::urldecode;
use strict;

use CGI qw/unescape/;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\burldecode\s+(.*)/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    return unescape $1;
}

sub help {
    return "Usage: urldecode <val>";
}

1;
