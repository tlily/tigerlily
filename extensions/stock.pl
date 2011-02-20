# -*- Perl -*-

use strict;

#Author: Will "Coke" Coleda

### Create a user Agent for web processing.
use TLily::Server::HTTP;

my (%timer, $timer_id);
my $info = "STOCK";
$config{stock_symbol}="GOOG" if (!exists $config{stock_symbol});
$config{stock_freq}=300 if (!exists $config{stock_freq});

command_r('stock', \&stock_cmd);
shelp_r('stock_symbol', "Display this ticker symbol", "variables");
shelp_r('stock_freq', "Frequency in seconds to update ticker symbol","variables");
shelp_r('stock', "Show stock ticker updates in your status bar");
help_r( 'stock',"%stock <TICKER SYMBOL list>   display oneshot update for stocks.

There are two config variables: stock_symbol and stock_freq. The former
controls the stock to be queried for the command line update and
the latter controls the frequency.

To force a change before the timer would go off, simply reload the extension.
");

#
# Once you can remove a config callback, we can prolly ditch start/stop
#


#
# There's got to be a module to do this for me. =-)
#
sub cleanHTML {

        $a = join(" ",@_);

        $a =~ s/\n/ /;
        $a =~ s/<[^>]*>/ /g;
        $a =~ s/&lt;/</gi;
        $a =~ s/&gt;/>/gi;
        $a =~ s/&amp;/&/gi;
        $a =~ s/&#46;/./g;
        $a =~ s/&quot;/"/ig;
        $a =~ s/&nbsp;/ /ig;
        $a =~ s/&uuml;/u"/ig;
        $a =~ s/\s+/ /g;
        $a =~ s/^\s+//;

        return $a;
}

#
# print out stock quote information for the given stocks..
#

sub disp_stock {
        my ($ui,@stock) = @_;

        my $url = "http://finance.yahoo.com/d/quotes.csv?s=" . join("+",@stock) . "&f=sl1d1t1c2v";

    TLily::Server::HTTP->new(
      url => $url,
      callback => sub {

        my ($response) = @_;

        my @chunks = split ( /\n/, $response->{_content} );

        foreach (@chunks) {
                my ( $stock, $value, $date, $time, $change, $volume ) =
                  map { s/^"(.*)"$/$1/; $_ } split( /,/, $_ );
                $change =~ s/^(.*) - (.*)$/$1 ($2)/;

                        $ui->print("$stock: Last $date $time, $value: Change $change\n");
                }
  });
}

#
# return a short string about the given stock...
#  (this should be part of disp_stock)
#

sub track_stock {
        my (@stock) = @_;

        my $ui = TLily::UI->name("main");
        my $url = "http://finance.yahoo.com/d/quotes.csv?s=" . join("+",@stock) . "&f=sl1d1t1c2v";

    TLily::Server::HTTP->new(
      url => $url,
      callback => sub {

        my ($response) = @_;

        my @chunks = split ( /\n/, $response->{_content} );

    my @retval;
        foreach (@chunks) {
                my ( $stock, $value, $date, $time, $change, $volume ) =
                  map { s/^"(.*)"$/$1/; $_ } split( /,/, $_ );

                $change =~ s/^(.*) - (.*)$/$1/;

        push @retval, "$stock:$value($change)";
                }


  TLily::UI->name("main")->set(stock => join (" ",@retval));

  });

}

#
# stop any statusline updates we're doing..
#

sub unload {
        TLily::UI->name("main")->set(stock => "");
        TLily::Event::time_u($timer_id);
}


sub start_tracker {
    my $ui = $_[0];
    $ui->define(stock => 'right');
    $info = "Waiting for $config{stock_symbol}";
    $ui->set(stock => $info);
    $timer{interval} = $config{stock_freq};
    my $stocks = $config{stock_symbol};
    $stocks =~ s/^\s+//;
    $stocks =~ s/\s+$//;
    my @stocks = split(/[\s,]+/,$stocks);
        $timer{call} = sub { track_stock(@stocks) };
        $timer_id = TLily::Event::time_r(\%timer);
}

#
# Handle any new requests for information
#
sub stock_cmd {
        my ($ui,$cmd) = @_;
        disp_stock($ui,split(/[\s,]+/,$cmd));
}

start_tracker(TLily::UI->name("main"));

#TRUE! They return TRUE!
1;
