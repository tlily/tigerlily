package CJ::command::compute;
use strict;

use CGI qw/escape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bcompute\s+(.*)$/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    my $args    = $1;
    my $verbose = 0;
    if ( $args =~ s/^-v\s+// ) {
        $verbose = 1;
    }

    my $url
        = "http://api.wolframalpha.com/v2/query?appid="
        . $CJ::config->val( 'wolfram', 'appID' )
        . "&format=plaintext&input="
        . escape($args);

    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {
            my ($response) = @_;
            CJ::dispatch( $event,
                scrape_wolfram( $response->{_content}, $verbose ) );
        }
    );
    return;
}

sub help {
    return <<END_HELP
Compute something using WolframAlpha.com; If you pass the -v option, I'll
include a LOT of output from the site, otherwise just the first few lines.
Usage: compute [-v] <stuff>
END_HELP
}

sub scrape_wolfram {
    my $content = shift;
    my $verbose = shift;

    my $footer = " [wolframalpha.com]";

    if ( $content =~ m/success='false'/ ) {
        return "I didn't understand that, sorry. $footer";
    }

    my $results = "";

    my $maxLines = 2;
    if ($verbose) {
        $maxLines = 20;
    }

    my $line = 0;
    while (
        $content =~ m/<pod title='(.*?)'.*?<plaintext>(.*?)<\/plaintext>/sig
        && $line < $maxLines )
    {
        my $section   = $1;
        my $plaintext = $2;
        $plaintext =~ s/\n/ /g;
        $results .= "$section: $plaintext\n";
        $line++;
    }

    $results .= $footer;
    return CJ::wrap( split( /\n/, $results ) );
}

1;
