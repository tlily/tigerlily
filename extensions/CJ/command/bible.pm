package CJ::command::bible;
use strict;

use CGI qw/escape/;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;

our $RE = qr/\b(?:bible|passage)\s*(kjv|asv|vulg)?\s+(.*\d+:\d+)/;

our $bibles = {
    'kjv'  => { id => 'KJV',     name => 'King James Version' },
    'asv'  => { id => 'ASV',     name => 'American Standard Version' },
    'vulg' => { id => 'VULGATE', name => "Biblia Sacra Vulgata" },
};

sub response {
    my ($event) = @_;
    my $args = $event->{VALUE};

    $event->{VALUE} =~ $RE;

    my $bible = lc $1;
    my $term  = escape $2;

    $bible = 'kjv' unless $bible;
    my $id = $bibles->{$bible}->{id};

    my $url = "https://www.biblegateway.com/passage/?search=$term&version=$id";

    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => ' main ',
        callback => sub {
            my ($response) = @_;
 CJ::debug(keys %$response);
            my $passage = _scrape_bible( $response->{_content} );
            if ($passage) {
                CJ::dispatch( $event, $passage );
            }
            return;
        }
    );
    return;
}

sub help {
    my $help = <<'END_HELP';
Quote chapter and verse. Syntax: bible or passage, followed by an optional
bible version, and then the name of the book and chapter:verse. Possible
translations include:
END_HELP
    foreach my $key ( keys %$bibles ) {
        $help .= $key . ' {' . $bibles->{$key}->{name} . '} ';
    }
    return $help;
}

sub _scrape_bible {
    my ($content) = @_;

CJ::debug($content);
    $content =~ m{<sup class="versenum".*?>(.*?)</p}sm;
    return CJ::cleanHTML($1);
}

1;
