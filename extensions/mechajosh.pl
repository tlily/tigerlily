# -*- Perl -*-
# $Id$
use TLily::Bot standard;

bot_r(match => "grope",
      respond => "Me grope good!");

bot_r(match => "answer",
      respond => "The answer is 42, silly!");

bot_r(match => "excuse",
      respond => sub {
	  $exc=getquote("http://cgi.cs.wisc.edu/scripts/ballard/bofhserver.pl");
	  $exc =~ s/The cause of the problem is/Automatic Excuse/;
	  if ($exc =~ /\S/) {
	      return($exc);
	  } else {
	      return(undef);
	  }
      }
     );

bot_r(match => "surreal|weird|compliment",
      respond => sub {
	  $comp=getquote("http://www.madsci.org/cgi-bin/cgiwrap/~lynn/jardin/SCG");
	  if ($comp =~ /\S/) {
	      s/^\s*//;
	      return($comp);
	  } else {
	      return(undef);
	  }
		    }
     );

bot_r(match => "search",
      respond => sub { getsearch(); }
     );


##############################################################################
sub getquote {
    my ($url)=@_;
    my ($ret,$p);

    print "getting url\n";
    open (E, '-|', "lynx -dump $url");
    foreach (<E>) {
	if (/____/) {
	    $p=! defined($p);
	    next;
	}
	if (/^\s*$/) { next; }
	s/\s+/ /g;
	if ($p) { $ret .= $_; }
    }
    close(E);

    $ret;
}

sub getsearch {
    my ($ret);

    for (1..5) {
      print "getting url\n";
      open (E, '-|', 'lynx -dump http://www.webcrawler.com/cgi-bin/SearchTicker');
      $ret = <E>;
      $ret = <E>;
      $ret = <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret =~ s/[\r\n]//g;
      close(E);
      last unless ($ret =~ /Choose a Channel/);
      $ret = "Unable to get a response from the SearchTicker.";
      sleep 1;
    }
    $ret;
}

1;
