package CJ::command::stock;
use strict;

use JSON;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bstock\s+(.*)/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $args = $1;

    _get_stock( $event, split( /[, ]+/, $args ) );
    return;
}

sub help {
    return <<'END_HELP',
Usage: stock <ticker symbol> for basic information.
Stock information comes from yahoo, and CJ makes no guarantee as to the
accuracy or timeliness of this information.
END_HELP
}

sub _get_stock {
    my ( $event, @stock ) = @_;

    if (@stock != 1) {
        CJ::dispatch( $event, "Please specify a single ticker symbol");
        return;
    }

    my $stock = @stock[0];
    my $url
        = 'https://query1.finance.yahoo.com/v7/finance/quote?symbols='
        . $stock;

    my $req = HTTP::Request->new( GET => $url );
    my $res = $CJ::ua->request($req);

    my $content = decode_json $res->content;

    if ( $res->is_success ) {
        if (! $content->{quoteResponse}{result}[0] ) {
            CJ::dispatch( $event,
                "Invalid ticker symbol" );
            return;
        }
        my $data = $content->{quoteResponse}{result}[0];
        CJ::dispatch(
            $event,
            CJ::cleanHTML(
                $data->{symbol} . ' [' . $data->{shortName}
                . '] '. (sprintf '%.2f', $data->{regularMarketPrice})
                . ' ' . $data->{financialCurrency}
                . ', Change: ' . (sprintf '%.2f', $data->{regularMarketChangePercent}) . "%"
            )
        );
        return;
    }
    CJ::dispatch( $event,
        "Apparently I can't do that: " . $res->status_line );
    return;

}

1;
