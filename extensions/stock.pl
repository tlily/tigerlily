use strict;

my @timer_ids;
my $info = "STOCK";
my $ticker = "";
my $freq = 15;

command_r('stock', \&stock_cmd);
shelp_r('stock', "Show stock ticker updates in your status bar");
help_r( 'stock','%stock stop                   stop ticker,
%stock <TICKER SYMBOL list>   display oneshot update for stocks. (NYI)
%stock -t <TICKER SYMBOL>     start tracking stock (default is $ticker)
%stock -f <frequency>         frequency in seconds to update statusbar
                              (defaults to $freq)
%stock -l                     show current settings.
');


#
# return stock quote information for the given stocks..
# (although we only ever use -one-, this is more extensible)
#

sub disp_stock {
    my ($ui,@stock) = @_;
    my $cmd = "wget -O- -q 'http://quote.yahoo.com/q?s=" . join("+",@stock) . "&d=v1'
";
    open (N,"$cmd|") or return "Quote for @stock failed";
    
    my @retval = () ;
    my $cnt = 0;
    while (<N>) {
	if (! m:^(</tr>)?<tr align=right>:) {next};
	<N>;			#discard symbol line
	my ($last_time, $last_value, $change_frac, $change_perc, $volume);
	chomp( $last_time = <N> ) ;
	chomp( $last_value = <N> ) ;
	chomp( $change_frac = <N> ) ;
	chomp( $change_perc = <N> ) ;
	chomp( $volume = <N> ) ;
	$last_time =~ s/(<[^>]*>)//g;
	$last_value =~ s/(<[^>]*>)//g;
	$change_frac =~ s/(<[^>]*>)//g;
	$change_perc =~ s/(<[^>]*>)//g;
	$volume =~ s/(<[^>]*>)//g;
	
	$ui->print("($stock[$cnt]: last trade: $last_time, $last_value. Change: $change_frac ($change_perc). Volume: $volume)\n");
	$cnt++;
    }
    close(N);
}

sub track_stock {
    my @stock = @_;
    
    my $cmd = "wget -O- -q 'http://quote.yahoo.com/q?s=" . join("+",@stock) . "&d=v1'";
    open (N,"$cmd|") or return "Quote for @stock failed";
    my @retval = () ;
    my $cnt = 0;
    while (<N>) {
	if (! m:^(</tr>)?<tr align=right>:) {next};
	<N>; <N>;		#toss 2 lines
	my ($last_value, $change_frac);
	chomp( $last_value = <N> ) ;
	chomp( $change_frac = <N> ) ;
	$last_value =~ s/(<[^>]*>)//g;
	$change_frac =~ s/(<[^>]*>)//g;
	push @retval, "$stock[$cnt]: $last_value ($change_frac)";
	$cnt++;
    }
    close(N);
    return join("",@retval);
}

#
# stop any statusline updates we're doing..
#

sub unload {
    foreach (@timer_ids) {
	TLily::Event::time_u($_);
    }
    @timer_ids = ();
}


#
# update the stock price every $freq seconds...
#

sub setup_handler {
    my ($ui) = @_;

    my $timer_id = TLily::Event::time_r(interval => $freq,
					call  => sub { 
					    $info = track_stock($ticker);
					    $ui->set(stock => $info);
					});
    push @timer_ids, $timer_id;
}

#
# Handle any new requests for information
#
sub stock_cmd {
    my ($ui,$cmd) = @_;
    
    if ($cmd eq "stop") {
	$ticker = "" ;
	$info = "";
	$ui->set(stock => $info);	
	unload();
    } elsif ($cmd =~ /^-t\s*(.*)/) {
	unload();
	$ticker = $1;
	$ui->define(stock => 'right');
	$info = "Waiting for $ticker";
	$ui->set(stock => $info);
	setup_handler($ui);
    } elsif ($cmd =~ /^-f\s*(.*)/) {
	unload();
	$freq = $1;
	setup_handler($ui);
    } elsif ($cmd eq "-l" || $cmd !~ /\S/) {
	if (@timer_ids) {
	    $ui->print("(Tracking: '$ticker' at a frequency of $freq seconds.)\n");
	} else {
	    $ui->print("(currently not tracking any stocks)\n");
	}
    } else {
	disp_stock($ui,split(/\s+/,$cmd));
    }
}

1;
