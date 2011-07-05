package CJ::command::translate;
use strict;

use CGI qw/escape/;
use JSON;

use Text::Unidecode;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;

our $RE = qr/
  (?:
  \b translate \s+ (.*) \s+ from      \s+ (.*) \s+ (?:in)?to \s+ (.*) |
  \b translate \s+ (.*) \s+ (?:in)?to \s+ (.*) \s+ from      \s+ (.*) |
  \b translate \s+ (.*) \s+ from      \s+ (.*)                        |
  \b translate \s+ (.*) \s+ (?:in)?to \s+ (.*)
  )
  \s* $
/ix;

our $default_language = 'English';

our %languages = (
    afrikaans        => 'af',
    albanian         => 'sq',
    basque           => 'hy',
    belarusian       => 'be',
    bulgarian        => 'bg',
    catalan          => 'ca',
    chinese          => 'zh',
    croatian         => 'hr',
    czech            => 'cs',
    danish           => 'da',
    estonian         => 'et',
    dutch            => 'nl',
    english          => 'en',
    filipino         => 'tl',
    finnish          => 'fi',
    french           => 'fr',
    galacian         => 'gl',
    georgian         => 'ka',
    german           => 'de',
    greek            => 'el',
    "haitian creole" => 'ht',
    hindi            => 'hi',
    italian          => 'it',
    japanese         => 'ja',
    portuguese       => 'pt',
    polish           => 'pl',
    russian          => 'ru',
    spanish          => 'es',
    yiddish          => 'yi',
);

sub _get_lang {
    my $guess = lc shift;

    $guess =~ s/^\s+//;
    $guess =~ s/\s+$//;

    if ( exists $languages{$guess} ) {
        return $languages{$guess};
    }
    if ( grep { $_ eq $guess } ( values %languages ) ) {
        return $guess;
    }
    return;
}

sub response {
    my ($event) = @_;

    $event->{VALUE} =~ $RE;

    my ( $term, $guess_from, $guess_to );
    if ($1) {
        ( $term, $guess_from, $guess_to ) = ( $1, $2, $3 );
    }
    elsif ($4) {
        ( $term, $guess_from, $guess_to ) = ( $4, $5, $6 );
    }
    elsif ($7) {
        ( $term, $guess_from, $guess_to ) = ( $7, $8, $default_language );
    }
    elsif ($9) {
        ( $term, $guess_from, $guess_to ) = ( $9, $default_language, $10 );
    }
    $term = escape $term;
    my $from = _get_lang($guess_from);
    if ( !$from ) {
        CJ::dispatch( $event, "I don't speak $guess_from" );
        return;
    }
    my $to = _get_lang($guess_to);
    if ( !$to ) {
        CJ::dispatch( $event, "I don't speak $guess_to" );
        return;
    }

    my $url
        = "https://www.googleapis.com/language/translate/v2?key="
        . $CJ::config->val( 'googleapi', 'APIkey' ) . "&q="
        . $term
        . "&source="
        . $from
        . "&target="
        . $to;

    my $req = HTTP::Request->new( GET => $url );
    my $res = $CJ::ua->request($req);

    my $content = decode_json $res->content;
    if ( $res->is_success ) {
        CJ::dispatch(
            $event,
            CJ::cleanHTML(
                $content->{data}{translations}[0]{translatedText}
            )
        );
        return;
    }
    CJ::dispatch( $event,
        "Apparently I can't do that: " . $res->status_line );
    return;
}

sub help {
    return
        "for example, 'translate some text from english to german' (valid languages: "
        . join( ', ', keys %languages )
        . ") (either the from or to is optional, and defaults to $default_language)";
}

1;
