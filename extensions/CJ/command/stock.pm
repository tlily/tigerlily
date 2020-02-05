package CJ::command::stock;
use strict;

use List::MoreUtils qw/uniq/;

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
Usage: stock <LIST of comma or space separated symbols> for basic information.
Stock information comes from yahoo, and CJ makes no guarantee as to the
accuracy or timeliness of this information.
END_HELP
}

sub _get_stock {
    my ( $event, @stock ) = @_;

    my $url
        = 'https://query1.finance.yahoo.com/v7/finance/quote?symbols='
        . join(',', uniq @stock);

    my $req = HTTP::Request->new( GET => $url );
    my $res = $CJ::ua->request($req);

    my $content = decode_json $res->content;

    my @results;

    if ( $res->is_success ) {
        foreach (@{$content->{quoteResponse}{result}}) {
            my $data = $_;

            push @results,
                sprintf "%-6s %7.2f %3s, Chg: %6.1f%% [%s]",
                    $data->{symbol},
                    $data->{regularMarketPrice},
                    $data->{financialCurrency},
                    $data->{regularMarketChangePercent},
                    $data->{shortName}

        }
        if (! @results ) {
            CJ::dispatch( $event,
                "Symbol(s) not found" );
            return;
        }

        foreach (@results) {
            CJ::dispatch( $event, $_);
        }
        return;
    }

    CJ::dispatch( $event,
        "Apparently I can't do that: " . $res->status_line );
    return;

}

1;
