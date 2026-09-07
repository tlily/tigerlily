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

Fetch one symbol. Returns ($line, $error): a symbol Nasdaq does not list gives
(undef, undef), which is an answer. A request that failed gives an error, so
that a service which is down, rate limiting us, or unreachable does not get
reported as an unknown ticker.

=cut

sub _quote {
    my ($symbol) = @_;

    my $error;

    foreach my $asset_class (@asset_classes) {
        my $url
            = $quote_url . '/'
            . uc($symbol)
            . '/info?assetclass='
            . $asset_class;

        my $req = HTTP::Request->new( GET => $url );
        $req->header( 'User-Agent' => $browser_agent );
        my $res = $CJ::ua->request($req);
        if ( !$res->is_success ) {
            $error = 'Nasdaq answered ' . $res->status_line;
            next;
        }

        my $content = eval { decode_json( $res->content ) };
        if ($@) {
            $error = 'I could not parse what Nasdaq sent';
            next;
        }

        my $data = $content->{data};
        next unless ( $data && $data->{primaryData} );

        my $p = $data->{primaryData};
        ( my $price = $p->{lastSalePrice} || q{} ) =~ s/^\$//;

        return ( sprintf(
            '%-6s %8s, Chg: %s (%s) [%s]',
            uc($symbol),
            $price,
            $p->{netChange}        || '?',
            $p->{percentageChange} || '?',
            $data->{companyName}   || uc($symbol)
        ), undef );
    }

    # Every asset class either said "no such symbol" or failed outright.
    return ( undef, $error );
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

    my ( @results, @errors );
    foreach my $symbol (@symbols) {
        my ( $line, $error ) = _quote($symbol);
        push @results, $line  if defined $line;
        push @errors,  $error if defined $error;
    }

    if ( !@results ) {
        # Say which it was. Reporting a lookup that never happened as a missing
        # symbol is what made this impossible to diagnose from the discussion.
        CJ::dispatch( $event,
            @errors ? "Stock lookup failed: $errors[0]." : 'Symbol(s) not found' );
        return;
    }

    foreach (@results) {
        CJ::dispatch( $event, $_ );
    }
    return;
}

1;
