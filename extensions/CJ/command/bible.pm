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

    # Bible Gateway is HTTPS only, and CJ::add_throttled_HTTP cannot speak TLS:
    # TLily::Server::HTTP issues a hardcoded "GET ... HTTP/1.0" and never sets
    # {secure}, so an https URL connects to port 443 in the clear. $CJ::ua
    # handles it, as CJ::shorten and the stock command already do.
    my $res = $CJ::ua->get($url);
    if ( !$res->is_success ) {
        CJ::dispatch( $event, 'Bible Gateway is not answering.' );
        return;
    }

    my $passage = _scrape_bible( $res->content );
    if ($passage) {
        CJ::dispatch( $event, $passage );
    }
    elsif ( $event->{type} eq 'private' ) {
        CJ::dispatch( $event, "I can't find that passage." );
    }
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

    # The first verse of a chapter is marked "chapternum" rather than
    # "versenum", so matching only the latter missed every <book> <chapter>:1
    # lookup -- Genesis 1:1, Psalm 23:1, John 1:1.
    return undef
        unless (
        $content =~ m{<(?:sup|span) class="(?:versenum|chapternum)".*?>(.*?)</p}sm );
    return CJ::cleanHTML($1);
}

1;
