package CJ::command::forecast;
use strict;

use CGI qw/escape unescape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bforecast\s+(.*)\??\s*$/i;

our $base_url
    = "http://mobile.wunderground.com/cgi-bin/findweather/getForecast?brand=mobile&query=";

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $term = escape $1;

    CJ::add_throttled_HTTP(
        url      => $base_url . $term,
        ui_name  => 'main',
        callback => sub {
            my ($response) = @_;
            my $conditions = _scrape_forecast( $term, $response->{_content} );
            if ($conditions) {
                CJ::dispatch( $event, $conditions );
            }
            else {
                $term = unescape($term);
                if ( length($term) > 10 ) {
                    $term = substr( $term, 0, 7 );
                    $term .= '...';
                }
                if ( $event->{type} eq 'private' ) {
                    CJ::dispatch( $event,
                        "Can't find forecast for '$term'." );
                }
            }
        }
    );
    return;
}

sub help {
    return "Given a location, get the weather forecast.";
}

sub _scrape_forecast {
    my ( $term, $content ) = @_;

    $content =~ m/(Forecast as of .*)Units:/s;
    my @results = map { CJ::cleanHTML($_), q{} } split( /<b>/, $1 );
    pop @results;                # remove trailing empty line.
    @results
        = @results[ 0 .. 10 ];   # limit responses. 5 days, 1 header, 5 blanks
    return CJ::wrap(@results);
}

1;
