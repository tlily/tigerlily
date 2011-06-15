package CJ::command::rot13;
use strict;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\brot13\b/i;

sub response {
    my ($event) = @_;
    my $args = $event->{VALUE};
    if ( !( $args =~ s/.*rot13\s+(.*)/$1/i ) ) {
        return 'ERROR: Expected rot13 RE not matched!';
    }

    $args =~ tr/[A-Za-z]/[N-ZA-Mn-za-m]/;

    return $args;
}

sub help { return "Usage: rot13 <val>" }

1;
