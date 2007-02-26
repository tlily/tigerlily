# -*- Perl -*-
# $Header: /data/cvs/lily/tigerlily2/extensions/cj.pl,v 1.2 2000/12/01 19:22:54 coke Exp $

use strict;

use lib qw(/Users/cjsrv/lib);    # XXX hack.

use CGI qw/escape unescape/;
use Data::Dumper;

use TLily::Server::HTTP;
use URI;
use XML::RSS::Parser;
use Config::IniFiles;
use DB_File;    # get rid of this now that we have Config::IniFiles...

use Chatbot::Eliza;

#use Net::IRC

=head1 AUTHOR

Will "Coke" Coleda

=head1 PURPOSE

This extension allows a player to act like a bot. It is designed to run
as a standalone user: don't expect to login to lily as yourself and run
this, it will take over your session.

There are two types of output that are generated:

=over 4

=item 1

Responses to queries. Each public, private or emote type send is checked
to see if matches certain regular expressions. If the expression matches,
a chunk of code is run against that event, and a response may be generated
to the discussion(s) or user the original message was targeted to.

=item 2

Broadcasts. Timers run every so often which look for new information (say,
from an RSS feed), and then announce this information to certain discussions.

=back

=head1 HISTORY

CJ was a bot. He did a lot of things that some folks found useful,
and did a lot of things that some folks thought was waaaaay too chatty.
He began as a lily-server based magic 8-ball, was ported to a bot using
tlily version 1. This brings CJ up to tlily version 2 as a fresh
implementation. I was going to use Josh's Bot.pm to handle a good chunk 
of the guts for me, but Bot.pm didn't really seem to meet my needs.
This rewrite is intended as an exercize to (a) improve stability, (b) 
improve maintainability, (c) prepare for a similar capability for Flow.
Perhaps someone could remove most of the functionality here and make
a ComplexBot module.

=cut

#########################################################################
my %response;    #Container for all response handlers.
my %throttle;    #Container for all throttling information.

#my $irc_obj = new Net::IRC;
my %irc;         #Container for all irc channel information
my $throttle_interval = 1;    #seconds
my $throttle_safety   = 5;    #seconds
my %prefs;     #dbmopen'd hash of lily user prefs. (XXX KILL THIS)
my $config;    # Config::IniFiles object storing preferences.
my $disc       = "cj-admin";    #where we keep our memos.
my $debug_disc = "cj-admin";
my %disc_feed;    # A cached copy of which discussions each feed goes to
my %disc_annotations
  ;               # A cached copy of which discussions each annotation goes to.
my %annotations;        # A cached copy of what our annotations do.
my %annotation_code;    # ala response, but for annotations.
my ( $every_10m, $every_30s, $frequently );    #timers

# some array refs of sayings...
my $sayings;      # pithy 8ball-isms.
my $overhear;     # listen for my name occasionally;
my $buzzwords;    # random set of words.

# Unify this into generic special handling. =-)
my $unified;      # special handling for the unified discussion.
my $beener;       # special handling for the beener discussion.

my $uptime = time();    #uptime indicator.
my %served;             #stats.

# we don't expect to be changing our name frequently, cache it.
my $name = TLily::Server->active()->user_name();

# we'll use Eliza to handle any commands we don't understand, so set her up.
my $eliza = new Chatbot::Eliza { name => $name, prompts_on => 0 };

=head1 Methods

=head2 debug( @complaints) 

Helpful when generating debug output for new features. Typically disabled

=cut

sub debug {
    TLily::Server->active()->cmd_process("$debug_disc: @_");
}

# XXX use File::*
my $config_file = $ENV{HOME} . "/.lily/tlily/CJ.ini";

=head2 asAdmin( $event, $callback) 

If someone is an admin, perform a task. The bot user should have a group
called "admins" - if the user is part of that group, then she's a moderator.

=cut

sub asAdmin {
    my ( $event, $sub ) = @_;
    my $server = TLily::Server::active();

    my $isAdmin = grep { $event->{SHANDLE} eq $_ }
      split( /,/, $server->{NAME}->{'admins'}->{'MEMBERS'} );

    if ($isAdmin) {
        $sub->();
    }
    else {
        dispatch( $event, "I'm a frayed knot." );
    }
}

=head2 pickRandom( $listref )

Given a ref to a list, return a random element from it.

=cut

sub pickRandom {
    my @list = @{ $_[0] };
    return $list[ int( rand( scalar(@list) ) ) ];
}

# URL => {headline,provider,summary,age,headlines,short_url}

sub get_feeds {
    my @feeds = $config->GroupMembers("feed");
    foreach my $feed (@feeds) {
        my $url = $config->val( $feed, "url" );
        get_feed( $feed, $url );
    }
}

# Get a feed.
my %rss_feeds;
my $xmlparser = new XML::RSS::Parser;

sub get_feed {
    my ( $source, $url ) = @_;
    add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {

            my ($response) = @_;

            foreach my $url ( keys %{ $rss_feeds{$source} } ) {

         # 12 is arbitrary here.  I believe updates are every half hours, so
         # this would mean more than 6 hours without the URL being referenced in
         # the feed data.

                if ( $rss_feeds{$source}{$url}{'__untouchedcount'}++ > 12 ) {
                    delete $rss_feeds{$source}{$url};
                }
            }

            my $feed = $xmlparser->parse( $response->{_content} );

            foreach my $item ( $feed->items() ) {
                my $data = {};
                map { $data->{ $_->name } = $_->value } $item->children;
                $rss_feeds{$source}{$url}{'__untouchedcount'} = 0;
                my $url = $data->{link};
                foreach my $key ( keys %$data ) {

                    # XXX this cleanHTML may be the cause of the yahoo failures.
                    $rss_feeds{$source}{$url}{$key} =
                      cleanHTML( $data->{$key} );
                }
            }
        }
    );
}

# emit an RSS headline.
sub send_headline {
    my ( $feed, $target, $url, $title, $description ) = @_;

    next if $url   eq "";
    next if $title eq "";

    if ( length($description) > 512 ) {
        $description = substr( $description, 0, 512 ) . " ...";
    }
    my $uri = URI->new($url);
    shorten(
        $url,
        sub {
            my ($shorty) = @_;

            my $line = $target . ":";
            if ( $shorty eq "" ) {

                # shortening failed for some reason.
                $line .= $url;
            }
            else {
                $line .= "$shorty (" . $uri->host . ")";
            }
            $line .= " :: ";

            #my $tmp = "$title--NADA--$description" ;
            #debug("target: $target");
            #if ($tmp =~ s/(.*)\.+?\s*--NADA--\s*\1/$1 :: ... /) {
            #debug("the RE matched...");
            #} else {
            #debug("the RE did not match...");
            #}
            #$tmp =~ s/ :: \.\.\. $//;
            #debug("temp is '$tmp'");
            #$line .= $tmp;

            $line .= "$title :: $description";
            TLily::Server->active()->cmd_process($line);

            #and, now that we've displayed it, save this fact in the config.
            my @shown = split /\n/, $config->val( $feed, "shown" );
            push @shown, $url;
            save_value( $feed, "shown", join( "\n", @shown ) );
        }
    );
}

# come up with a more efficient way to do this.
sub broadcast_feeds {
    foreach my $feed ( keys %rss_feeds ) {
        foreach my $item ( keys %{ $rss_feeds{$feed} } ) {
            my $story = $rss_feeds{$feed}{$item};
            my @shown = split /\n/, $config->val( $feed, "shown" );
            if ( !grep { $_ eq $item } @shown ) {

                # What discussions does this go to?
                foreach my $disc ( @{ $disc_feed{$feed} } ) {
                    send_headline( $feed, $disc, $story->{link},
                        $story->{title}, $story->{description} );
                }
                return;
            }
        }
    }
}

sub save_value {
    my ( $section, $var, @values ) = @_;
    if ( !$config->setval( $section, $var, @values ) ) {
        $config->AddSection($section);
        $config->newval( $section, $var, @values );
    }
}

### Process stock requests

my $wrapline = 76;    # This is where we wrap lines...

sub get_stock {
    my ( $event, @stock ) = @_;
    my %stock     = ();
    my %purchased = ();
    my $cnt       = 0;
    my $wrap      = 76;
    my @retval;

    if ( $stock[0] =~ /^[\d@.]+$/ ) {
        while (@stock) {
            my $num   = shift @stock;
            my $stock = uc( shift @stock );
            $num =~ /^(\d+)(@([\d.])+)?$/;
            my $shares   = $1;
            my $purchase = $3;
            $stock{$stock}     = $shares;
            $purchased{$stock} = $purchase;

            #push @retval ,"$shares shares of $stock at $purchase";
        }
        @stock = keys %stock;
    }

    my $total = 0;
    my $gain  = 0;

    my $url =
        "http://finance.yahoo.com/d/quotes.csv?s="
      . join( ",", @stock )
      . "&f=sl1d1t1c2v";
    add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {

            my ($response) = @_;

            #return "Quote for @stock failed." unless $response->is_success();
            my @chunks = split( /\n/, $response->{_content} );
            foreach (@chunks) {
                my ( $stock, $value, $date, $time, $change, $volume ) =
                  map { s/^"(.*)"$/$1/; $_ } split( /,/, $_ );
                $change =~ s/^(.*) - (.*)$/$1 ($2)/;
                if (%stock) {
                    my $sub = $value * $stock{$stock};
                    $total += $sub;
                    if ( $purchased{$stock} ) {
                        my $subgain =
                          ( $value - $purchased{$stock} ) * $stock{$stock};
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
"$stock: Last $date $time, $value: Change $change: Vol $volume";
                }
            }

            if ( %stock && @stock > 1 ) {
                if ($gain) {
                    push @retval, "Total gain:  $gain";
                }
                push @retval, "Total value: $total";
            }

            my $retval = "";
            foreach my $tmp (@retval) {
                $tmp = cleanHTML($tmp);

                my $pad = " " x ( $wrap - ( ( length $tmp ) % $wrap ) );
                $retval .= $tmp . $pad;
            }

            $retval =~ s/\s*$//;
            dispatch( $event, $retval );
        }
    );
}

sub wrap {
    my $wrap = 76;
    my $retval;
    foreach my $tmp (@_) {
        my $pad = " " x ( $wrap - ( ( length $tmp ) % $wrap ) );
        $retval .= $tmp . $pad;
    }
    $retval =~ s/\s+$//;
    return $retval;
}

# Provide a mechanism to throttle outgoing HTTP requests.
# These events are queued up and then run - at a very quick interval, but
# not immediately.

my @throttled_events;

sub add_throttled_HTTP {
    my (%options) = @_;

    push @throttled_events, \%options;
}

sub do_throttled_HTTP {
    return unless @throttled_events;
    my $options = shift @throttled_events;
    TLily::Server::HTTP->new(%$options);
}

# Given a URL and a callback, find out the shortened version
# of the URL and pass it to the callback. Or the other thing.

my %shorts;    # briefs?

sub unshorten {
    my ( $short, $callback ) = @_;

    my $url = 'http://metamark.net/api/rest/simple?short_url=' . escape($short);

    add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {

            my ($response) = @_[0];

            my $ans = "";
            if ( $response->{_content} =~ "ERROR" ) {
                $ans = "Pshaw. That's not right, and you know it.";
            }
            else {
                $ans = $response->{_content};
                $ans =~ s/\s//g;
                $ans = "Originally: $ans";
                
            }
            &$callback($ans);
        }
    );
    return;
}

sub shorten {
    my ( $short, $callback ) = @_;

    # If we've already seen this URL, don't bother asking again.
    if ( exists $shorts{$short} ) {
        &$callback( $shorts{$short} );
        return;
    }

    my $original_host = new URI($short)->host();

    my $url = 'http://metamark.net/api/rest/simple?long_url=' . escape($short);

    add_throttled_HTTP(
        url      => $url,
        ui_name  => 'main',
        callback => sub {

            my ($response) = @_[0];

            my $ans = "";
            if ( $response->{_state}{_status} ne "200" ) {
                $ans =
                  "unreachable. (HTTP Status "
                  . $response->{_state}{_status} . ")";
            }
            else {
                # response should be on first line:
                $response->{_content} =~ s/^([^\n]*)//;  
                #$response->{_content} =~ m/(http.*)/;
                $ans = $1;
                #$ans =~ s/\s//g;
                if ($ans) { 
                  $ans .= " [$original_host]";
                  $shorts{$short} = $ans;
                } else {
                  # XXX - this is really not very helpful. 
                  # $ans = "unresolvable, sorry."
                }
            }
            &$callback($ans) if $ans;
        }
    );
    return;
}

# Should find a better place to put this.
$annotation_code{shorten} = {
    CODE => sub {
        my ($event)   = shift;
        my ($shorten) = shift;

        my $start = index($event->{VALUE}, $shorten) + 4; # prefix on send.
        my $end = $start + length($shorten);

        if ($end <= 79 ) {return; } # don't shorten if it fit on one line anyway.
        if ( $shorten !~ m|^http://xrl.us| ) {
            shorten(
                $shorten,
                sub {
                    my ($short_url) = shift;
                    dispatch( $event, "$event->{SOURCE}'s url is $short_url" );
                }
            );
        }
      }
};

=head1 %response

This hash contains all the information for how CJ should respond to 
public, private, and emote sends. The top level keys are the names
of the implemented command. Their values are hashrefs of the following
form:

=over 4

=item RE

A regexp object that is compared to each send of the appropriate type to
see if this is what the user wants.

=item CODE

The perl code that will be execute when the the RE is matched. This callback
is passed the tigerlily event when invoked.

=item TYPE

Listref showing the valid contexts for this command. (public, private, or emote)

=item POS

Integer (-1, 0, 1) indicating the order in which this command should be checked.
Lowest is checked first.

=item HELP

Coderef that will be run when someone asks for help with this handler. See
the help response handler for more details. 

=item STOP

Boolean that indicates whether this command should stop processing of any
other commands. Set to false to run this command B<and> still allow for
later rules to process.

=item DISABLED

Boolean that indicates whether this command should be processed or not.

=item PRIVILEGE

String indicating the level of privilege required to run this command. Three
possible settings: Admin (Must be one of CJ's administrators), and User
(Anyone can make this request.) - If not specified, the default is User.

TODO: Moderator (must moderator/own a discussion the request is on behalf of)

=back

There is no special default handler. You must define one explicitly.
The default behavior is silence, because that's how Priz would
have wanted it.

=cut


my $bibles = {
  "niv"   => {id => 31, name => "New International Version"},
  "nasb"  => {id => 49, name => "New American Standard Bible"},
  "tm"    => {id => 65, name => "The Message"},
  "ab"    => {id => 45, name => "Amplified Bible"},
  "nlt"   => {id => 51, name => "New Living Translation"},
  "kjv"   => {id =>  9, name => "King James Version"},
  "esv"   => {id => 47, name => "English Standard Version"},
  "cev"   => {id => 46, name => "Contemporary English Version"},
  "nkjv"  => {id => 50, name => "New King James Version"},
  "21kjv" => {id => 48, name => "21st Century King James Version"},
  "asv"   => {id =>  8, name => "American Standard Version"},
  "ylt"   => {id => 15, name => "Young's Literal Translation"},
  "dt"    => {id => 16, name => "Darby Translation"},
  "nlv"   => {id => 74, name => "New Life Version"},
  "hcsb"  => {id => 77, name => "Holman Christian Standard Bible"},
  "wnt"   => {id => 53, name => "Wycliffe New Testament"},
  "we"    => {id => 73, name => "Worldwide English (New Testament)"},
  "nivuk" => {id => 64, name => "New International Version - UK"},
  "tniv"  => {id => 72, name => "Today's New International Version"},
};

$response{bible} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        my $bible    = $1;
        my $term     = escape $2;

        $bible = "kjv" unless $bible;
        $bible = $bibles->{$bible}->{id};

        my $url      =
            "http://www.biblegateway.com/passage/?search=$term&version=$bible";
        # nine is king james
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $passage = 
                  scrape_bible( $term, $response->{_content} );
                if ($passage)
                {
                    dispatch( $event, $passage) ;
                }
                # silently fail 
            }
        );
        return;
    },

    HELP => sub { 
        my $help = "Quote chapter and verse. Syntax: bible or passage, followed by an optional bible version, and then the name of the book and chapter:verse. Possible translations include: ";
        foreach my $key (keys %$bibles) {
            $help .= $key . " {" . $bibles->{$key}->{name} . "} ";
        }
        return $help;
    },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\b(?:bible|passage)\s*(niv|nasb|tm|ab|nlt|kjv|esv|cev|nkjv|21kjv|asv|ylt|dt|nlv|hcsb|wnt|we|nivuk|tniv)?\s+(.*\d+:\d+)/i,
};

$response{weather} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( $args !~ m/weather\s*(.*)\s*$/i ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term = $1;
        $term =~ s/\?$//; #XXX add this to RE above...
        $term     = escape $term;
        my $url      =
            "http://mobile.wunderground.com/cgi-bin/findweather/getForecast?brand=mobile&query=$term";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $conditions = 
                  scrape_weather( $term, $response->{_content} );
                if ($conditions )
                {
                    dispatch( $event, $conditions) ;
                }
                else
                {
                    $term = unescape($term);
                    if (length($term) > 10) {
                        $term  = substr($term,0,7);
                        $term .= '...';
                    }
                    dispatch( $event, "Can't find weather for '$term'.");
                }
            }
        );
        return;
    },
    HELP => sub { return "Given a location, get the current weather." },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bweather\b/i

};
$response{forecast} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( $args !~ m/forecast\s*(.*)\s*$/i ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term = $1;
        $term =~ s/\?$//; #XXX add this to RE above...
        $term     = escape $term;
        my $url      =
            "http://mobile.wunderground.com/cgi-bin/findweather/getForecast?brand=mobile&query=$term";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $conditions = 
                  scrape_forecast( $term, $response->{_content} );
                if ($conditions )
                {
                    dispatch( $event, $conditions) ;
                }
                else
                {
                    $term = unescape($term);
                    if (length($term) > 10) {
                        $term  = substr($term,0,7);
                        $term .= '...';
                    }
                    dispatch( $event, "Can't find forecast for '$term'.");
                }
            }
        );
        return;
    },
    HELP => sub { return "Given a location, get the weather forecast." },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bforecast\b/i
};

$response{engrish} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( $args !~ m/engrish*\s*(.*)\s*$/i ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term     = escape $1;
        my $language = "nl";
        my $url      =
          "http://babelfish.altavista.com/tr?trtext=$term&lp=en_$language";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $xlated =
                  escape scrape_translate( $term, $response->{_content} );

                my $url =
"http://babelfish.altavista.com/tr?trtext=$xlated&lp=$language"
                  . "_en";
                add_throttled_HTTP(
                    url      => $url,
                    ui_name  => 'main',
                    callback => sub {
                        my ($response) = @_;
                        my $engrish =
                          scrape_translate( $term, $response->{_content} );
                        dispatch( $event, $engrish );
                    }
                );
            }
        );
        return;
    },
    HELP => sub { return "Given an english phrase, botch it." },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bengrish\b/i
};

my %languages = (
    english    => 'en',
    german     => 'de',
    dutch      => 'nl',
    french     => 'fr',
    greek      => 'el',
    italian    => 'it',
    portuguese => 'pt',
    spanish    => 'es',
);

sub get_lang {
    my $guess = lc shift;

    $guess =~ s/^\s+//;
    $guess =~ s/\s+$//;

    if ( exists $languages{$guess} ) {
        return $languages{$guess};
    }
    if ( grep { $_ eq $guess } ( values %languages ) ) {
        return $guess;
    }
    return;
}

my $default_language = "English";
my $translateRE      = qr/
  (?:
  \b translate \s+ (.*) \s+ from      \s+ (.*) \s+ (?:in)?to \s+ (.*) |
  \b translate \s+ (.*) \s+ (?:in)?to \s+ (.*) \s+ from      \s+ (.*) |
  \b translate \s+ (.*) \s+ from      \s+ (.*)                        |
  \b translate \s+ (.*) \s+ (?:in)?to \s+ (.*)
  )
  \s* $
/ix;

$response{translate} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        $args =~ $translateRE;

        my ( $term, $guess_from, $guess_to );
        if ($1) {
            ( $term, $guess_from, $guess_to ) = ( $1, $2, $3 );
        }
        elsif ($4) {
            ( $term, $guess_from, $guess_to ) = ( $4, $5, $6 );
        }
        elsif ($7) {
            ( $term, $guess_from, $guess_to ) = ( $7, $8, $default_language );
        }
        elsif ($9) {
            ( $term, $guess_from, $guess_to ) = ( $9, $default_language, $10 );
        }
        $term = escape $term;
        my $from = get_lang($guess_from);
        if ( !$from ) {
            dispatch( $event, "I don't speak $guess_from" );
            return;
        }
        my $to = get_lang($guess_to);
        if ( !$to ) {
            dispatch( $event, "I don't speak $guess_to" );
            return;
        }
        my $url =
          "http://babelfish.altavista.com/tr?trtext=$term&lp=${from}_${to}";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $xlated = scrape_translate( $term, $response->{_content} );
                if ($xlated) {
                    dispatch( $event, $xlated );
                }
                else {
                    dispatch( $event, "Apparently I can't do that." );
                }
            }
        );
        return;
    },
    HELP => sub {
        return
"for example, 'translate some text from english to german' (valid languages: "
          . join( ", ", keys %languages )
          . ") (either the from or to is optional, and defaults to $default_language)";
    },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => $translateRE,
};

my $anagramRE      = qr/
  (?:
  \b anagram \s+ (.*) \s+ with    \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*)
  )
  \s* $
/ix;

$response{anagram} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};

        $args =~ $anagramRE;
        my ($term, $include, $exclude);
        my  $url = 
        "http://wordsmith.org/anagram/anagram.cgi?language=english" ;
 
        if ($1) {
          ( $term, $include, $exclude) = ( $1, $2, $3) ;
        } elsif ($4) { 
          ( $term, $exclude, $include) = ( $4, $5, $6) ;
        } elsif ($7) { 
          ( $term, $include) = ( $7, $8 );
        } elsif ($9) { 
          ( $term, $exclude) = ( $9, $10 );
        } else { 
          ( $term ) = ( $11 );
        }
        $url .= "&anagram=" . escape ($term); 
        if ($include) {
            $url .= "&include=" . escape ($include);
        }
        if ($exclude) {
            $url .= "&exclude=" . escape ($exclude);
        }
        

        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                my $anagram = scrape_anagram( $term, $response->{_content} );
                if ($anagram) {
                    dispatch( $event, $anagram );
                }
                else {
                    dispatch( $event, "That's unanagrammaticatable!" );
                }
            }
        );
        return;
    },
    HELP => sub {
        return
 "given a phrase, return an anagram of it.";
    },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => $anagramRE,
};

my $convertRE      = qr/
  (?:
  \b convert \s+ (\d+ .? \d+?)? \s* ([a-z]*) \s+ (?:(?:in)?to \s+)? ([a-z]*)
  )
/ix;

$response{convert} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};

        my ($from, $to, $count);
        if ($2)  {
          ($count, $from, $to ) = ($1, $2, $3);
          $count = 1 unless defined ($count);
        }

        # should be safe, only alpha units are allowed
        my $units_output = `units $from $to`;
        if ($units_output =~ m/(conformbility error)/ ) {
          return $1;
        } elsif ($units_output =~ m/(unknown unit '[a-z]*')/i ) {
          return $1
        }
        $units_output =~ s/\n.*//smx;
        $a = eval "$count $units_output";
        return "$a $to";
    },
    HELP => sub {
        return "convert units: convert (amount) from_units to_units ";
    },
    TYPE => [qw/private public emote/],
    POS  => '1',
    STOP => 1,
    RE   => $convertRE,
};

my $mathRE = qr{^([+*/\d\s().-]*)\??$};

$response{math} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        $args =~ $mathRE;
        my $term = $1;

        my $result = eval $term; # see RE above, must be math-safe.
        if ($@) { 
            if ($event->{type} eq "private") {
                return "that looked mathy, but it isn't." 
            } else {
                return;
            }
        }
	return $result;
    },
    HELP => sub {
        return "math stuff";
    },
    TYPE => [qw/private/],
    POS  => '1',
    STOP => 1,
    RE   => $mathRE,
};

$response{shorten} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/shorten*\s*(.*)\s*$/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        my $shorten = $1;
        if ( $shorten =~ m|^http://xrl.us/(.*)| ) {
            unshorten( $1, sub { dispatch( $event, shift ) } );
        }
        else {
            shorten( $shorten, sub { dispatch( $event, shift ) } );
        }
        return "";
    },
    HELP => sub {
        return "Given a URL, return an xrl.us shortened version of the url. Or, vice versa.";
    },
    TYPE => [qw/private/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bshorten\b/i
};

$response{help} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/help\s*(.*)\s*$/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        if ( $args eq "" ) {

            # XXX respect PRIVILEGE
            my @cmds =
              sort grep { !$response{$_}->{DISABLED} }
              grep { $_ ne "help" } keys %response;
            return
"Hello. I'm a bot. Try 'help' followed by one of the following for more information: "
              . join( ", ", @cmds )
              . ". In general, commands can appear anywhere in private sends, but must begin public sends.";
        }
        if ( exists ${response}{$args} ) {
            return &{ $response{$args}{HELP} }();
        }
        return "ERROR: \'$args\' , unknown help topic.";
    },
    HELP => sub { return "You're kidding, right?"; },
    TYPE => [qw/private/],
    POS  => '-2',
    STOP => 1,
    RE   => qr/\bhelp\b/i,
};

my $year  = qr/\d{4}/;
my $month = qr/(?:[1-9]|10|11|12)/;

$response{cal} = {
    CODE => sub {
        my ($event) = @_;
        my ($args)  = $event->{VALUE};
        my $retval;

        if ( $args =~ m/cal\s+($month)\s+($year)/i ) {
            $retval = `cal $1 $2 2>&1`;
        }
        elsif ( $args =~ m/cal\s+($year)/i ) {
            $retval =
"A fine year. Nice vintage. Too much output, though, pick a month.";
        }
        elsif ( $args =~ m/\bcal\s*$/ ) {
            $retval = `cal 2>&1`;
        }
        else {
            $retval = "I can't find my watch.";
        }
        return wrap( split( /\n/, $retval ) );
    },
    HELP => sub { return "like the unix command"; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\bcal\b/i,
};

$response{"unset"} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/\bunset\s+(.*)$/$1/ ) ) {
            return "ERROR: Expected RE not matched!";
        }

        my $handle = $event->{SHANDLE};
        my $key    = $handle . "-" . $args;

        if ( exists $prefs{$key} ) {
            delete $prefs{$key};
            return "$args is now unset";
        }
        else {
            return "ERROR: invalid variable: $args";
        }
    },
    HELP => sub { return "Purpose: provide a way to undo \"set\""; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr(\bunset\b)i,
};

$response{"poll"} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/\bpoll\s?(.*)\s*$/$1/ ) ) {
            return "ERROR: Expected RE not matched!";
        }
        $args =~ s/^\s+//;
        $args =~ s/\s+$//;
        my @args = split( /\s+/, $args, 2 );

        my $handle = $event->{SHANDLE};

        # This should be configable.
        my %polls = (
            "pres"  => "2000 Presidential Campaign",
            "ny"    => "2000 NYS Senate Campaign",
            "spice" => "Your Favourite Spice Girl"
        );

        if ( scalar @args == 0 ) {
            my @tmp;
            foreach my $key ( keys %polls ) {
                push @tmp, $key . ", \'" . $polls{$key} . "\'";
            }
            return "The currently available polls are: " . join( "; ", @tmp );
        }
        elsif ( scalar @args == 1 ) {
            if ( exists $polls{ $args[0] } ) {

                # Get the current tally:
                my %results;
                my @list = grep /-\-*poll-/,  ( keys %prefs );
                foreach my $key ( @list ) {
                    $results{ lc $prefs{$key} }++ if $key =~ /$args[0]$/;
                }
                my $key = $handle . "-*poll-" . $args[0];

                my $personal = "You have not voted in this poll.";
                if ( exists $prefs{$key} ) {
                    $personal = "You voted for '" . $prefs{$key} . "'";
                }
                return "Results: " . join(
                    ", ",
                    map {
                        $_ . ": "
                          . $results{$_} . " vote"
                          . ( ( $results{$_} == 1 ) ? "" : "s" )
                      } ( keys %results )
                  )
                  . ". "
                  . $personal;
            }
            else {
                return $args[0] . " is not an active poll";
            }
        }
        elsif ( scalar @args == 2 ) {
            if ( exists $polls{ $args[0] } ) {
                $prefs{ $handle . "-*poll-" . $args[0] } = $args[1];
                return "Your ballot has been cast.";
            }
            else {
                return $args[0] . " is not an active poll";
            }
        }
        else {
            return "ERROR: Expected RE not matched!";
        }
    },
    HELP => sub {
        return
"Similar to /vote. By itself, list current polls. given a poll name, return the current results. You can also specify a value to cast your ballot. Usage: poll [<poll> [<vote>]]";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr(\bpoll\b)i,
};

$response{"set"} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/\bset(.*)$/$1/ ) ) {
            return "ERROR: Expected RE not matched!";
        }
        my @args = split( ' ', $args, 2 );

        my $section = "user $event->{SHANDLE}";

        if ( ! @args ) {
            my @tmp; 
            foreach my $key ($config->Parameters($section))
            {
                my $val = $config->val($section,$key);
                push @tmp,  $key . " = \'" . $val . "\'";
            }
            return join( ", ", @tmp );
        }
        elsif ( scalar @args == 1 ) {
            my $val = $config->val($section,$args[0]);
            return (defined($val)? "\"$val\"":"undef");
        }
        else
        {
            my $key = shift @args;
            my $val = join(" ",@args);
            if ( $key =~ m:^\*: ) {
                return "You may not modify " . $key . " directly.";
            }
            $config->setval($section,$key,$val);
            return $key . " = \'" . $val . "\'";
        }
    },
    HELP => sub {
        return
"Purpose: provide a generic mechanism for preference management. Usage: set [ <var> [ <value> ] ]. Only works in private. I should really limit what data can be set here. Also, we use your SHANDLE via SLCP, in violation of the geneva convention.";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr(\bset\b)i,
};

my $min  = 60;
my $hour = $min * 60;
my $day  = $hour * 24;

sub humanTime {
    my $seconds = shift;

    my ( @result, $chunk );
    if ( $seconds >= $day ) {
        $chunk = int( $seconds / $day );
        push @result, $chunk . " days";
        $seconds -= ( $chunk * $day );
    }
    if ( $seconds >= $hour ) {
        $chunk = int( $seconds / $hour );
        push @result, $chunk . " hours";
        $seconds -= ( $chunk * $hour );
    }
    if ( $seconds >= $min ) {
        $chunk = int( $seconds / $min );
        push @result, $chunk . " minutes";
        $seconds -= ( $chunk * $min );
    }
    if ($seconds) {
        push @result, $seconds . " seconds";
    }

    return ( join( ", ", @result ) );
}

$response{"ping"} = {
    CODE => sub {
        my $a = cleanHTML( Dumper( \%served ) );
        $a =~ s/\$VAR1 =/ number of commands and messages processed: /;
        return "pong. uptime: " . humanTime( time() - $uptime ) . "; $a";
    },
    HELP =>
      sub { return "Yes, I'm alive. And have some stats while you're at it."; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/ping/i,
};

$response{"stomach pump"} = {
    CODE => sub {
        return "Eeeek!";
    },
    HELP => sub { return "stomach pumps scare me."; },
    TYPE => [qw/private public emote/],
    POS  => '0',
    STOP => 1,
    RE   => qr/stomach pump/i,
};

$response{cmd} = {
    PRIVILEGE => "admin",
    CODE      => sub {
        my ($event) = @_;
        ( my $cmd = $event->{VALUE} ) =~ s/.*\bcmd\b\s*(.*)/$1/;
        asAdmin(
            $event,
            sub {
                my @response;
                TLily::Server->active()->cmd_process(
                    $cmd,
                    sub {
                        my ($newevent) = @_;
                        $newevent->{NOTIFY} = 0;
                        return if ( $newevent->{type} eq "begincmd" );
                        if ( $newevent->{type} eq "endcmd" ) {
                            dispatch( $event, wrap(@response) );
                        }
                        if ( $newevent->{text} ne "" ) {
                            push @response, $newevent->{text};
                        }
                    }
                );
            }
        );
    },
    HELP => sub {
        return
          "If you are a cj admin, you can use this command to boss me around.";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\bcmd\b/i,
};

$response{buzz} = {
    CODE => sub {
        my ($event) = @_;
        my @tmp;
        foreach ( 1 .. 3 ) {
            push @tmp, pickRandom($buzzwords);
        }
        return join( " ", @tmp ) . "!";
    },
    HELP =>
      sub { return "random buzzword generator. Active with keyword \"buzz\""; },
    TYPE => [qw/private/],
    POS  => '1',
    STOP => 1,
    RE   => qr/\bbuzz\b/i,
};

$response{stock} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/stock\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        else {
            get_stock( $event, split( /[, ]+/, $args ) );
            return "";
        }
    },
    HELP => sub {
        return
"Give a list of ticker symbols, I'll be your web proxy to finance.yahoo.com";
    },
    TYPE => [qw/private public emote/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\bstock\b/i,
};

$response{drink} = {
    CODE     => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( $args =~ m/slides a\b(.*)\bdown the bar to CJ\b/ ) {
            my $cmd = "/drink $1";
            TLily::Server->active()
              ->cmd_process( $cmd, sub { $_[0]->{NOTIFY} = 0; } );
        }
        return q{};
    },
    HELP => sub { return "slide me a drink, I'm game."; },
    TYPE => [qw/emote/],
    POS  => '0',
    STOP => 1,
    RE => qr/down the bar/i,
};

$response{kibo} = {
    CODE => sub {
        my ($event) = @_;
        my $list = $sayings;
        if ( $event->{RECIPS} eq "unified" ) {
            $list = [ (@$unified) x 2, @$list ];
        }
        elsif ( $event->{RECIPS} eq "beener" ) {
            $list = [ (@$beener) x 2, @$list ];
        }
        my ($message) = sprintf( pickRandom($list), $event->{SOURCE} );
        return $message;
    },
    HELP => sub { return "I respond to public questions addressed to me."; },
    TYPE => [qw/public emote/],
    POS  => '1',
    STOP => 1,
    RE   => qr/\b$name\b.*\?/i,
};

$response{eliza} = {
    CODE => sub {
        my ($event) = @_;
        return $eliza->transform( $event->{VALUE} );
    },
    HELP => sub {
        return
"I've been doing some research into psychotherapy, I'd be glad to help you work through your agression.";
    },
    TYPE => ["private"],
    POS  => '2',
    STOP => 1,
    RE   => qr/.*/,
};

sub scrape_weather {
    my ( $term, $content ) = @_;

    $content =~ m/(Updated:.*)Current Radar/s;
    my @results = map {cleanHTML($_)} split(/<tr>/, $1);
    return wrap(@results);
}

sub scrape_forecast {
    my ( $term, $content ) = @_;

    $content =~ m/(Forecast as of .*)Units:/s;
    my @results = map {cleanHTML($_), ""} split(/<b>/, $1);
    pop @results; # remove trailing empty line.
    @results = @results[0..10]; # limit responses. 5 days, 1 header, 5 blanks
    return wrap(@results);
}

sub scrape_bible {
    my ( $term, $content ) = @_;

    $content =~ m{result-text-style-normal"(.*)<div id="result-options-info2}sm;
    return cleanHTML($1);
}

sub scrape_horoscope {
    my ( $term, $content, $type ) = @_;

    $content =~ m/<big class="yastshsign">([^<]*)<\/big>/i;
    my $sign = $1;

    if ($type eq "chinese") {
        $content =~ m:<small>Year In General(.*)Previous Day</a>:s;
        my $reading = $1;
        return cleanHTML("$sign : $reading");
    }
    else
    {
        $content =~ m/<span class="yastshdate">([^<]*)<\/span>/i;
        my $dates = $1;
        $content =~ m/<b class="yastshdotxt">Overview:<\/b><br>([^<]*)<\/td>/;
        my $reading = $1;
        return cleanHTML("$sign ($dates): $reading");
    }

}

sub scrape_anagram{
    my ( $term, $content ) = @_;

    if ( $content =~
        m{<PRE>([^<]*)</PRE>}i )
    {
        my @results = grep {$_ ne '' && lc $_ ne $term} split /\n/, $1;
        return unless @results;
        return pickRandom( [@results]);
    }
    else {
        return;
    }
}

sub scrape_translate {
    my ( $term, $content ) = @_;

    #my $joe = $content;
#$joe =~ s{\n}{\\n}xgms;
    #TLily::Server->active()->cmd_process( "Coke:$joe" );

    if ( $content =~
        m{<td bgcolor=white class=s><div style=padding:10px;>([^<]*)</div></td>}i )
    {
        return cleanHTML($1);
    }
    else {
        return "";
    }
}

sub scrape_wiktionary {
    my ( $term, $content ) = @_;

    if ( $content =~ m/Wiktionary does not have an entry for this exact word/ ||
         $content =~ m/Sorry, there were no exact matches to your query/ ) {
      return;
    }

    my ($lookup, @retval);

    $content =~ s/\n/ /g;

    $content =~ s/.*<a name="English" id="English">//;

    my $skip;
    foreach my $chunk (split /<span class="mw-headline">/sm, $content) {
      my ($m,$n) = split (/<\/span>/, $chunk);
      $m = cleanHTML($m);
      $n = cleanHTML($n);
      $m =~ s/^\s+//;
      $m =~ s/\s*\[\s*edit\s*\]//;
      next unless $m;
      $n =~ s/\s*\[\s*edit\s*\]//;
      next unless $n;
      next if lc $m eq 'derived terms';
      next if lc $m eq 'english';
      next if lc $m eq 'pronunciation';
      next if lc $m eq 'translations';
      next if lc $m eq 'translations to be checked';
      $chunk = $m . ' :: ' . $n;
      push @retval, $chunk;
    }

    unshift @retval, "According to Wiktionary:";
    return wrap(@retval);

}

sub scrape_google_guess {
    my $term = shift;
    my $content = shift;

    my ($lookup, @retval);

    $content =~ s/\n/ /g;
    if ($content =~ m{Did you mean.*<i>([^>]+)</i>}) { 
      return "No match for '$term', did you mean: '$1'?";
    }
    return;
} 
sub scrape_webster {
    my ( $term, $content ) = @_;

    if ( $content =~ /The word you've entered isn't in the dictionary/ ) {
        return "Could find no definition for '$term'";
    }

    # Was there more than one match?
    my ( @see_also, @other_forms );
    if ( $content =~ /(\d+) words found/ ) {

        # all the words will appear in a dropdown, get the options.

        my @options = grep { /^<option.*>(.*)$/ } split( /\n/, $content );

        foreach my $option (@options) {
            $option =~ s/<option.*>//;
            ( my $tmp = $option ) =~ s/\[.*\]//g;
            if ( $tmp eq $term ) {

                # we get the first term for free already...
                my $blah = quotemeta "[1,";
                if ( $option !~ /$blah/ ) {
                    push @other_forms, $option;
                }
            }
            else {
                push @see_also, $option;
            }
        }
    }

    # process the main form.
    ( my $retval = cleanHTML($content) ) =~
      s/^.*Main Entry: (.*)Get the Top 10.*/$1/;
    $retval =~ s/For More Information on ".*//;

    # Is there another form of the same name?

    if (0) {

        # XXX This needs to be converted to add_throttled_http...

        if ( scalar(@other_forms) >= 1 ) {

#Need to figure out the magic incation to get the secondary data...
#http://www.m-w.com/cgi-bin/dictionary?hdwd=murder&jump=a&list=a=700349
#<input type=hidden name=list value="murder[1,noun]=700416;murder[2,verb]=700439;bloody murder=109479;self-murder=972362">

            $content =~ /<input type=hidden name=list value="(.*)">/;
            my $list = $1;

            foreach my $other_term (@other_forms) {
                my $sub_url =
                    "http://www.m-w.com/cgi-bin/dictionary?hdwd=" . $term
                  . "&jump="
                  . $other_term
                  . "&list="
                  . $list;

#my $sub_response = $ua->request(HTTP::Request->new(GET => $sub_url));
#if ($sub_response->is_success) {
#($sub_content= cleanHTML($sub_response->content)) =~ s/^.*Main Entry: (.*)Get the Top 10.*/$1/;
#$retval .= "; " . $sub_content;
#}
            }
        }

    }

    # tack on any other items that turned up on the main list, for kicks.
    if ( scalar(@see_also) ) {
        $retval .= "| SEE ALSO: " . join( ", ", @see_also );
    }
    return "According to Webster: " . $retval;

}

sub scrape_bacon {
    my ($content) = shift;

    if ( $content =~ /cannot find/ ) {
        $content =~ s/.*?(The Oracle cannot find)/\1/sm;
        $content =~ s/Arnie.*//sm;
        return cleanHTML($content);
    }

    $content =~ s/.*?The Oracle of Bacon at Virginia//s;
    $content =~ s/.*?The Oracle of Bacon at Virginia//s;

    if ( $content =~ /infinity/ ) {
        $content =~ s/(infinity).*/$1/s;
    }
    else {
        $content =~ s/<br>/;/g;
        $content =~ s/(Kevin Bacon).*/$1/s;
    }
    return cleanHTML($content);
}

$response{bacon} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ m/\bbacon*\s*(.*)\s*$/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term = $1;
        if (lc($term) eq "kevin bacon") {
            dispatch($event,"Are you congenitally insane or irretrievably stupid?");
            return;
        }
        if ($term =~ m/ \s* (\w+) \s+ (\w+) \s+ \(([ivxlcm]*)\) /smix) {
            $term = "$2, $1 ($3)";
        }

        $term = escape($term);
        my $url  =
"http://oracleofbacon.org/cgi-bin/oracle/movielinks?firstname=Bacon%2C+Kevin&game=1&secondname="
          . $term;
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                dispatch( $event, scrape_bacon( $response->{_content} ) );
            }
        );
        "";
    },
    HELP => sub {
        return "Find someone's bacon number using http://oracleofbacon.org/";
    },
    TYPE => [qw/private/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/bacon/i,
};

my $horoscopeRE = qr( \b
    horoscope \s+ (?: for \s+)? 
    (?:
    (
      aries | leo | sagittarius | taurus | virgo | capricorn | gemini |
      libra | aquarius | cancer | scorpio | pisces | ophiuchus
    )  |
    (
      rat | ox | goat | dragon | rabbit | monkey | dog | pig | snake | 
      tiger | rooster | horse
    )
    )
\b )xi;

$response{horoscope} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        my ($term, $url, $type);

        #XXX this should be done in the handler caller, not the handler itself.
        $args =~ $horoscopeRE;

        if ($1)
        {
            $term = $1;
            if (lc($term) eq "ophiuchus") {
                # support those unlucky enough to be in this sign.
                $term = "sagittarius";
            }
            $url  =
              "http://astrology.yahoo.com/astrology/general/dailyoverview/";
            $type = "western";
        }
        else 
        {
            $term = $2;
            $url  =
              "http://astrology.yahoo.com/chinese/general/dailyoverview/";
            $type = "chinese";
        }

        $term = lc $term;
        $url = $url . $term;
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {
                my ($response) = @_;
                dispatch( $event,
                    scrape_horoscope( $term, $response->{_content}, $type ) );
            }
        );
        "";    #muahaah
    },
    HELP => sub { return "ask me about your sign to get a daily horoscope. We speak chinese. (Usage: horoscope [for] sign)"; },
    TYPE => [qw/private public emote/],
    POS  => '-1',
    STOP => 1,
    RE   => $horoscopeRE,
};

$response{define2} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ m/define2*\s*(.*)\s*$/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term = escape $1;
        my $url  = "http://en.wiktionary.org/w/index.php?printable=yes&title=$term";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {

                my ($response) = shift;
                my $answer = scrape_wiktionary( $term, $response->{_content});  
                if ($answer) {
                  dispatch( $event,$answer);
                } else  {
                  my $url2 = "http://www.google.com/search?num=0&hl=en&lr=&as_qdr=all&q=$term&btnG=Search";
                  add_throttled_HTTP(
                      url      =>  $url2,
                      ui_name  => 'main',
                      callback => sub {
                          my ($response2) = shift;
                          $answer= scrape_google_guess( $term, $response2->{_content} );
			if ($answer) {
                          dispatch( $event, $answer);
                        } else {
                          dispatch( $event, "Sorry, '$term' not found");
                        }
                      }
                  );
                }
            }
        );
        "";    #muahaah
    },
    HELP => sub { return "Look up a word on wiktionary.org/en"; },
    TYPE => [qw/private/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bdefine2\b/i
};

$response{define} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ m/define*\s*(.*)\s*$/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        my $term = $1;
        my $url  = "http://www.m-w.com/cgi-bin/dictionary?$term";
        add_throttled_HTTP(
            url      => $url,
            ui_name  => 'main',
            callback => sub {

                my ($response) = @_;
                dispatch( $event,
                    scrape_webster( $term, $response->{_content} ) );
            }
        );
        "";    #muahaah
    },
    HELP => sub { return "Look up a word on m-w.com"; },
    TYPE => [qw/private/],
    POS  => '-1',
    STOP => 1,
    RE   => qr/\bdefine\b/i
};

$response{foldoc} = {
    DISABLED => 1,
    CODE     => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*foldoc\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        add_throttled_HTTP(
            url => 'http://www.nightflight.com/foldoc-bin/foldoc.cgi?query='
              . $args,
            host     => 'www.nightflight.com',
            ui_name  => 'main',
            protocol => 'http',
            callback => sub {

                my ($response) = @_;

                my $tmp =
                  cleanHTML( ( split( "</FORM>", $response->{_content} ) )[0] );

                if ( $tmp =~ /No match for/ ) {
                    dispatch( $event, "No match, sorry" );
                    return "";
                }
                else {

                    #dispatch($event,"a match, sorry");
                }

                my @chunks = split( "<HR>", $response->{_content} );

                if ( scalar(@chunks) == 3 ) {
                    my $tmp =
                      cleanHTML( ( split( "</FORM>", $chunks[0] ) )[1] );
                    $tmp =~ s/Try this search on OneLook \/ Google//;

                    dispatch( $event, "According to FOLDOC: " . $tmp );
                }
                else {
                    dispatch( $event, "foldoc: Screen Scrape failed!" );
                }
            }
        );
        return;
    },
    HELP => sub {
        return "Define things from the Free Online Dictionary of Computing";
    },
    TYPE => [qw/private public emote/],
    POS  => '0',
    STOP => 1,
    RE   => qr/foldoc/i,
};

$response{lynx} = {
    DISABLED => 1,
    CODE     => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*lynx\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        add_throttled_HTTP(
            url      => $args,
            host     => 'www.cnn.com',
            ui_name  => 'main',
            protocol => 'http',
            callback => sub {

                my ($response) = @_;
                my $message;

         #$message = "keys: ". (join " ", (keys %$response));
         #$message = "status keys: ". (join " ", (keys %{$response->{_state}}));
                $message = "status: " . $response->{_state}{_msg};
                $message .= " url: " . $response->{url};
                $message .= " size: " . length( $response->{_content} );

                #$response->{_content} =~ s/\s+/ /g;
                #$message = "content: ". $response->{_content};
                dispatch( $event, $message );
            }
        );
        return;
    },
    HELP => sub { return "trying to find a nice way to suck down web pages."; },
    TYPE => [qw/private public emote/],
    POS  => '0',
    STOP => 1,
    RE   => qr/lynx/i,
};

my @ascii =
  qw/NUL SOH STX ETX EOT ENQ ACK BEL BS HT LF VT FF CR SO SI DLE DC1 DC2 DC3 DC4 NAK SYN ETB CAN EM SUB ESC FS GS RS US SPACE/;
my %ascii;

for my $cnt ( 0 .. $#ascii ) {
    $ascii{ $ascii[$cnt] } = $cnt;
}
$ascii{DEL} = 0x7f;

sub format_ascii {
    my $val = @_[0];

    my $format = "%s => %d (dec); 0x%x (hex); 0%o (oct)";

    if ( $val < 0 || $val > 255 ) {
        return "Ascii is 7 bit, silly!";
    }
    my $chr = "'" . chr($val) . "'";

    my $control = "";
    if ( $val >= 1 && $val <= 26 ) {
        $control = "; control-" . chr( $val + ord('A') - 1 );
    }

    if ( $val < $#ascii ) {
        $chr = $ascii[$val];
    }

    if ( $val == 0x7f ) {
        $chr = "DEL";
    }

    return sprintf( $format, $chr, $val, $val, $val ) . $control;
}

$response{rot13} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*rot13\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }

        $args =~ tr/[A-Za-z]/[N-ZA-Mn-za-m]/;

        return $args;
    },
    HELP => sub { return "Usage: rot13 <val>"; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\brot13\b/i,
};

$response{urldecode} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*urldecode\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }

        return unescape $args;
    },
    HELP => sub { return "Usage: urldecode <val>"; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\burldecode\b/i,
};

$response{urlencode} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*urlencode\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }

        return escape $args;
    },
    HELP => sub { return "Usage: urlencode <val>"; },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\burlencode\b/i,
};

$response{ascii} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*ascii\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        if ( $args =~ m/^'(.)'$/ ) {
            return format_ascii( ord($1) );
        }
        elsif ( $args =~ m/^0[Xx][0-9A-Fa-f]+$/ ) {
            return format_ascii( oct($args) );
        }
        elsif ( $args =~ m/^0[0-7]+$/ ) {
            return format_ascii( oct($args) );
        }
        elsif ( $args =~ m/^[1-9]\d*$/ ) {
            return format_ascii($args);
        }
        elsif ( $args =~ m/^\\[Cc]([A-Z])$/ ) {
            return format_ascii( ord($1) - ord('A') + 1 );
        }
        elsif ( $args =~ m/^\\[Cc]([a-z])$/ ) {
            return format_ascii( ord($1) - ord('a') + 1 );
        }
        elsif ( $args =~ m/^[Cc]-([a-z])$/ ) {
            return format_ascii( ord($1) - ord('a') + 1 );
        }
        elsif ( $args =~ m/^[Cc]-([A-Z])$/ ) {
            return format_ascii( ord($1) - ord('A') + 1 );
        }
        elsif ( exists $ascii{ uc $args } ) {
            return format_ascii( $ascii{ uc $args } );
        }
        else {
            return "Sorry, $args doesn't make any sense to me.";
        }
    },
    HELP => sub {
        return
"Usage: ascii <val>, where val can be a char ('a'), hex (0x1), octal (01), decimal (1) an emacs (C-A) or perl (\\cA) control sequence, or an ASCII control name (SOH).";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\bascii\b/i,
};

$response{country} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*country\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        if ( $args =~ m/^(..)$/ ) {

            my $a = `grep -i '\|$1\$' /Users/cjsrv/CJ/countries.txt`;
            $a =~ m/^([^\|]*)/;
            return $1 unless ( $1 eq "" );
            return "No Match.";
        }
        else {
            my @a =
              split( /\n/, `grep -i \'$args\' /Users/cjsrv/CJ/countries.txt` );
            if ( scalar(@a) > 10 ) {
                return "Your search found "
                  . scalar(@a)
                  . " countries. Be more specific (I can only show you 10).";
            }
            elsif ( scalar(@a) > 0 ) {
                my $tmp = join( "\'; ", @a );
                $tmp =~ s/\|/=\'/g;
                return $tmp . "'";
            }
            else {
                return "Found no matches.";
            }
        }
    },
    HELP => sub {
        return
"Usage: country <val>, where val is either a 2 character country code, or a string to match against possible countries.";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\bcountry\b/i,
};

$response{utf8} = {
    CODE => sub {
        my ($event) = @_;
        my $args = $event->{VALUE};
        if ( !( $args =~ s/.*utf8\s+(.*)/$1/i ) ) {
            return "ERROR: Expected RE not matched!";
        }
        if ( $args =~ m/^[Uu]\+([0-9A-Fa-f]*)$/ ) {
            my $a = `grep -i '^$1\|' /Users/cjsrv/CJ/unicode2.txt`;
            $a =~ s/^[^|]+\|(.*)/$1/;
            return $a;
        }
        else {
            my @a =
              split( /\n/,
                `grep -i \'\|\.\*$args\' /Users/cjsrv/CJ/unicode2.txt` );
            if ( scalar(@a) > 10 ) {
                return "Your search found "
                  . scalar(@a)
                  . " glyphs. Please be more specific.";
            }
            elsif ( scalar(@a) > 0 ) {
                my $tmp = join( "\'; ", @a );
                $tmp =~ s/\|/=\'/g;
                return $tmp . "'";
            }
            else {
                return "Found no matches.";
            }
        }
    },
    HELP => sub {
        return
"Usage: utf8 <val>, where val is either U+<hex> or a string to match against possible characters.";
    },
    TYPE => [qw/private/],
    POS  => '0',
    STOP => 1,
    RE   => qr/\butf8\b/i,
};

# This is already pretty unweidly.
#
sub cleanHTML {

    # join blank lines, remove excess whitespace and kill tags.
    $a = join( " ", @_ );
    $a =~ s/\n/ /;
    $a =~ s/<[^>]*>/ /g;

    # translate some common html-escapes.
    $a =~ s/&lt;/</gi;
    $a =~ s/&gt;/>/gi;
    $a =~ s/&amp;/&/gi;
    $a =~ s/&#46;/./g;
    $a =~ s/&#160;/ /g;
    $a =~ s/&#176;/o/g;
    $a =~ s/&#0?39;/'/g;
    $a =~ s/&quot;/"/ig;
    $a =~ s/&nbsp;/ /ig;
    $a =~ s/&uuml;/u"/ig;

    # translate any utf8 codes to ascii representations:
    # Use Text::Unidecode if it's available...

    # cleanup whitespace.
    $a =~ s/\s+/ /g;
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;

    return $a;
}

sub dispatch {

    my ( $event, $message ) = @_;

    return if ( $message eq "" );

    if ( $event->{type} eq "emote" ) {
        $message = '"' . $message;
    }
    my $line = $event->{_recips} . ":" . $message;
    TLily::Server->active()->cmd_process( $line, sub { $_[0]->{NOTIFY} = 0; } );
}

# keep myself busy.
sub away_event {
    my ( $event, $handler ) = @_;

    if ( $event->{SOURCE} eq $name ) {
        my $line = "/here";
        TLily::Server->active()
          ->cmd_process( $line, sub { $_[0]->{NOTIFY} = 0; } );
    }

}

sub cj_event {
    my ( $event, $handler ) = @_;

    $event->{NOTIFY} = 0;

    # I should never respond to myself. There be dragons!
    #  this is actually an issue with emotes, which automatically
    #  send the message back to the user.
    if ( $event->{SOURCE} eq $name ) {
        return;
    }

    # throttle:
    my $last   = $throttle{ $event->{SOURCE} }{last};
    my $status = $throttle{ $event->{SOURCE} }{status};    #normal(0)|danger(1)
    $throttle{ $event->{SOURCE} }{last} = time;

    if ( ( $throttle{ $event->{SOURCE} }{last} - $last ) < $throttle_interval )
    {

        #TLily::UI->name("main")->print("$event->{SOURCE} tripped throttle!\n");
        $throttle{ $event->{SOURCE} }{count} += 1;
    }
    elsif ( ( $throttle{ $event->{SOURCE} }{last} - $last ) > $throttle_safety )
    {

  #TLily::UI->name("main")->print("$event->{SOURCE} is no longer dangerous!\n");
        $throttle{ $event->{SOURCE} }{count}  = 0;
        $throttle{ $event->{SOURCE} }{status} = 0;
    }

    if ( $throttle{ $event->{SOURCE} }{count} > 3 ) {
        if ($status) {
            ( my $offender = $event->{SOURCE} ) =~ s/\s/_/g;
            TLily::Server->active()->cmd_process( "/ignore $offender all",
                sub { $_[0]->{NOTIFY} = 0; } );
        }
        else {

        #TLily::UI->name("main")->print("$event->{SOURCE} is now dangerous!\n");
            $throttle{ $event->{SOURCE} }{status} = 1;
            $throttle{ $event->{SOURCE} }{count}  = 0;
        }
    }

    if ($status) {
        return;    #They're dangerous. don't talk to them.
    }

    # Who should get a response? If it's private, the sender
    # and all recips. If public/emote, just the recips.

    my @recips = split( /, /, $event->{RECIPS} );
    if ( $event->{type} eq "private" ) {
        push @recips, $event->{SOURCE};
    }
    elsif ( $event->{type} eq "emote" ) {
        if ( $event->{VALUE} =~ /^ . o O \((.*)\)$/ ) {
            $event->{VALUE} = $1;
        }
        elsif ( $event->{VALUE} =~ /^ (asks|says), \"(.*)\"$/ ) {
            $event->{VALUE} = $2;
        }
    }

    @recips = grep { !/^$name$/ } @recips;
    my $recips = join( ",", @recips );
    $recips =~ s/ /_/g;
    $event->{_recips} = $recips;

    # Workhorse for responses:
    my $message = "";
  HANDLE_OUTER: foreach my $order (qw/-2 -1 0 1 2/) {
      HANDLE_INNER: foreach my $handler ( keys %response ) {

            # XXX respect PRIVILEGE
            next if $response{$handler}->{DISABLED};
            if ( $response{$handler}->{POS} eq $order ) {
                next
                  if !grep { /$event->{type}/ } @{ $response{$handler}{TYPE} };
                my $re = $response{$handler}->{RE};
                if ( $event->{type} eq "public" ) {
                    $re = qr/^\s*(?i:$name\s*,?\s*)?$re/;
                } elsif ( $event->{type} eq "emote" ) {
                    $re = qr/(?i:\b$name\s*,?\s*)?$re/;
                }

                if ( $event->{VALUE} =~ m/$re/ ) {
                    $served{ $event->{type} . " messages" }++;
                    $served{$handler}++;
                    $message .= &{ $response{$handler}{CODE} }($event);
                    if ( $response{$handler}->{STOP} ) {
                        last HANDLE_OUTER;
                    }
                }
            }
        }
    }
    dispatch( $event, $message );

    # Handle Discussion Annotations

    #convert our event (by target) into a hash (by type)
    my @targets = split /,/, $event->{_recips};
    my $notations;    # -> type -> {TARGETS => [], VALUES => []}
    foreach my $target (@targets) {
        foreach my $annotation ( keys %{ $disc_annotations{$target} } ) {
            my $RE  = $annotations{$annotation}{RE};
            my $VAL = $event->{VALUE};
            push @{ $notations->{$annotation}->{TARGETS} }, $target;
            next if $notations->{$annotation}->{VALUES};
            while ( $VAL =~ m/$RE/g ) {
                push @{ $notations->{$annotation}->{VALUES} }, $1;
            }
        }
    }
    foreach my $annotation ( keys %{$notations} ) {
        my $ds = $notations->{$annotation};
        next unless $ds->{VALUES};
        my $local_event = $event;
        $local_event->{_recips} = join( ",", @{ $ds->{TARGETS} } );
        foreach my $value ( @{ $ds->{VALUES} } ) {
            &{ $annotation_code{$annotation}{CODE} }( $local_event, $value );
        }
    }

}

#
# Insert event handlers for everything we care about.
#
for (qw/public private emote/) {
    event_r( type => $_, order => 'before', call => \&cj_event );
}
event_r( type => "away", order => 'after', call => \&away_event );

sub load {
    my $server = TLily::Server->active();
    dbmopen( %prefs, "/Users/cjsrv/CJ_prefs.db", 0666 )
      or die "couldn't open DBM file!";
    $config = new Config::IniFiles( -file => $config_file )
      or die @Config::IniFiles::errors;

    foreach my $disc ( $config->GroupMembers("discussion") ) {
        my $discname = $disc;
        $discname =~ s/^discussion //;

        my @feeds = split /\n/, $config->val( $disc, "feeds" );
        foreach my $feed (@feeds) {
            push @{ $disc_feed{"feed $feed"} }, $discname;
        }
        my @annotations = split /\n/, $config->val( $disc, "annotations" );
        foreach my $annotation (@annotations) {
            $disc_annotations{$discname}{$annotation} = 1;
        }

        #my $irc = $config->val($disc,"irc");
        #if (defined($irc)) {
        #$irc{$discname} = $irc;
        #}
    }
    foreach my $annotation ( $config->GroupMembers("annotation") ) {
        my $ann_name = $annotation;
        $ann_name =~ s/^annotation //;
        $annotations{$ann_name}{RE}     = $config->val( $annotation, "regexp" );
        $annotations{$ann_name}{action} = $config->val( $annotation, "action" );
    }

    #foreach my $irc_cxn ($config->GroupMembers("irc")) {
    #my $irc_name = $irc_cxn;
    #$irc_name =~ s/^irc //;
    #my $server = $config->val($irc_cxn,"server");
    #my $port = $config->val($irc_cxn,"port");
    #my $nick = $config->val($irc_cxn,"nick");
    #my $channel= $config->val($irc_cxn,"channel");
    #$irc_cxn{$channel} = $irc_obj->newconn(Nick=>$nick,
    #Server=>$server,
    #Port=>$port,
    #Server=>$server,
    #Ircname => "Lily/IRC Bridge");
    #}
    #TLily::Event::event_r("idle", "after", sub {
    #$irc_obj->do_one_loop() });

    $server->fetch(
        call => sub { my %event = @_; $sayings = $event{text} },
        type   => "memo",
        target => $disc,
        name   => "sayings"
    );
    $server->fetch(
        call => sub { my %event = @_; $overhear = $event{text} },
        type   => "memo",
        target => $disc,
        name   => "overhear"
    );
    $server->fetch(
        call => sub { my %event = @_; $buzzwords = $event{text} },
        type   => "memo",
        target => $disc,
        name   => "buzzwords"
    );
    $server->fetch(
        call => sub { my %event = @_; $unified = $event{text} },
        type   => "memo",
        target => $disc,
        name   => "-unified"
    );
    $server->fetch(
        call => sub { my %event = @_; $beener = $event{text} },
        type   => "memo",
        target => $disc,
        name   => "-beener"
    );

    $every_10m = TLily::Event::time_r(
        call => sub {
            get_feeds();
        },
        interval => 60 * 10
    );
    $every_30s = TLily::Event::time_r(
        call => sub {
            broadcast_feeds();
            checkpoint();
        },
        interval => 60 * .5
    );
    $frequently = TLily::Event::time_r(
        call => sub {
            do_throttled_HTTP();
        },
        interval => 2.0
    );
    TLily::Server->active()->cmd_process("/blurb off");
}

=head2 checkpoint ()

Call this to save our in memory config out, either by saving memos or
writing to our local config file(s).

=cut

sub checkpoint {
    $config->RewriteConfig();
}

=head2 unload ()

Called by tigerlily when you use C<%ext unload cj> - our chance to
release any external resources we have open.

=cut

sub unload {
    dbmclose(%prefs);
    checkpoint();

    TLily::Event->time_u($every_10m);
    TLily::Event->time_u($every_30s);
    TLily::Event->time_u($frequently);
}

1;
