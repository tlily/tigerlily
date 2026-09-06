package CJ::command::stock;
use strict;

use List::MoreUtils qw/uniq/;

use JSON;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bstock\s+(.*)/i;

# Yahoo's v7 quote endpoint now answers "Unauthorized" to anyone without a
# session crumb, so it cannot be used unauthenticated any more. Nasdaq's public
# quote endpoint needs no key and carries the same three things this printed:
# price, change, and the company name.
#
# It takes one symbol per request rather than a batch, and wants to be told
# which asset class to look in -- stocks first, then ETFs, which covers
# anything anyone asks a chat bot about.

our $quote_url     = 'https://api.nasdaq.com/api/quote';
our @asset_classes = qw/stocks etf/;

# Nasdaq refuses a default LWP user-agent.
our $browser_agent
    = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    . '(KHTML, like Gecko) Chrome/120 Safari/537.36';

# A cap, so "stock" followed by a paragraph does not fire off fifty requests.
our $max_symbols = 5;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $args = $1;

    _get_stock( $event, split( /[, ]+/, $args ) );
    return;
}

sub help {
    return <<'END_HELP',
Usage: stock <LIST of comma or space separated symbols> for basic information.
Stock information comes from Nasdaq, and CJ makes no guarantee as to the
accuracy or timeliness of this information.
END_HELP
}

=head2 _quote($symbol)

Fetch one symbol, returning a formatted line or undef if it is not found.

=cut

sub _quote {
    my ($symbol) = @_;

    foreach my $asset_class (@asset_classes) {
        my $url
            = $quote_url . '/'
            . uc($symbol)
            . '/info?assetclass='
            . $asset_class;

        my $req = HTTP::Request->new( GET => $url );
        $req->header( 'User-Agent' => $browser_agent );
        my $res = $CJ::ua->request($req);
        next unless $res->is_success;

        my $content = eval { decode_json( $res->content ) };
        next if $@;

        my $data = $content->{data};
        next unless ( $data && $data->{primaryData} );

        my $p = $data->{primaryData};
        ( my $price = $p->{lastSalePrice} || q{} ) =~ s/^\$//;

        return sprintf(
            '%-6s %8s, Chg: %s (%s) [%s]',
            uc($symbol),
            $price,
            $p->{netChange}        || '?',
            $p->{percentageChange} || '?',
            $data->{companyName}   || uc($symbol)
        );
    }

    return undef;
}

sub _get_stock {
    my ( $event, @stock ) = @_;

    my @symbols = grep {/^[A-Za-z.\-]{1,8}$/} uniq @stock;
    if ( !@symbols ) {
        CJ::dispatch( $event, 'Usage: stock <symbols>' );
        return;
    }
    @symbols = @symbols[ 0 .. $max_symbols - 1 ]
        if ( @symbols > $max_symbols );

    my @results = grep { defined } map { _quote($_) } @symbols;

    if ( !@results ) {
        CJ::dispatch( $event, 'Symbol(s) not found' );
        return;
    }

    foreach (@results) {
        CJ::dispatch( $event, $_ );
    }
    return;
}

1;
