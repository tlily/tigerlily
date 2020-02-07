package CJ::command::weather;
use strict;

use CGI qw/escape unescape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bweather\s+(.*)\??\s*$/i;

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
            my $conditions = _scrape_weather( $term, $response->{_content} );
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
                    CJ::dispatch( $event, "Can't find weather for '$term'." );
                }
            }
        }
    );
    return;
}

sub help {
    return "Given a location, get the current weather.";
}

sub _scrape_weather {
    my ( $term, $content ) = @_;

    $content =~ m/(Updated:.*)Current Radar/s;
    my @results = map { CJ::cleanHTML($_) } split( /<tr>/, $1 );
    return CJ::wrap(@results);
}

1;
