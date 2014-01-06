package CJ::command::stock;
use strict;

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
Usage: stock <LIST of comma or space separated symbols> for generic information
or stock (<amount> <stock>) to show the value of a certain number of shares.
Stock information comes from yahoo, and CJ makes no guarantee as to the
accuracy or timeliness of this information.
END_HELP
}

sub _get_stock {
    my ( $event, @stock ) = @_;
    my %stock     = ();
    my %purchased = ();
    my $cnt       = 0;
    my @retval;

    if ( $stock[0] =~ /^[\d@.]+$/ ) {
        while (@stock) {
            my $num   = shift @stock;
            my $stock = uc( shift @stock );
            $num =~ /^([\d.]+)(@([\d.])+)?$/;
            my $shares   = $1;
            my $purchase = $3;
            $stock{$stock}     = $shares;
            $purchased{$stock} = $purchase;
        }
        @stock = keys %stock;
    }

    my $total = 0;
    my $gain  = 0;

    my $url
        = 'http://download.finance.yahoo.com/d/quotes.txt?s='
        . join( ',', @stock )
        . '&f=sl1d1t1c2v';
    CJ::add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {

            my ($response) = @_;
            my (@invalid_symbols);

            my @chunks = split( /\n/, $response->{_content} );
            foreach my $chunk (@chunks) {
                my ( $stock, $value, $date, $time, $change, $volume )
                    = map { s/^"(.*)"$/$1/; $_ }
                    split( /,/, CJ::cleanHTML($chunk) );
                if ( $volume =~ m{N/A} && $change =~ "N/A") {
                    # skip unknown stocks.
                    push @invalid_symbols, $stock;
                    next;
                }
                $change =~ s/^(.*) - (.*)$/$1 ($2)/;
                if (%stock) {
                    my $sub = $value * $stock{$stock};
                    $total += $sub;
                    if ( $purchased{$stock} ) {
                        my $subgain = ( $value - $purchased{$stock} )
                            * $stock{$stock};
                        $gain += $subgain;
                        push @retval,
                            "$stock: Last $date $time, $value: Change $change: Gain: $
subgain";
                    }
                    else {
                        push @retval,
                            "$stock: Last $date $time, $value: Change $change: Tot: $sub";
                    }
                }
                else {
                    push @retval,
                        "$stock: Last $date $time, $value: Change $change: Vol: $volume";
                }
            }

            if ( %stock && @stock > 1 ) {
                if ($gain) {
                    push @retval, "Total gain:  $gain";
                }
                push @retval, "Total value: $total";
            }

            my $retval = CJ::wrap(@retval);

            if ( @invalid_symbols && $event->{type} eq 'private' ) {
                CJ::dispatch( $event, 'Invalid Ticker Symbols: ' . join ', ',
                    @invalid_symbols );
            }
            CJ::dispatch( $event, $retval );
        }
    );
}

1;
