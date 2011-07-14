package CJ::command::anagram;
use strict;

use CGI qw/escape unescape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/
  (?:
  \b anagram \s+ (.*) \s+ with    \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*)
  )
  \s* $
/ix;

our $base_url
    = "http://wordsmith.org/anagram/anagram.cgi?language=english&anagram=";

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    my ( $term, $include, $exclude );

    if ($1) {
        ( $term, $include, $exclude ) = ( $1, $2, $3 );
    }
    elsif ($4) {
        ( $term, $exclude, $include ) = ( $4, $5, $6 );
    }
    elsif ($7) {
        ( $term, $include ) = ( $7, $8 );
    }
    elsif ($9) {
        ( $term, $exclude ) = ( $9, $10 );
    }
    else {
        ($term) = ($11);
    }
    my $url = $base_url . escape($term);
    if ($include) {
        $url .= '&include=' . escape($include);
    }
    if ($exclude) {
        $url .= '&exclude=' . escape($exclude);
    }

    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {
            my ($response) = @_;
            my $anagram = _scrape_anagram( $term, $response->{_content} );
            if ($anagram) {
                CJ::dispatch( $event, $anagram );
            }
            else {
                CJ::dispatch( $event, "That's unanagrammaticatable!" );
            }
        }
    );
    return;
}

sub help {
    return <<'END_HELP';
Given a phrase, return an anagram of it. Usage: anagram <phrase>. You can
optionally tack on "with <word>" or "without <word>" to tweak the response.
Or both. No more than one of each kind of modifier, though.
END_HELP
}

sub _scrape_anagram {
    my ( $term, $content ) = @_;

    if ( $content =~ s{.*\d+ found\. Displaying}{}smi ) {
        my @results;
        my @lines = split /\n/, $content;
        shift @lines;
        foreach my $line (@lines) {
            $line = CJ::cleanHTML($line);
            last if $line eq '';
            next if lc $line eq $term;
            push @results, $line;
        }
        return unless @results;
        return CJ::pickRandom( [@results] );
    }
    else {
        return;
    }
}

1;
