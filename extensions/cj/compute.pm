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

    my $args = $1;

    my $url
        = "http://api.wolframalpha.com/v2/query?appid="
        . $CJ::config->val( 'wolfram', 'appID' )
        . "&format=plaintext&input="
        . escape($1);

    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {
            my ($response) = @_;
            CJ::dispatch( $event, scrape_wolfram( $response->{_content} ) );
        }
    );
    return;
}

sub help {
    return <<END_HELP
Compute something using WolframAlpha.com
Usage: compute <stuff>
END_HELP
}

sub scrape_wolfram {
    my ($content) = shift;

    my $footer = " [wolframalpha.com]";

    if ( $content =~ m/success='false'/ ) {
        return "I didn't understand that, sorry. $footer";
    }

    my $results = "";

    while (
        $content =~ m/<pod title='(.*?)'.*?<plaintext>(.*?)<\/plaintext>/sig )
    {
        my $section   = $1;
        my $plaintext = $2;
        $plaintext =~ s/\n/ /g;
        $results .= "$section: $plaintext\n";
    }

    $results .= $footer;
    return CJ::wrap( split( /\n/, $results ) );
}

1;
