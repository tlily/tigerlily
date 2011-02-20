use strict;

use Data::Dumper;
use XML::Simple;
use CGI;

use TLily::Bot;
use TLily::Server::HTTP;

# XML API Docs:
#  http://fluff.dapillow.com:8888/defiance/datagrab/datagrabber-help.html
#  http://fluff.dapillow.com:8888/defiance/datagrab/dataposter-help.html

my $BASE_URL = 'http://defiance.versestudios.com/datagrab/';

my @behaviors = (
    { name    => 'queue_length',
      respond => 'if_addressed',
      match   => [ 'queue length', 'queuelen' ],
      call    => \&fetch_queue_length
    },
    { name    => 'current_queue',
      respond => 'if_addressed',                          # i need to be addressed directly.
      match   => [ qq/whats coming( soon| up)?/,
                  qq/queue/ ],
      call    => \&fetch_current_queue
    },
    { name    => 'current_stats_passive',
      respond => 'all',
      match   => [ qq/whats playing( right)?( now)?/ ],
      call    => \&fetch_playing_now
    },
    { name    => 'current_stats_active',
      respond => 'if_addressed',
      match   => [ 'playing', 'current', 'now', 'whats on',
                  'anything good on', 'whats this' ],
      call    => \&fetch_playing_now
    },
    { name    => 'current_stats_active',
      respond => 'if_addressed',
      match   => [ 'playing', 'current', 'now' ],
      call    => \&fetch_playing_now
    },
    { name    => 'search',
      respond => 'private_only',
      match   => [ 'search for (.*)',
                   'search (.*)' ],
      call    => \&do_search
    },
    { name    => 'request',
      respond => 'private_only',
      match   => [ 'request (\d+)\s*(.*)' ],
      call    => \&do_request
    }
);

my $xs = XML::Simple->new(SuppressEmpty => undef);

init_handlers();
init_behaviors();

##############################################################################

sub init_handlers() {
  # set up the send handlers
  event_r(order => 'after',
          type => 'private',
          call => \&sendhandler);

  event_r(order => 'after',
          type => 'public',
          call => \&sendhandler);

  event_r(order => 'after',
          type => 'emote',
          call => \&sendhandler);
}

sub init_behaviors {
    my $num = 0;
    foreach my $behavior (@behaviors) {
        $num++;

        die "Behavior #$num is missing 'name'"
            unless (exists($behavior->{'name'}));

        my $name = $behavior->{name};

        die "Behavior '$name' is missing 'respond'"
            unless (exists($behavior->{'respond'}));

        die "Behavior '$name' has invalid 'respond' value"
            unless ($behavior->{'respond'} =~ /^(all|if_addressed|private_only)$/);

        die "Behavior '$name' is missing 'call'"
            unless (exists($behavior->{'call'}));

        die "Behavior '$name': call is not a code ref'"
            unless (ref($behavior->{'call'}) eq "CODE");

        die "Behavior '$name' is missing 'match'"
            unless (exists($behavior->{'match'}));

        if (ref($behavior->{'match'})) {
            if (ref($behavior->{'match'}) ne "ARRAY") {
                die "Behavior '$name': 'match' is not an array reference!";
            }
        } else {
            # convert it to an arrayref if it's a scalar.. no biggie.
            $behavior->{'match'} = [ $behavior->{'match'} ];
        }
    }
}


sub sendhandler {
    my($event,$handler) = @_;

    my $ui=ui_name();

    if ($event->{isuser}) {
        # it's a message to me- ignore it.

        return 1;
    }

    # Now see if we have anything to do.
    my $behavior = find_behavior_for_sendtext($event->{VALUE});

    if ($behavior) {
        # most commands require me to be addressed directly.
        if ($behavior->{respond} eq 'if_addressed') {
            return 1 unless (i_am_being_addressed($event));
        }

        # and some can only be used in private messages..
        if ($behavior->{respond} eq 'private_only') {
            return 1 unless ($event->{EVENT} eq "private");
        }

        # OK, so trigger the behavior.
        $ui->print("Triggering behavior $behavior->{name}.\n");
        &{$behavior->{call}}($event);

    }

    return 1;
}

sub i_am_being_addressed {
    my ($event) = @_;

    if ($event->{EVENT} eq "private") {
        return 1;
    }

    my $my_name = active_server()->user_name();
    # note: could support aliases (like mechajosh -> mj) as /groups, as
    # in mask.pl.

    if ($event->{VALUE} =~ /^\s*$my_name[,:]/i) {
        return 1;
    }

    return 0;
}

sub find_behavior_for_sendtext {
    my ($sendtext) = @_;

    # normalize whitespace.
    $sendtext =~ s/\s+/ /g;
    my $sendtext_nopunc = $sendtext;
    $sendtext_nopunc =~ s/[^a-zA-Z0-9 ]//g;

    # try to find a matching pattern.
    foreach my $behavior (@behaviors) {
        foreach my $pattern (@{$behavior->{'match'}}) {
            return $behavior if ($sendtext =~ /$pattern/i);
            return $behavior if ($sendtext_nopunc =~ /$pattern/i);
        }
    }

    # nope?
    return undef;
}


sub fetch_queue_length {
    my ($event) = @_;

    get_text(
        url => "$BASE_URL/datagrabber.php?mode=queue_length",
        call => sub {
           my ($text) = @_;

           my $response = "The queue length is currently $text.\n";

           send_response($event, $response);
           return 1;
        }
    );
}


sub fetch_playing_now {
    my ($event) = @_;

    get_xml(
        url => "$BASE_URL/datagrabber.php?mode=current_stats",
        call => sub {
           my ($xml) = @_;
           my $song = $xml->{current_stats}{historyEntry};

           my $response = "Now playing: ";
           $response .= describe_song($song);

           $response .= ".  There are $song->{listeners} people listening.";

           send_response($event, $response);
           return 1;
        }
    );
}


sub fetch_current_queue {
    my ($event) = @_;

    get_xml(
        url => "$BASE_URL/datagrabber.php?mode=current_queue",
        call => sub {
           my ($xml) = @_;

           my @songs = @{$xml->{current_queue}{song}};

           my $response = "The following songs are currently in the queue to be played:\n";
           foreach my $song (@songs) {
               $response .= " " . describe_song($song) . "\n";
           }

           if (@songs == 0) {
               $response = "No songs currently in the queue.";
           }

           send_response($event, $response);
           return 1;
        }
    );
}

sub do_request {
    my ($event) = @_;

    my ($id, $message) = ($event->{VALUE} =~ /request (\d+)\s*(.*)/);
    if (! defined($id)) {
        send_response($event, "Request what?");
        return;
    }

    my $requestor = CGI::escape($event->{SOURCE});
    my $my_name = CGI::escape(active_server()->user_name());
    my $message_esc = CGI::escape($message);

    my $url = "$BASE_URL/dataposter-by-get.php?mode=insert_request&songID=$id&requestor=$requestor&username=$my_name&message=$message_esc";
    ui_name->print("URL=$url\n");
    get_text(
        url => $url,
        call => sub {
           my ($text) = @_;

           my $response = "Your request has been entered in the queue: $text";

           if ($text == -1) {
               $response = "user not found, or incorrect password with mismatched";
           }

           if ($text == -2) {
               $response = "password not supplied and is needed";
           }

           if ($text == -3) {
               $response = "songID not found in database";
           }

           send_response($event, $response);
           return 1;
        }
    );
    return 1;
}


sub do_search {
    my ($event) = @_;

    my ($criteria) = ($event->{VALUE} =~ /search for (.*)/);
    if (! defined($criteria)) {
        ($criteria) = ($event->{VALUE} =~ /search (.*)/);
    }
    if (! defined($criteria)) {
        send_response($event, "Search for what?");
        return 1;
    }

    my $criteria_esc = CGI::escape($criteria);

    get_xml(
        url => "$BASE_URL/datagrabber.php?mode=search_library&search_string=$criteria_esc",
        call => sub {
           my ($xml) = @_;

           my $num_results = $xml->{searchResults}{numberResults};
           my $max_results = $xml->{searchResults}{maxResults};

           my @songs = @{$xml->{searchResults}{song}};

           my $response = "The following $num_results songs match '$criteria'\n";
           foreach my $song (@songs) {
               $response .= " $song->{ID} | " . describe_song($song) . "\n";
           }

           $response .= "\n (NOTE! The maximum number of results ($max_results) was exceeded, so only the first $num_results will be displayed.)\n" if ($num_results >= $max_results);

           $response .= "\n To request a song, use \"request <id>\"\n";

           if ($num_results == 0) {
               $response = "No matches to '$criteria'.";
           }

           send_response($event, $response);
           return 1;
        }
    );
}

sub describe_song {
    my ($song) = @_;

    my $descr;
    $descr .= "$song->{artist}: \"$song->{title}\"";
    $descr .= " (album \"$song->{album}\")" if ($song->{album} =~ /\S/);
    my $duration_secs = $song->{duration} / 1000;

    my $duration = sprintf("%d:%02d", int($duration_secs / 60), $duration_secs % 60);
    $descr .= " [$duration]";

    return $descr;
}

sub get_xml {
    my (%args) = @_;

    TLily::Server::HTTP->new(
        url => $args{url},
        callback => sub {
            my ($response) = @_;
            $response->{_content} =~ s/Æ/AE/g;

            my $xml = $xs->XMLin($response->{_content});

            &{$args{call}}($xml);
        }
    );
}

sub get_text {
    my (%args) = @_;

    TLily::Server::HTTP->new(
        url => $args{url},
        callback => sub {
            my ($response) = @_;
            my $text = $response->{_content};

            &{$args{call}}($text);
        }
    );
}


sub send_response {
    my ($original_event, $response) = @_;
    my $send_to;

    if ($original_event->{EVENT} eq "private") {
        $send_to  = $original_event->{SOURCE};
    } else {
        $send_to = $original_event->{RECIPS};
    }
    $send_to  =~ s/\s/_/g;

    $response = TLily::Bot::wrap_lines($response);
    $response =~ s/\s*$//g;

    my $ui=ui_name();
    $ui->print("sending $send_to;$response");
    $original_event->{server}->sendln("$send_to;$response");

    return 1;
}


