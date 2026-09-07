package CJ::command::bacon;
use strict;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/\bbacon\s+(.*)\s*$/i;

# The Oracle of Bacon is still running, but two things moved since this was
# written: the query is a POST rather than a GET, and the answer now lives in
# an element with id="linkresult" instead of the old <div id="main">. It also
# stalls on a default LWP user-agent, hence the browser one below.
#
# A POST means this cannot use CJ::add_throttled_HTTP, which issues a hardcoded
# "GET ... HTTP/1.0"; $CJ::ua handles it, as CJ::shorten and stock already do.

our $bacon_url = 'https://oracleofbacon.org/movielinks.php';

our $browser_agent
    = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    . '(KHTML, like Gecko) Chrome/120 Safari/537.36';

sub _scrape_bacon {
    my ($content) = shift;

    if ( $content =~ /The Oracle cannot find/ ) {
        return "No match.";
    }
    elsif ( $content =~ /There are \d+ people named/ ) {
        return "That's not a unique name, sorry.";
    }

    # The answer, and only the answer.
    return undef unless ( $content =~ m{<[^>]*id="linkresult"[^>]*>(.*?)</div>}sm );
    my $result = $1;

    $result = CJ::cleanHTML($result);

    # The page appends the search settings to the answer; they are not part of
    # it.
    $result =~ s/\s*to\s+Using:.*$//i;

    return $result;
}

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $term = $1;

    if ( lc($term) eq 'kevin bacon' ) {
        CJ::dispatch( $event,
            'Kevin Bacon has a Bacon number of 0.'
        );
        return;
    }
    elsif ( lc($term) eq 'coke' ) {
        CJ::dispatch( $event, 'Heart attack in a glass, baby.' );
        return;
    }
    if ( $term =~ m/ \s* (\w+) \s* , \s* (\w+) \s+ \(([ivxlcm]*)\) /smix ) {
        $term = "$2 $1 ($3)";
    }

    my $res = $CJ::ua->post(
        $bacon_url,
        { a => 'Kevin Bacon', b => $term },
        'User-Agent' => $browser_agent,
    );

    if ( !$res->is_success ) {
        CJ::dispatch( $event,
            'The Oracle answered ' . $res->status_line . '.' );
        return;
    }

    # decoded_content, not content: CJ::cleanHTML finishes with unidecode(),
    # which wants characters. Handed raw UTF-8 bytes it reads each one as
    # Latin-1, so the "\xC2\xA0" of a non-breaking space becomes "\x{C2}\x{A0}"
    # -- and unidecode turns U+00C2 into a literal "A". That is where the
    # stray "A" in "16A For God so loved the world" came from.
    my $html = $res->decoded_content;
    $html = $res->content unless defined $html;

    my $answer = _scrape_bacon($html);
    CJ::dispatch( $event,
        $answer || "The Oracle had nothing to say about $term." );
    return;
}

sub help {
    return "Find someone's bacon number using https://oracleofbacon.org/. "
        . "Usage: bacon <actor>";
}

1;
