use strict;

use Cwd;
use Symbol 'qualify_to_ref';

use TLily::Server::HTTP;
use URI;
use Config::IniFiles;

use Text::Unidecode;

use LWP::UserAgent;
use LWP::Protocol::https;    # declare dependency, not used directly.

=head1 AUTHOR

Will "Coke" Coleda

=head1 PURPOSE

This extension allows a player (lily user) to act like a bot. It is designed
to run as a standalone user: don't expect to login to lily as yourself and run
this, it will take over your session.

There are two types of output that CJ generates. In both cases, CJ matches
each send against regular expressions, and if a match happens, runs some
code (potentially using information in the send) and posts a response or
a followup.

=over 4

=item * commands

These are always on: if CJ is in a discussion, he will respond if one
of the commands is matched.

=item * annotations

Each discussion can opt in to individual annotations (e.g. url shortening).
These are conditionally enabled or disabled per discussion.

=back

=cut

#########################################################################
%CJ::response;    #Container for all response handlers.
my %throttle;     #Container for all throttling information.

my $throttle_interval = 1;    #seconds
my $throttle_safety   = 5;    #seconds
$CJ::config;                  # Config::Inifiles object.

$CJ::disc = 'cj-admin';       #where we keep our memos.
my $debug_disc = 'cj-admin';
my %disc_annotations
    ;    # A cached copy of which discussions each annotation goes to.
my %annotations;        # A cached copy of what our annotations do.
my %annotation_code;    # ala response, but for annotations.
my $frequently;         # timers

$CJ::uptime = time();   #uptime indicator.
%CJ::served;            #stats.

# we don't expect to be changing our name frequently, cache it.
$CJ::name = TLily::Server->active()->user_name();

$CJ::ua = LWP::UserAgent->new;
$CJ::ua->agent("CJ-bot/1.0");

=head1 Methods

=head2 CJ::debug( @complaints)

Send text to our debug discussion.

=cut

sub CJ::debug {

    # join and split to catch any embedded newlines
    my $args = join( "\n", @_ );
    my @lines = split( /\n/, $args );
    TLily::Server->active()->cmd_process("$debug_disc: $_") for @lines;
}

# XXX use File::*
my $config_file = $ENV{HOME} . '/.lily/tlily/CJ.ini';

=head2 pickRandom( $listref )

Given a ref to a list, return a random element from it.

=cut

sub CJ::pickRandom {
    my @list = @{ $_[0] };
    return $list[ int( rand( scalar(@list) ) ) ];
}

sub CJ::wrap {
    my $wrapline = 76;    # This is where we wrap lines...

    my $retval;
    foreach my $tmp (@_) {
        my $pad = ' ' x ( $wrapline - ( ( length $tmp ) % $wrapline ) );
        $retval .= $tmp . $pad;
    }
    $retval =~ s/\s+$//;
    return $retval;
}

# Provide a mechanism to throttle outgoing HTTP requests.
# These events are queued up and then run - at a very quick interval, but
# not immediately.

my @throttled_events;

sub CJ::add_throttled_HTTP {
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

sub CJ::shorten {
    my ( $short, $callback ) = @_;

    # If we've already seen this URL, don't bother asking again.
    if ( exists $shorts{$short} ) {
        &$callback( $shorts{$short} );
        return;
    }

    # This used to add a throttled HTTP request. now it does it inline
    # This could be bad. TLily::Server::HTTP needs to be updated.

    my $original_host = new URI($short)->host();

    my $url = 'https://www.googleapis.com/urlshortener/v1/url?key='
        . $CJ::config->val( 'googleapi', 'APIkey' );

    my $req = HTTP::Request->new( POST => $url );
    $req->content_type('application/json');
    $req->content(<<"EJSON");
{
longUrl: "$short"
}
EJSON
    my $res = $CJ::ua->request($req);

    if ( $res->is_success ) {
        if ( $res->content =~ /"id": "(.*)",/ ) {
            my $ans = $1 . " [$original_host]";
            &$callback($ans) if $ans;
        }
    }
    else {
        CJ::debug( "shorten failed: " . $res->status_line );
    }

    return;
}

# Should find a better place to put this.
$annotation_code{shorten} = {
    CODE => sub {
        my ($event)   = shift;
        my ($shorten) = shift;

        my $start = index( $event->{VALUE}, $shorten ) + 4;  # prefix on send.
        my $end = $start + length($shorten);

        if ( $end <= 79 ) {
            return;
        }    # don't shorten if it fit on one line anyway.
        CJ::shorten(
            $shorten,
            sub {
                my ($short_url) = shift;
                CJ::dispatch( $event,
                    "$event->{SOURCE}'s url is $short_url" );
            }
        );
        }
};

=head1 %response

XXX - leftover from internal command handling - instead, use
vars/subs directly from external commands namespaces.

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

String showing the valid contexts for this command, which are any of
public, private, or emote. The default for all commands is private only.

=item POS

Integer (-1, 0, 1) indicating the order in which this command should be checked.
Lowest is checked first.

=item HELP

A string with the helptext, or a Coderef that will be run when someone asks
for help with this handler. See the help response handler for more details.

=item STOP

Boolean that indicates whether this command should stop processing of any
other commands. Set to false to run this command B<and> still allow for
later rules to process.

=item PRIVILEGE

String indicating the level of privilege required to run this command. Three
possible settings: Admin (Must be one of CJ's administrators), and User
(Anyone can make this request.) - If not specified, the default is User.

TODO: Moderator (must moderator/own a discussion the request is on behalf of)

TODO: this declaration isn't actually used at the moment.

=back

There is no special default handler. You must define one explicitly.
The default behavior is silence, because that's how Priz would
have wanted it.

=cut

# load external commands
# XXX - currently forcing them into %response because that's how we did it
# when everything was internal. can now skip this step and update
# response-related code to work directly against the namespaces

my @external_commands = glob( getcwd . "/extensions/CJ/command/*pm" );
foreach my $file (@external_commands) {
    ( my $command ) = $file =~ /(\w+)\.pm/;
    do $file or CJ::debug("loading external command: $file: $!/$@");
    my $glob = qualify_to_ref( "::CJ::command::" . $command . "::" );
    $CJ::response{$command} = {
        CODE => sub { &{ *$glob{HASH}{response} }(@_) },
        TYPE => ${ *$glob{HASH}{TYPE} },
        POS  => ${ *$glob{HASH}{POSITION} },
        STOP => ${ *$glob{HASH}{LAST} },
        RE   => ${ *$glob{HASH}{RE} },
    };
}

=head2 CJ::asModerator($event, $disc, $sub) 

Determine if the user who generated the event is a moderator for (or owner
of) the discussion; if so, run the passed in sub.

=cut

sub CJ::asModerator {
    my $event = shift;
    my $disc  = shift;
    my $sub   = shift;

    my $server = TLily::Server->active();
    my $user   = $event->{SOURCE};
    $disc = $server->expand_name($disc);

    my $response;
    $server->cmd_process(
        "/what $disc",
        sub {
            my ($newevent) = @_;
            $newevent->{NOTIFY} = 0;
            return if ( $newevent->{type} eq 'begincmd' );
            if ( $newevent->{type} eq 'endcmd' ) {
                $response =~ /Owner: (.*?)\s+State/;
                if ( $1 eq $user ) {
                    $sub->();
                    return;
                }

                $response =~ /Moderators: (.*)Authors/ms;
                my $moderators = $1;
                my @moderator
                    = grep { $_ eq $user } split( /,\s+/, $moderators );
                if (@moderator) {
                    $sub->();
                    return;
                }
                CJ::dispatch( $event, "You are not a moderator for $disc" );
            }
            if ( $newevent->{text} ne q{} ) {
                $response .= $newevent->{text};
            }
        }
    );
}

=head2 CJ::humanTime

Given an elapsed time in seconds, produce a human readable elapsed time.

=cut

sub CJ::humanTime {
    my $seconds = shift;

    my $min  = 60;
    my $hour = $min * 60;
    my $day  = $hour * 24;

    my ( @result, $chunk );
    if ( $seconds >= $day ) {
        $chunk = int( $seconds / $day );
        push @result, $chunk . ' days';
        $seconds -= ( $chunk * $day );
    }
    if ( $seconds >= $hour ) {
        $chunk = int( $seconds / $hour );
        push @result, $chunk . ' hours';
        $seconds -= ( $chunk * $hour );
    }
    if ( $seconds >= $min ) {
        $chunk = int( $seconds / $min );
        push @result, $chunk . ' minutes';
        $seconds -= ( $chunk * $min );
    }
    if ($seconds) {
        push @result, $seconds . ' seconds';
    }

    return ( join( ', ', @result ) );
}

=head2 CJ::cleanHTML

Given an array of lines, return a string with the HTML stripped and
ASCII-fied (lily is 7 bit).

=cut

sub CJ::cleanHTML {

    # join blank lines, remove excess whitespace and kill tags.
    $a = join( ' ', @_ );
    $a =~ s/\n/ /;
    $a =~ s/<[^>]*>/ /g;

    # translate some common html-escapes.
    $a =~ s/&lt;/</gi;
    $a =~ s/&gt;/>/gi;
    $a =~ s/&amp;/&/gi;
    $a =~ s/&#46;/./g;
    $a =~ s/&#160;/ /g;
    $a =~ s/&#176;/o/g;
    $a =~ s/&deg;/o/ig;
    $a =~ s/&#0?39;/'/g;
    $a =~ s/&quot;/"/ig;
    $a =~ s/&laquo;/<</ig;
    $a =~ s/&raquo;/>>/ig;
    $a =~ s/&l[dr]quot;/"/ig;
    $a =~ s/&nbsp;/ /ig;
    $a =~ s/&uuml;/u"/ig;

    $a = unidecode($a);

    # cleanup whitespace.
    $a =~ s/\s+/ /g;
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;

    return $a;
}

=head2 CJ::dispatch($event, $message) 

Given a TLily event and a message, send that message to the recipients of the
original event. (Dealing with emote discussions).

=cut

sub CJ::dispatch {

    my ( $event, $message ) = @_;

    return if ( $message eq q{} );

    if ( $event->{type} eq 'emote' ) {
        $message = '"' . $message;
    }
    my $line = $event->{_recips} . ':' . $message;
    TLily::Server->active()
        ->cmd_process( $line, sub { $_[0]->{NOTIFY} = 0; } );
}

=head2 CJ::get_types($command)

Given a command, return all the types that handler is valid for.

=cut

sub CJ::get_types {
    my $handler   = shift;
    my $type_spec = $handler->{TYPE};

    return qw{private} unless $type_spec;

    if ( $type_spec eq 'all' ) {
        return qw{public private emote};
    }
    else {
        return split( ' ', $type_spec );
    }
}

sub cj_event {
    my ( $event, $handler ) = @_;

    $event->{NOTIFY} = 0;

    # I should never respond to myself. There be dragons!
    #  this is actually an issue with emotes, which automatically
    #  send the message back to the user.
    if ( $event->{SOURCE} eq $CJ::name ) {
        return;
    }

    # throttle:
    my $last   = $throttle{ $event->{SOURCE} }{last};
    my $status = $throttle{ $event->{SOURCE} }{status};   #normal(0)|danger(1)
    $throttle{ $event->{SOURCE} }{last} = time;

    if (( $throttle{ $event->{SOURCE} }{last} - $last ) < $throttle_interval )
    {

      #TLily::UI->name('main')->print("$event->{SOURCE} tripped throttle!\n");
        $throttle{ $event->{SOURCE} }{count} += 1;
    }
    elsif (
        ( $throttle{ $event->{SOURCE} }{last} - $last ) > $throttle_safety )
    {

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
    if ( $event->{type} eq 'private' ) {
        push @recips, $event->{SOURCE};
    }
    elsif ( $event->{type} eq 'emote' ) {
        if ( $event->{VALUE} =~ /^ . o O \((.*)\)$/ ) {
            $event->{VALUE} = $1;
        }
        elsif ( $event->{VALUE} =~ /^ (asks|says), \"(.*)\"$/ ) {
            $event->{VALUE} = $2;
        }
    }

    @recips = grep { !/^$CJ::name$/ } @recips;
    my $recips = join( ',', @recips );
    $recips =~ s/ /_/g;
    $event->{_recips} = $recips;

    # Workhorse for responses:
    my $message;
HANDLE_OUTER: foreach my $order (qw/-2 -1 0 1 2/) {
    HANDLE_INNER: foreach my $handler ( keys %CJ::response ) {

            # XXX respect PRIVILEGE
            my @types = CJ::get_types( $CJ::response{$handler} );
            if ( $CJ::response{$handler}->{POS} eq $order ) {
                next
                    if !grep {/$event->{type}/} @types;
                my $re = $CJ::response{$handler}->{RE};
                if ( $event->{type} eq 'public' ) {
                    $re = qr/(?i:$CJ::name\s*,?\s*)?$re/;
                }
                elsif ( $event->{type} eq 'emote' ) {

                    # XXX must anchor emotes by default.
                    # fixup so things like "drink" work, though.
                    $re = qr/(?i:$CJ::name\s*,?\s*)?$re/;
                }
                $re = qr/^\s*$re/;    # anchor to the beginning of a send
                if ( $event->{VALUE} =~ m/$re/ ) {
                    $CJ::served{ $event->{type} . ' messages' }++;
                    $CJ::served{$handler}++;
                    $message .= &{ $CJ::response{$handler}{CODE} }($event);
                    if ( $CJ::response{$handler}->{STOP} ) {
                        last HANDLE_OUTER;
                    }
                }
            }
        }
    }
    CJ::dispatch( $event, $message );

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
        $local_event->{_recips} = join( ',', @{ $ds->{TARGETS} } );
        foreach my $value ( @{ $ds->{VALUES} } ) {
            &{ $annotation_code{$annotation}{CODE} }( $local_event, $value );
            $CJ::served{$annotation}++;
            $CJ::served{"public messages"}++;
        }
    }

}

#
# Insert event handlers for everything we care about.
#
for (qw/public private emote/) {
    event_r( type => $_, order => 'before', call => \&cj_event );
}

# a bot never sleeps.
event_r(
    type  => 'away',
    order => 'after',
    call  => sub {
        my $event = shift;

        if ( $event->{SOURCE} eq $CJ::name ) {
            my $line = '/here';
            TLily::Server->active()
                ->cmd_process( $line, sub { $_[0]->{NOTIFY} = 0; } );
        }
    }
);

sub load {
    my $server = TLily::Server->active();
    $CJ::config = new Config::IniFiles( -file => $config_file )
        or die @Config::IniFiles::errors;

    foreach my $disc ( $CJ::config->GroupMembers('discussion') ) {
        my $discname = $disc;
        $discname =~ s/^discussion //;

        my @annotations = split /\n/,
            $CJ::config->val( $disc, 'annotations' );
        foreach my $annotation (@annotations) {
            $disc_annotations{$discname}{$annotation} = 1;
        }

    }
    foreach my $annotation ( $CJ::config->GroupMembers('annotation') ) {
        my $ann_name = $annotation;
        $ann_name =~ s/^annotation //;
        $annotations{$ann_name}{RE}
            = $CJ::config->val( $annotation, 'regexp' );
        $annotations{$ann_name}{action}
            = $CJ::config->val( $annotation, 'action' );
    }

    $frequently = TLily::Event::time_r(
        call => sub {
            do_throttled_HTTP();
        },
        interval => 2.0
    );

    # fire any "load" subs present in command modules.
    foreach my $ns ( values %CJ::command:: ) {
        my $load = *{ qualify_to_ref($ns) }{HASH}{load};
        if ( defined($load) ) {
            $load->();
        }
    }

    TLily::Server->active()->cmd_process('/blurb off');
}

=head2 checkpoint ()

Call this to save our in memory config out to our config file.

=cut

sub checkpoint {
    $CJ::config->RewriteConfig();
}

=head2 unload ()

Called by tigerlily when you use C<%ext unload cj> - our chance to
release any external resources we have open.

=cut

sub unload {
    checkpoint();

    TLily::Event->time_u($frequently);

    # clean up %INC (used for dispatch)
    delete @INC{ grep m:/extensions/cj/\w*\.pm$:, keys %INC };
}

1;
