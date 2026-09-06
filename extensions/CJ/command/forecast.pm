package CJ::command::forecast;
use strict;

use JSON;

# weather.pm's geocoding and WMO code table are shared rather than duplicated.
# They cannot be pulled in with "use": cj.pl loads command modules with do()
# from a directory that does not match their package names, so they are not in
# @INC. Every module is loaded into the one process before any send is
# dispatched, so the subs are there by the time response() runs.

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bforecast\s+(.*)\??\s*$/i;

# See the comment in weather.pm: Weather Underground retired the page this used
# to scrape, and Open-Meteo replaces it. Geocoding and the WMO code table are
# shared with that command rather than duplicated.

our $days = 5;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $term = $1;

    my $loc = CJ::command::weather::geocode($term);
    if ( !$loc ) {
        CJ::command::weather::not_found( $event, 'forecast', $term );
        return;
    }

    my $url
        = $CJ::command::weather::forecast_url
        . '?latitude='
        . $loc->{latitude}
        . '&longitude='
        . $loc->{longitude}
        . '&daily=weather_code,temperature_2m_max,temperature_2m_min'
        . '&forecast_days='
        . $days
        . '&temperature_unit=fahrenheit';

    my $res = $CJ::ua->get($url);
    if ( !$res->is_success ) {
        CJ::dispatch( $event, 'The weather service is not answering.' );
        return;
    }

    my $data = eval { decode_json( $res->content ) };
    if ( $@ || !$data->{daily} ) {
        CJ::dispatch( $event, "I couldn't make sense of the forecast data." );
        return;
    }

    my $daily = $data->{daily};
    my @lines = ( 'Forecast for ' . CJ::command::weather::place_name($loc) . ':' );

    for my $i ( 0 .. $#{ $daily->{time} } ) {
        push @lines,
            sprintf(
            '%s: %s, %s-%sF',
            $daily->{time}[$i],
            CJ::command::weather::condition( $daily->{weather_code}[$i] ),
            $daily->{temperature_2m_min}[$i],
            $daily->{temperature_2m_max}[$i]
            );
    }

    # Padded so each day starts on its own line, as the scraped version was.
    CJ::dispatch( $event, CJ::wrap(@lines) );
    return;
}

sub help {
    return "Given a location, get the weather forecast. Usage: forecast <place>";
}

1;
