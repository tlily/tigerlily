# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/url.pl,v 1.1 1999/02/28 04:37:19 josh Exp $
#
# URL handling
#

my @urls = ();

sub handler {
    my($event, $handler) = @_;

    my $type;
    foreach $type ('http', 'https', 'ftp') {
        $event->{text} =~ s|($type://\S+[^\s\(\)\[\]\{\}\"\'\?\,\;\:\.])|
            push @urls, $1;
            my $t=$config{tag_urls}?'['.scalar(@urls).']':"";
            "<url>$1$t</url>";|ge;
    }
    return 0;
}

sub url_cmd {
    my ($ui) = shift;
    my ($arg,$num)=split /\s+/, "@_";
    my $url;

    $arg = "show" if ($arg eq "view");
    
    if ($arg eq "clear") {
       ui->print("(cleared URL list)\n");
       @urls=();
       return;
    }

    if ($arg eq "show" || $arg=~ /^-?\d+$/) {  
	if ($arg eq "show" && ! $num) {
	    $num=$#urls+1;
	}
	if ($arg=~/^-?\d+$/) { $num=$arg;	}	
	if (! defined $num) { 
	    $ui->print("(usage: %url show <number|url> or %url show or %url <number>\n"); 
            return;
	}
	if ($num=~/^-?\d+$/) {
	    if ($num > @urls || $num < -@urls) {
		$ui->print("(invalid URL number $num)\n");
		return;
	    }
            if ($num > 0) { $url=$urls[$num-1]; }
            elsif ($num == 0) { $url=$urls[$#urls]; }
            elsif ($num < 0) { $url=$urls[$#urls+$num+1]; }
        } else {
	    $url = $num;
	}

	$url =~ s/([,\"\'])/sprintf "%%%02x", ord($1)/eg;
	
	$ui->print("(viewing $url)\n");
	my $cmd=$config{browser};
	if ($cmd =~ /%URL%/) {
	    $cmd=~s/%URL%/$url/g;
	} else {
	    $cmd .= " $url";
 	}
 	if ($config{browser_textmode}) {
 	    $ui->suspend();
	    $ret=`$cmd 2>&1`;	    
 	    $ui->resume();
 	    $ui->print("$ret\n") if $ret;
 	} else {
   	    $ret=`$cmd 2>&1`;
 	    $ui->print("$ret\n") if $ret;
 	}
 	return
    }
 
    if (@urls == 0) {
	$ui->print("(no URLs captured this session)\n");
 	return;
    }
    $ui->print("| URLs captured this session:\n");
    foreach (0..$#urls) {
 	$ui->print(sprintf("| %2d) $urls[$_]\n",$_+1));
    }    
} 

event_r(type  => 'public',
	call  => \&handler,
	order => 'before');

event_r(type  => 'private',
	call  => \&handler,
	order => 'before');

event_r(type  => 'emote',
	call  => \&handler,
	order => 'before');

command_r('url' => \&url_cmd);

shelp_r('url', "View list of captured urls");
help_r('url', "
Usage: %url
       %url clear
       %url show <num> | <url>
       %url show  (will show last url)
       %url <num>
");


