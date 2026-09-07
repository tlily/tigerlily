package CJ::command::weather;
use strict;

use JSON;
use URI::Escape;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bweather\s+(.*)\??\s*$/i;

# Weather Underground retired the mobile site this used to scrape; the old URL
# now redirects to a marketing page. Open-Meteo replaces it: no API key, no
# registration, and a documented JSON interface instead of a scrape.
#
# Requests go through $CJ::ua rather than CJ::add_throttled_HTTP because
# These endpoints are HTTPS only. CJ::add_throttled_HTTP goes through
# TLily::Server::HTTP, which issues a hardcoded "GET ... HTTP/1.0" and does not
# follow redirects or decode the response charset. CJ::shorten and the stock
# command already use $CJ::ua for the same reason.

our $geocode_url  = "https://geocoding-api.open-meteo.com/v1/search";
our $forecast_url = "https://api.open-meteo.com/v1/forecast";

# WMO weather codes, which is how Open-Meteo reports conditions.
our %conditions = (
    0  => 'clear',                    1  => 'mainly clear',
    2  => 'partly cloudy',            3  => 'overcast',
    45 => 'fog',                      48 => 'freezing fog',
    51 => 'light drizzle',            53 => 'drizzle',
    55 => 'heavy drizzle',            56 => 'light freezing drizzle',
    57 => 'freezing drizzle',         61 => 'light rain',
    63 => 'rain',                     65 => 'heavy rain',
    66 => 'light freezing rain',      67 => 'freezing rain',
    71 => 'light snow',               73 => 'snow',
    75 => 'heavy snow',               77 => 'snow grains',
    80 => 'light showers',            81 => 'showers',
    82 => 'violent showers',          85 => 'light snow showers',
    86 => 'snow showers',             95 => 'thunderstorms',
    96 => 'thunderstorms with hail',  99 => 'thunderstorms with heavy hail',
);

=head2 geocode($place)

Turn a place name into a hashref of location data. Returns ($location, $error):
at most one is set. A place we simply do not recognise gives (undef, undef) --
that is an answer, not a failure. Anything else gives an error to report, so
that a service that is down or blocked does not masquerade as a typo. Shared
with the forecast command.

=cut

sub geocode {
    my ($place) = @_;

    my $url = $geocode_url . '?name=' . uri_escape($place) . '&count=1';
    my $res = $CJ::ua->get($url);
    return ( undef, 'the geocoder answered ' . $res->status_line )
        unless $res->is_success;

    my $data = eval { decode_json( $res->content ) };
    return ( undef, 'I could not parse what the geocoder sent' ) if $@;
    return ( undef, undef ) unless ( $data->{results} && @{ $data->{results} } );
    return ( $data->{results}[0], undef );
}

=head2 place_name($location)

The human readable name of a geocoded location: "Boston, Massachusetts, US".

=cut

sub place_name {
    my ($loc) = @_;
    return join ', ', grep { defined && length }
        ( $loc->{name}, $loc->{admin1}, $loc->{country_code} );
}

=head2 condition($code)

Describe a WMO weather code.

=cut

sub condition {
    my ($code) = @_;
    return 'unknown' unless defined $code;
    return $conditions{$code} || 'unknown';
}

=head2 not_found($event, $what, $term)

Report an unrecognised place, but only privately: a mistyped word in a
discussion should not produce noise for everyone in it. This is what the
scraping version did when it found nothing.

=cut

sub not_found {
    my ( $event, $what, $term ) = @_;

    return unless ( $event->{type} eq 'private' );
    if ( length($term) > 10 ) {
        $term = substr( $term, 0, 7 ) . '...';
    }
    CJ::dispatch( $event, "Can't find $what for '$term'." );
    return;
}

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $term = $1;

    my ( $loc, $err ) = geocode($term);
    if ($err) {
        CJ::dispatch( $event, "Looking up '$term' failed: $err." );
        return;
    }
    if ( !$loc ) {
        not_found( $event, 'weather', $term );
        return;
    }

    my $url
        = $forecast_url
        . '?latitude='
        . $loc->{latitude}
        . '&longitude='
        . $loc->{longitude}
        . '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
        . '&temperature_unit=fahrenheit&wind_speed_unit=mph';

    my $res = $CJ::ua->get($url);
    if ( !$res->is_success ) {
        CJ::dispatch( $event,
            'The weather service answered ' . $res->status_line . '.' );
        return;
    }

    my $data = eval { decode_json( $res->content ) };
    if ( $@ || !$data->{current} ) {
        CJ::dispatch( $event, "I couldn't make sense of the weather data." );
        return;
    }

    my $now = $data->{current};
    CJ::dispatch(
        $event,
        sprintf(
            '%s: %sF, %s, humidity %s%%, wind %smph',
            place_name($loc),
            $now->{temperature_2m},
            condition( $now->{weather_code} ),
            $now->{relative_humidity_2m},
            $now->{wind_speed_10m}
        )
    );
    return;
}

sub help {
    return "Given a location, get the current weather. Usage: weather <place>";
}

1;
