# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/stock.pl,v 1.3 2000/09/11 21:15:52 coke Exp $

use strict;

#Author: Will "Coke" Coleda

### Create a user Agent for web processing.
require LWP::UserAgent;
my $ua = new LWP::UserAgent;

my @timer_ids;
my $info = "STOCK";
my $ticker = "";
my $freq = 300;

command_r('stock', \&stock_cmd);
shelp_r('stock', "Show stock ticker updates in your status bar");
help_r( 'stock',"%stock stop                   stop ticker,
%stock <TICKER SYMBOL list>   display oneshot update for stocks.
%stock -t <TICKER SYMBOL>     start tracking stock (default is $ticker)
%stock -f <frequency>         frequency in seconds to update statusbar
                              (defaults to $freq seconds)
%stock -l                     show current settings.
");

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

	my $url = "http://finance.yahoo.com/q?s=" . join("+",@stock) . "&d=v1";
	my $response = $ua->request(HTTP::Request->new(GET => $url));
	if (!$response->is_success) {
		$ui->print("(stock request for @stock failed.)\n");
		return;
	}

	my $cnt=0;

	my @chunks = ($response->content =~ /^<td nowrap align=left>.*/mg);

	foreach (@chunks) {
                my $retval="";
		my ($time,$value,$frac,$perc,$volume) = (split(/<\/td>/,$_,))[1..5];

		if (/No such ticker symbol/) {
			$ui->print("($stock[$cnt]: Oops. No such ticker symbol. Try stock lookup.)\n");
		} else {
                        $retval = "($stock[$cnt]: Last $time, $value: Change $frac ($perc): Vol $volume)";
			$retval = cleanHTML($retval);
			$retval =~ s:(\d) / (\d):$1/$2:g;
			$retval =~ s:\( :(:g;
			$retval =~ s: \):):g;
			$retval =~ s: ,:,:g;
			$ui->print("$retval\n");
		}
		$cnt++;
	}
}

#
# return a short string about the given stock...
#  (this should be part of disp_stock)
#

sub track_stock {
	my ($stock) = @_;

	my $url = "http://finance.yahoo.com/q?s=" . join("+",$stock) . "&d=v1";
	my $response = $ua->request(HTTP::Request->new(GET => $url));
	if (!$response->is_success) {
		return "$stock: no data";
	}

	my @chunks = ($response->content =~ /^<td nowrap align=left>.*/mg);
	if (scalar (@chunks) != 1) {
		return "$stock: bad data";
	}

	my ($time,$value,$frac,$perc,$volume) = (split(/<\/td>/,$chunks[0],))[1..5];

	if ($chunks[0] =~ /No such ticker symbol/) {
		return "$stock: bad symbol";
	} else {
        	my $retval="";
		$retval = "$stock: $value ($frac)";
		$retval = cleanHTML($retval);
		$retval =~ s:(\d) / (\d):$1/$2:g;
		$retval =~ s:\( :(:g;
		$retval =~ s: \):):g;
		$retval =~ s: ,:,:g;
		return $retval;
	}
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

#TRUE! They return TRUE!
1;
