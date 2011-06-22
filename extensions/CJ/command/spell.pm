package CJ::command::spell;
use strict;

use CGI qw/escape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bspell\s+(.*)\s*$/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    my $term = escape $1;
    my $url
        = "http://www.google.com/search?num=0&hl=en&lr=&as_qdr=all&q=$term&btnG=Search";
    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {
            my ($response) = shift;
            my $answer = scrape_google_guess( $term, $response->{_content} );
            if ($answer) {
                CJ::dispatch( $event,
                    "No match for '$term', did you mean '$answer'?" );
            }
            else {
                CJ::dispatch( $event,
                    "Looks OK, but google could be wrong." );
            }
        }
    );
    return;
}

sub help {
    return <<END_HELP;
Have google check your spelling...
Usage: spell <phrase>
END_HELP
}

sub scrape_google_guess {
    my $term    = shift;
    my $content = shift;

    my ( $lookup, @retval );

    $content =~ s/\n/ /g;
    if ( $content =~ m{Did you mean.*<i>([^>]+)</i>} ) {
        return $1;
    }
    return;
}
