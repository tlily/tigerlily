use strict;
use vars qw(%config);

use TLily::Config qw(%config);

=head1 NAME

toc_parse.pl - AIM TOC event parser

=head1 DESCRIPTION

Convers low level toc_* events into higher level lily-style events, updates
server state database, etc.

=cut

my $has_html_entities = 0;

eval {
    require HTML::Entities;
    $has_html_entities = 1;
};


event_r(type => 'toc_NICK',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my ($my_name) = @{$event->{args}};

            $serv->state(DATA   => 1,
                         NAME   => "whoami",
                         VALUE  => $my_name);

            $serv->state(HANDLE => lc($my_name),
                         NAME   => $my_name,
                         BLURB  => "");
            1;
        });

event_r(type => 'toc_IM_IN',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};
            my $Me   = $serv->user_name();

            my ($source, $auto, $html_message) = @{$event->{args}};
            my $message = $html_message;
            if (lc($auto) eq 't') {
                $message = "[Auto Response] $html_message";
            }

            # Add the user to our state database.
            $serv->state(HANDLE => lc($source),
                         NAME   => $source,
                         BLURB  => "");

            # un-HTMLify the message:
            $message =~ s/<[^>]*>//g;
            if ($has_html_entities) {
                HTML::Entities::decode_entities($message);
            }

            # And create a lily-style private event.
            TLily::Event::send({ server  => $serv,
                                 ui_name => $serv->{'ui_name'},
                                 type    => "private",
                                 VALUE   => $message,
                                 html    => $html_message,
                                 SOURCE  => $source,
                                 SHANDLE => lc($source),
                                 RECIPS  => $Me,
                                 TIME    => time,
                                 NOTIFY  => 1,
                                 BELL    => 1,
                                 STAMP   => 1 });

            # remember who the last message came from for ':' replies.
            $serv->{last_message_from} = $source;

            1;
        });

event_r(type => 'toc_CONFIG',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my ($config) = @{$event->{args}};

            my $current_group = undef;
            foreach (split /\n/, $config) {
                my ($type, $value) = /^(.) (.*)$/;
                if ($type eq "g") {
                    $current_group = $value;
                }
                if ($type eq "b") {

                    $serv->state(HANDLE      => lc($value),
                                 NAME        => $value,
                                 ONLINE      => undef,
                                 EVIL        => undef,
                                 ON_SINCE    => undef,
                                 IDLE        => undef,
                                 UNAVAILABLE => undef);

                    $serv->{BUDDY_GROUP}{$current_group}{$value} = 1;
                }
            }
            1;
        });

event_r(type => 'toc_UPDATE_BUDDY',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my ($buddy,$online,$evil,$on_since,$idle,$uc) =
                @{$event->{args}};

            my $unavail = 0;
            $unavail = 1 if (substr($uc, 2) eq 'U');

            $serv->state(HANDLE      => lc($buddy),
                         NAME        => $buddy,
                         ONLINE      => $online,
                         EVIL        => $evil,
                         ON_SINCE    => $on_since,
                         IDLE        => $idle,
                         LAST_UPDATE => time,
                         UNAVAILABLE => $unavail);
            1;
        });

event_r(type => 'toc_ERROR',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my ($code, $args) = @{$event->{args}};

            my $error = "$Net::AOLIM::ERROR_MSGS{$code}";
            $error =~ s/\$ERR_ARG/$args/g;

            # And create a lily-style sysmsg event.
            TLily::Event::send({ server  => $serv,
                                 ui_name => $serv->{'ui_name'},
                                 type    => "sysmsg",
                                 SHANDLE => "AIM",
                                 VALUE   => $error,
                                 TIME    => time,
                                 NOTIFY  => 1,
                                 BELL    => 1,
                                 STAMP   => 1 });
            1;
        });

event_r(type => 'toc_EVILED',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my ($evil_user, $eviled_by) = @{$event->{args}};

            $serv->state(HANDLE      => lc($evil_user),
                         EVIL        => 1);

            # create an event we can format..
            TLily::Event::send({ server  => $serv,
                                 ui_name => $serv->{'ui_name'},
                                 type    => "evil",
                                 SOURCE  => $eviled_by,
                                 RECIPS  => $evil_user,
                                 TIME    => time,
                                 NOTIFY  => 1,
                                 BELL    => 0,
                                 STAMP   => 1 });
            1;
        });

event_r(type => 'toc_PAUSE',
        call => sub {
            my($event) = @_;
            my $serv = $event->{server};

            my $message = "Server is temporarily offline.  All messages will be ignored until it returns.";

            # And create a lily-style sysmsg event.
            TLily::Event::send({ server  => $serv,
                                 ui_name => $serv->{'ui_name'},
                                 type    => "sysmsg",
                                 VALUE   => $message,
                                 TIME    => time,
                                 NOTIFY  => 1,
                                 BELL    => 1,
                                 STAMP   => 1 });
            1;
        });

1;
