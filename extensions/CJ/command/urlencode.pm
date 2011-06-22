package CJ::command::urlencode;
use strict;

use CGI qw/escape/;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\burlencode\s+(.*)/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    return escape $1;
}

sub help {
    return "Usage: urlencode <val>";
}

1;
