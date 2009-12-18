# -*- Perl -*-
# $Id$

use strict;

#Author: Will "Coke" Coleda

### Create a user Agent for web processing.
require LWP::UserAgent;
my $ua = new LWP::UserAgent;

my (%timer, $timer_id);
my $info = "STOCK";
$config{stock_symbol}="EXDS" if (!exists $config{stock_symbol});
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
	TLily::UI->name("main")->set(stock => "");
	TLily::Event::time_u($timer_id);
}




sub start_tracker {
	my $ui = $_[0];
	$ui->define(stock => 'right');
	$info = "Waiting for $config{stock_symbol}";
	$ui->set(stock => $info);
	$timer{interval} = $config{stock_freq};
	$timer{call} = 
	  sub {$ui->set(stock => track_stock($config{stock_symbol}))};
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
