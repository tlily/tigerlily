# known bugs:
# language should be per-instance, not global.
# maybe should break up the queue into 5-send chunks or so to avoid sending too
#   much data at babelfish.
# it doesn't like some sends (like ojiepat's).  It messes up ordering of words
#  so that part of the send ends up before the x0x.
use CGI;
use LWP::UserAgent;
use HTML::Parser;
use strict;

command_r('babelmirror' => \&babelmirror_cmd);
command_r('unbabelmirror', \&unbabelmirror_cmd);
shelp_r('babelmirror', "babelmirror a discussion into another");
shelp_r('unbabelmirror', "undo a %babelmirror");
help_r('babelmirror', 
       " usage: %babelmirror [fromdisc] [todisc]");

help_r('unbabelmirror', 
       " usage: %unbabelmirror [disc]");

my(%babelmirrored, $timed_id, @babelqueue);

# how often to translate any pending data.
my $trans_interval = 60;

sub babelmirror_cmd {
    my $ui = shift;
    my ($fromdisc,$todisc,$language) = split /\s+/, "@_";
    $fromdisc = lc($fromdisc);
    $todisc = lc($todisc);

    # (english to spanish)
    $language ||= "en_es";
    
    if ("@_" =~ /^\S*$/) {
	my $f;
	foreach (sort keys %babelmirrored) {
	    $f=1;
	    $ui->print("($_ is babelmirrored to " . (split /,/,$babelmirrored{$_})[2] . ")\n");
	}
	if (! $f) {
	    $ui->print("(no discussions are currently being babelmirrored)\n");
	}    
	return 0;
    }
    
    if (! (($fromdisc =~ /\S/) && ($todisc =~ /\S/))) {
	$ui->print("usage: %babelmirror [fromdisc] [todisc]\n");
	return 0;
    }
    
    if ($babelmirrored{$fromdisc}) {
	$ui->print("(error: $fromdisc is already babelmirrored)\n");
	return 0;
    }
    
    my $e1 = event_r(type => 'public',
		     call => sub { send_handler($fromdisc,$todisc,@_); });
    
    my $e2 = event_r(type => 'emote',
		     call => sub { send_handler($fromdisc,$todisc,@_); });

    $timed_id ||= TLily::Event::time_r(interval => $trans_interval,
                                       call     => \&timed_handler);
    
    $babelmirrored{$fromdisc}="$e1,$e2,$todisc";
    
    $ui->print("(babelmirroring $fromdisc to $todisc)\n");
    0;
}

sub unbabelmirror_cmd {
    my ($ui,$disc) = @_;
    
    if ($babelmirrored{$disc}) {
	my ($e1,$e2,$e3) = split ',',$babelmirrored{$disc};
	event_u($e1);
	event_u($e2);
	delete $babelmirrored{$disc};
	$ui->print("(\"$disc\" will no longer be babelmirrored.)\n");
    } else {
	$ui->print("(\"$disc\" is not being babelmirrored!)\n");
    }
    
}

sub send_handler {
    my ($from,$to,$e) = @_;
    
    my $match = 0;
    foreach (split ',',$e->{RECIPS}) {
	if (lc($_) eq $from) { $match=1; last; }
    }
    
    if ($match) {
	if ($e->{type} eq "emote") {
            push @babelqueue, [ $to, "| (to $e->{RECIPS}) $e->{SOURCE}$e->{VALUE}", $e->{server} ];
	} else {
            push @babelqueue, [ $to, "($e->{SOURCE} => $e->{RECIPS}) $e->{VALUE}", $e->{server} ];
	}
    }
    
    0;
}

sub timed_handler {

    my $string;
    for (0..$#babelqueue) {
        $string .= "x${_}x foo. $babelqueue[$_][1]\n";
    }

    
    if ($string) {
        my $ui = ui_name();        

        TLily::Event::keepalive();
        $ui->print("translating \"$string\n");
        my $result = translate($string, "en_es");
        TLily::Event::keepalive(5);

        $result =~ s/\n//g;
        $result =~ s/(x\d+x) foo\./\n$1/g;
        $result =~ s/^[\s\n]*//g;
        $result =~ s/[\s\n]*$//g;
        $ui->print("result = \"$result\"\n");

        foreach (split "\n", $result) {
            my ($idx, $what) = /x(\d+)x (.*)/;
            $what ||= $_;
            $what =~ s/^[\s\n]*//g;
            $what =~ s/[\s\n]*$//g;
            $ui->print("sending \"$babelqueue[$idx][0];$what\"\n");
            $babelqueue[$idx][2]->sendln("$babelqueue[$idx][0];$what\n");
        }
    }

    undef @babelqueue;
}

sub unload {
    my $ui = ui_name();
    foreach (sort keys %babelmirrored) {
	unbabelmirror_cmd($ui,$_);
    }

    event_u($timed_id);
}


my ($interesting, $result);
sub translate {
    my ($string, $language) = @_;

    my $ua = new LWP::UserAgent;
    $ua->timeout(20);

    my $req = HTTP::Request->new('POST' => 'http://babelfish.altavista.com/tr');
    $req->content_type('application/x-www-form-urlencoded');
    my $content = "doit=done&tt=urltext&lp=$language&urltext=" . CGI::escape($string);
    $req->content($content);
    my $res = $ua->request($req);
    if (! $res->is_success) {
        return "HTTP Request Failed: " . $res->status_line();
    }
    
    my $parser = new HTML::Parser(api_version => 3,
                                  start_h => [\&start, "tagname, attr"],
                                  text_h  => [\&text,  "dtext"],
                                  end_h   => [\&end,   "tagname"],
                                  unbroken_text => 1);    
    $interesting = 0;
    $result = "";
    return "HTTP Request Failed: no data returned" unless $res->content =~ /\S/;
    $parser->parse($res->content);
    return $result;
}

sub start {
    my ($tagname, $attr) = @_;

    if (($tagname eq "textarea" && $attr->{name} eq "q") ||
        ($tagname eq "td" && $attr->{bgcolor} eq "white")) {
        $interesting = 1;
    }

    if ($tagname eq "i") {
        $interesting = 0.5;
    }

}

sub end {
    my ($tagname) = @_;

    $interesting = 0;
}                           

sub text {
    my ($text) = @_;

    if ($interesting eq "0.5") {
        if ($text !~ /Error/i) { $interesting = 0; }
    }

    if ($interesting) {
        $result .= $text;
    }
}
