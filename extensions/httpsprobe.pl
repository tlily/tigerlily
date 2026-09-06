use strict;

use TLily::Server::HTTP;

=head1 NAME

httpsprobe.pl - check whether TLily::Server::HTTP can fetch an https URL

=head1 SYNOPSIS

    %httpsprobe                 # fetch a known-good https URL
    %httpsprobe <url>           # fetch a URL of your choosing

=head1 DESCRIPTION

A minimal demonstration that TLily::Server::HTTP either can or cannot fetch
over TLS. It makes one request and reports what came back.

Requires http_parse.pl, which is loaded by default -- that is the extension
that turns the raw socket data into a body and calls our callback.

Before the fix, an https URL is parsed correctly -- port 443, protocol
"https" -- but nothing sets {secure}, so tigerlily opens a plaintext socket to
port 443 and sends a cleartext GET into a port expecting a TLS handshake. What
comes back depends on the server, and both outcomes show up in practice:

    %httpsprobe https://example.com/
    (fetching https://example.com/)
    FAIL: got HTTP 400 in the clear -- the request went to port 443
          unencrypted, so the server rejected it before reading any of it.

    %httpsprobe https://www.biblegateway.com/
    (fetching https://www.biblegateway.com/)
    FAIL: nothing came back after 20s.
          If this was an https URL and a http:// one works, ...

Afterwards both complete:

    %httpsprobe https://example.com/
    (fetching https://example.com/)
    OK: status 200, 1256 bytes, looks like HTML

Try a plain http:// URL too. That path is untouched by the fix and works
either way, which is what separates "TLS is broken" from "the network is
broken".

=cut

# Something small, stable, and unlikely to be blocked.
my $default_url = 'https://example.com/';

# How long to wait before calling it a failure. A server that hangs up on a
# cleartext request never produces a callback, so without a timeout that case
# looks like nothing happening at all.
my $timeout = 20;

my %pending;

sub httpsprobe_cmd {
    my ( $ui, $args ) = @_;

    my $url = $args || $default_url;
    $url =~ s/^\s+//;
    $url =~ s/\s+$//;

    if ( $url !~ m{^https?://} ) {
        $ui->print("usage: %httpsprobe [http(s)://...]\n");
        return;
    }

    $ui->print("(fetching $url)\n");

    my $id      = "$url:" . time() . ":" . rand();
    my $started = time();
    $pending{$id} = 1;

    TLily::Server::HTTP->new(
        url      => $url,
        ui_name  => $ui->{name},
        # http_parse.pl accumulates the body onto the server object and hands
        # that back, so this is the server, not a separate response.
        callback => sub {
            my ($server) = @_;
            return unless delete $pending{$id};

            my $elapsed = time() - $started;
            my $body    = $server->{_content};
            my $status  = $server->{_state} ? $server->{_state}->{_status} : undef;
            my $secure  = $url =~ m{^https://};

            if ( !defined($body) || $body eq '' ) {
                $ui->print( "FAIL: connection closed with no content"
                        . " (${elapsed}s)"
                        . ( $secure ? " -- see %help httpsprobe" : q{} )
                        . "\n" );
                return;
            }

            # A cleartext request to a TLS port is usually rejected out of
            # hand, so a 4xx on an https URL is the signature of the bug
            # rather than of anything wrong with the URL.
            if ( $secure && defined($status) && $status >= 400 ) {
                $ui->print(
                    "FAIL: got HTTP $status in the clear -- the request went "
                        . "to port 443\n"
                        . "      unencrypted, so the server rejected it "
                        . "before reading any of it.\n" );
                return;
            }

            $ui->printf( "OK: status %s, %d bytes%s (%ds)\n",
                ( defined $status ? $status : '?' ),
                length($body),
                ( $body =~ /<html/i ? ', looks like HTML' : q{} ),
                $elapsed );
            return;
        }
    );

    # A server that hangs up rather than answering produces no callback at
    # all, so without this the user just watches nothing happen.
    TLily::Event::time_r(
        after => $timeout,
        call  => sub {
            return unless delete $pending{$id};
            $ui->print(
                "FAIL: nothing came back after ${timeout}s.\n"
                    . "      If this was an https URL and a http:// one "
                    . "works, TLily::Server::HTTP\n"
                    . "      cannot speak TLS: it never sets {secure}, so "
                    . "the request went to\n"
                    . "      port 443 in the clear and the server hung up.\n"
            );
            return;
        }
    );

    return;
}

command_r( 'httpsprobe', \&httpsprobe_cmd );
shelp_r( 'httpsprobe', 'check whether https URLs can be fetched' );
help_r( 'httpsprobe', <<'END_HELP' );
Fetch a URL through TLily::Server::HTTP and report what came back. With no
argument it fetches https://example.com/.

Useful for telling apart "TLS is broken" and "the network is broken": try it
with an https:// URL and then an http:// one. If the plain one works and the
secure one does not, TLily::Server::HTTP cannot speak TLS.
END_HELP

1;
