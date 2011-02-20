# -*- Perl -*-
# $Id$

#
# URL handling
#

use strict;

use CGI qw/escape unescape/;
use TLily::Server::HTTP;
use URI;

my @urls = ();
my %shorten = ();
my $url_schemes = qr/https?|ftp|daap/;
my $url_base = qr/\S+[^\s;:,.!?()<>{}\[\]\"\']+/;
my $text_wrapping;

sub shorten {
    my ($ui, $url, $sender) = @_;

    $sender .= "'s" if (length($sender));
    $sender = 'Shortened' if (!length($sender));

    my $original_url = $url;
    my $original_host = new URI($url)->host();

    if (exists $shorten{$url}) {
        $ui->print("(${sender} URL: $shorten{$url}{short_url} [$original_host] (cached))\n");
        return;
    }

    my $url = 'http://metamark.net/api/rest/simple?long_url=' . escape($url);

    TLily::Server::HTTP->new(
        url => $url,
        secure => 0,
        callback => sub {
            my ($response) = @_;
            if ($response->{_state}{_status} ne 200) {
            } else {
                $response->{_content} =~ m/(http.*)/;
                my $ans = $1;
                $ans =~ s/\s//g;
                if ($ans) {
                    $shorten{$original_url}{short_url} = $ans;
                    $shorten{$original_url}{host} = $original_host;
                    $ui->print("(${sender} URL: $ans [$original_host])\n");
                }
            }
        }
    );
}

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s|($url_schemes://$url_base)|
        my $url = $1;
        if ($url ne $urls[$#urls]) {
            push @urls, $url;
        }
        shorten(ui_name($event->{ui_name}), $url, $event->{SOURCE})
            if ($config{shorten});
        my $t=$config{tag_urls} ? '['.scalar(@urls).']' : "";
        "$url$t";
    |ge;
    return 0;
}

# This handler attempts to detect wrapped URLs, but it suffers from false
# positives, and I don't think there is a way to resolve that.  The problem
# will happen when a URL ends in exactly column 79; the first word of the
# next line, if it starts immediately after the "* ", "# - " or "# > " prefix,
# will get appended to the URL.
sub text_handler {
    my($event, $handler) = @_;
    # XXXDCL Need to get real screen width from server, since that controls
    # the maximum line length coming back (doesn't it?)
    my $wrap_width = 79;

    if ($text_wrapping) {
        # "* " for memo/info, "# - " for Connect-style, "# > " for emote.
        if ($event->{text} =~ /^(\*|\# [->]) ($url_base)(.)?/) {
            $urls[$#urls] .= $2;
            if (! defined($3) && length($event->{text}) == $wrap_width) {
                # Still wrapping.
                return 0;
            } else {
                # All done; discard if duplicate and continue to look
                # for more URLs via the following loop.
                pop @urls if @urls > 1 && $urls[$#urls] eq $urls[$#urls-1];
            }
        }
    }

    $text_wrapping = 0;

    # Note that the (.)? is ok even in the presence of \G because it will
    # match whatever character (if any) terminated the search, which couldn't
    # be the first character of the next URI protocol on the line (if any).
    while ($event->{text} =~ m!\G.*?(($url_schemes)://$url_base)(.)?!g) {
        if (! defined($3) && length($event->{text}) == $wrap_width) {
            push @urls, $1;
            $text_wrapping = 1;
        } else {
            push @urls, $1 if $1 ne $urls[$#urls];
        }
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
        if ($arg=~/^-?\d+$/) { $num=$arg; }
        if (! defined $num) {
            $ui->print("(usage: %url show <number|url> or %url show ",
                       "or %url <number>\n");
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
        } elsif ($num=~m'^[a-z]*://') {
            $url = $num;
        } else {
            foreach my $testurl (reverse @urls) {
                if ($testurl=~/$num/) {
                    $url = $testurl;
                    last;
                }
            }
            $ui->print("(no url found matching '$num')\n");
            return;
        }

        $url =~ s/([,\"\'\\])/sprintf "%%%02x", ord($1)/eg;

        $ui->print("(viewing $url)\n");
        my $cmd=$config{browser};
        if ($cmd =~ /%URL%/) {
            # This should not have 'quotes' around the substitution value--
            # consider what happens when browser is set to something like
            #   mozilla -remote 'openURL("%URL",new-window)'
            # If the user wants quotes, they should just add them to the
            # browser variable.
            $cmd=~s/%URL%/$url/g;
        } else {
            # This should have quotes around it, however.
            $cmd .= " '$url'";
         }
        if ($^O =~ /MSWin32/) {
            # Escape % so that the shell doesn't try to interpolate %foo% as
            # an environment variable substitution
                $url=~s/\%/"\%"/g;  # Isn't Windows COOL!?! (Isn't CPerl-mode?)

            # If the first parameter to the 'start' command begins with a
            # quote, it's assumed to be a window title, so we need to fake
            # a blank window title and then give the URL as the second
            # parameter.
            system('start', '""', '"'.$url.'"');

        } elsif ($config{browser_textmode}) {
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

    elsif ($arg =~ m/s?list/ || $arg eq "") {
        my $count = $num || $config{url_list_count};
        $count = @urls if $count =~ /^\s*all\s*/i;
        $count = 3 if $count <= 0;
        $count = @urls if $count > @urls;

        if (@urls == 0) {
            $ui->print("(no URLs captured this session)\n");
             return;
        }

        $ui->print("| URLs captured this session:\n");

        my $format = $config{url_list_format} ?
                eval $config{url_list_format} : "| %2d) %s";

        foreach (($#urls-$count+1)..$#urls) {
            if ($arg eq 'slist' && exists $shorten{$urls[$_]}) {
                 $ui->print(sprintf("$format\n", $_+1, "$shorten{$urls[$_]}{short_url} [$shorten{$urls[$_]}{host}]"));
            } else {
                 $ui->print(sprintf("$format\n", $_+1, $urls[$_]));
            }
        }
        return;
    }

    else {
        $ui->print(
          "(%url [view | list | slist | clear]; type %help for help)\n"
        );
    }

    return;
}

sub shorten_cmd {
    my $ui = shift;
    my ($sender, $url) = split(/\s+/, shift, 2);
    if (!length($url)) {
        $url = $sender;
        $sender = undef;
    }

    return unless $url =~ m|($url_schemes://$url_base)|;

    shorten($ui, $1, $sender) if $1;
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

event_r(type  => 'text',
        call  => \&text_handler,
        order => 'before');

command_r('url' => \&url_cmd);
command_r('shorten' => \&shorten_cmd);

shelp_r('url', "View list of captured urls");
help_r('url', q{
Usage: %url
       %url list [all | <count>]
       %url slist [all | <count>]
       %url clear
       %url show <num> | <regex> | <url>
       %url show  (will show last url)
       %url <num>

With no arguments, or with the 'list' or 'slist' command forms, %url will
list out the specified amount of most-recently captured URLs, or the last
$url_list_count URLs captured if no amount is given.  The 'slist'
form will display shortened versions of the URLs, if shortened versions
are available in the cache (if the $shorten config variable is set to true,
all captured URLs should be shortened).

The 'show' command will attempt to display the specified URL in your web
browser, as configured in the $browser config variable.  It will replace
the string '%URL%' with the URL, if present, or otherwise append the URL,
and the execute the command.

Note: the browser and browser_textmode variables are ignored if you're on
Windows running ActiveState Perl. In that case, your default browser is used.
});

shelp_r('shorten', "Shorten a given URL, or URL in a block of text");
help_r('shorten', q{
Usage: %shorten http://slashdot/
       %on public to surf %shorten $sender $value
       %on public server NotRPI %shorten $sender $value

If passed a single argument (space-delimited), %shorten will just return
the shortened URL (if possible).  If passed more than one space-delimited
argument, %shorten will assume the first word is the sender, and that the
rest of the argument is a text block to look for URLs in.

If you want to shorten ALL URLs seen in any event from any server, then
instead of using %on as described above, set the $shorten config variable
to true:
  %set $shorten 1
});

shelp_r('browser', "[string] browser command for %url", "variables");
shelp_r('browser_textmode', "[boolean] open textmode browser open in tlily", "variables");
shelp_r('shorten', "[boolean] Shorten ALL captured URLs", "variables");

