# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/url.pl,v 1.11 2000/02/07 05:30:24 tale Exp $

#
# URL handling
#

use strict;

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
    my ($url,$ret);

    $arg ||= "";
    $arg = "show" if ($arg eq "view");
    
    if ($arg eq "clear") {
       $ui->print("(cleared URL list)\n");
       @urls=();
       return;
    }

    elsif ($arg eq "show" || $arg=~ /^-?\d+$/) {  
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
	    TLily::Event::keepalive();
 	    $ui->suspend();
	    if ($^O =~ /cygwin/) {	    
	        $ret=`$cmd`;
	    } else {
	        $ret=`$cmd 2>&1`;	    
	    }
 	    $ui->resume();
 	    $ui->print("$ret\n") if $ret;
 	} else {
	    TLily::Event::keepalive(15);
	    if ($^O =~ /cygwin/) {	    
		$ret=`$cmd`;
	    } else {
		$ret=`$cmd 2>&1`;
	    }
 	    $ui->print("$ret\n") if $ret;
 	}
 	return
    }

    elsif ($arg eq "list" || $arg eq "") {
        my $count = $num || $config{url_list_count};
	$count = @urls if ($count !~ /^\d+$/);
	$count = 3 if ($count <= 0);
	$count = @urls if ($count > @urls);

        if (@urls == 0) {
	    $ui->print("(no URLs captured this session)\n");
 	    return;
        }

        $ui->print("| URLs captured this session:\n");

        my $format = $config{url_list_format} ?
                eval $config{url_list_format} : "| %2d) %s";

        foreach (($#urls-$count+1)..$#urls) {
 	    $ui->print(sprintf("$format\n", $_+1, $urls[$_]));
        }    
	return;
    }

    else {
	$ui->print("(%url [view | list | clear]; type %help for help)\n");
    }

    return;
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

# XXX The handling of finding URLs in raw text messages (ie, /review output)
# is imperfect, because it can't tell when a URL has spilled over from one
# text line to the next.  It could be improved on by having the handler note
# when the URL ends at column 79 and then add the start of the the next
# line (repeating as long as the URL reaches column 79).  This method would
# have a different shortcoming, because it would not necessarily be the
# case that the start of the next line is still part of the URL.  The chances
# of that happening, however, are almost certainly less than the chances that
# a URL will have wrapped onto multiple lines.
event_r(type  => 'text',
	call  => \&handler,
	order => 'before');

command_r('url' => \&url_cmd);

shelp_r('url', "View list of captured urls");
help_r('url', "
Usage: %url
       %url list [all | <count>]
       %url clear
       %url show <num> | <url>
       %url show  (will show last url)
       %url <num>
");


