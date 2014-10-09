package CJ::command::shorten;
use strict;

our $TYPE     = "all";
our $POSITION = 1;
our $LAST     = 1;
our $RE       = qr/\bshorten\b\s*(.*)\s*$/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $url = $1;

    if ($url eq "") {
        CJ::dispatch( $event, "Shorten what?" ); 
    } else {
        CJ::shorten( $url, sub { CJ::dispatch( $event, shift ) } );
    }
    return;
}

sub help {
    return
        "Given a URL, return a shortened version of the url. Usage: shorten <url>";
}

1;
