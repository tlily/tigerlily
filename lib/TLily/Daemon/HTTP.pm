#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

package TLily::Daemon::HTTP::Connection;

use strict;

use Carp;

use TLily::Daemon::Connection;

use vars qw(@ISA);

@ISA = qw(TLily::Daemon::Connection);

sub send {
    my ($self, %args) = @_;
    my $filename;

    croak "send called without required argument \"file\"!" unless $args{file};

    unless (($filename = $self->{daemon}->file_c($args{file}))) {
        $self->send_error( errno => 404,
                           title => "File not found",
                           long  => "The url $args{file} is unavailable " .
                           "on this server.",
                           head  => $args{head} );
        return 0;
    }

    $self->{filealias} = $args{file};

    my $in;
    if ((! -r $filename) || !(open $in, '<', $filename)) {
        $self->send_error( errno => 403,
                           title => "Forbidden",
                           long  => "Unable to open $args{file}.",
                           head  => $args{head} );
        return 0;
    }

    $self->{filedes} = $in;

    print {$self->{sock}} "HTTP/1.0 200 OK\r\n";
    print {$self->{sock}} "Date: " . TLily::Daemon::HTTP::date() . "\r\n";
    print {$self->{sock}} "Connection: close\r\n";
    print {$self->{sock}} "Content-Length: " . (-s $in) . "\r\n";
    print {$self->{sock}} "Content-Type: application/octet-stream\r\n";
    print {$self->{sock}} "Cache-Control: private\r\n";
    print {$self->{sock}} "\r\n";

    # the real data is done elsewhere.
    unless ($args{head}) {
        $self->{output_id} = TLily::Event::io_r (handle => $self->{sock},
                                                 mode   => 'w',
                                                 obj    => $self,
                                                 call   => \&send_raw);
    }

    return 1;
}

sub send_error {
    my ($self, %args) = @_;

    print {$self->{sock}} "HTTP/1.0 ${args{errno}} ${args{title}}\r\n";
    print {$self->{sock}} "Date: " . TLily::Daemon::HTTP::date() . "\r\n";
    if (exists $args{headers}) {
        foreach my $h (keys (%{$args{Headers}})) {
            print {$self->{sock}} "$h: ${args{headers}->{$h}}\r\n";
        }
    }
    print {$self->{sock}} "\r\n";

    unless ($args{head}) {
        print {$self->{sock}} "<html><head>\n";
        print {$self->{sock}} "<title>${args{errno}} ${args{title}}</title>\n";
        print {$self->{sock}} "</head><body>\n<h1>${args{errno}} ";
        print {$self->{sock}} "${args{title}}";
        print {$self->{sock}} "</h1>\n${args{long}}<p>\n";
        print {$self->{sock}} "</body></html>\n";
    }
    return;
}

sub send_raw {
    my ($self, $mode, $handler) = @_;
    my $buf;

    if (read $self->{filedes}, $buf, 4096) {
        print {$self->{sock}} $buf;
    } else {
        # File's done.  Tell the client.
        TLily::Event::send(type   => "$self->{proto}_filedone",
                           daemon => $self);
        $self->close();
    }
}

sub close {
    my ($self, @args) = @_;

    close $self->{filedes} if defined($self->{filedes});
    $self->{filedes} = undef;
    TLily::Event::io_u ($self->{output_id});

    return $self->SUPER::close(@args);
}

package TLily::Daemon::HTTP;

use strict;

use Carp;

use TLily::Daemon;
use TLily::Extend;

use vars qw(@ISA);

@ISA = qw(TLily::Daemon);

=head1 NAME

TLily::Daemon::HTTP - Tigerlily HTTP Daemon

=head1 SYNOPSIS

use TLily::Daemon::HTTP;

=head1 DESCRIPTION

This is a simple http daemon.  It is intended for use by extensions for
client-to-client communications.  All of the socket work is done for us
by the parent class, so this will handle the files available to any given
instance of the daemon.

Currently, only one instance of this class is allowed, but extensions don't
need to care about that.

=head1 FUNCTIONS

=over 10

=cut

#' CPerl-mode is confused

# The currently existant object.  For now at least, force only one instance.
my $inst = undef;

# List of currently exported files
my %files = ();

=item new(%args)

Creates a new TLily::Daemon::HTTP object.

=cut

sub new {
    my ($proto, %args) = @_;
    my $class = ref($proto) || $proto;

    # Only allow one instance of this class.
    return $inst if defined($inst);

    $args{protocol} = "http";
    $args{port}   ||= 8080;
    $args{type}     = 'tcp';
    $args{name}     = "httpd";  # Change this if we ever do multiple instances

    my $self = $class->SUPER::new(%args);

    return undef unless defined($self);

    $inst = $self;

    TLily::Registrar::class_r('web_file' => \&file_u);

    bless $self, $class;
}

=item daemon()

Returns a reference to the currently running daemon object, or undef
if there is not one running.

=cut

sub daemon {
        return $inst;
}

=item terminate()

Terminate the daemon

=cut

sub terminate {
    $inst->SUPER::terminate();

    $inst = undef;
}

=item file_r(%args)

Registers a file with the daemon for export.  The only required parameter
is 'file', which is the complete path to the file to allow.  An optional
parameter, 'alias', is used to obsufcate the real name from the recipient,
and is used in place of the actual filename in the url.

If no alias is given, then the file will be refered to by the last component
of the path.

  TLily::Daemon::HTTP::file_r(file  => '/tmp/bar.tar.gz',
                              alias => 'foo.tar.gz');

=cut

sub file_r {
    shift if (@_ % 2);
    my (%args) = @_;

    croak "File registered without \"file\"" unless defined($args{file});

    return undef unless -r $args{file};

    my @path = split m|/|, $args{file};
    $args{alias} = pop @path unless defined($args{alias});

    TLily::Registrar::add("web_file", $args{alias});

    $files{$args{alias}} = $args{file};
    return $inst->{port};
}

=item file_u($alias)

Unregister a file for export.

=cut

sub file_u {
    shift if (@_ > 1);
    my ($alias) = @_;

    my @path = split m|/|, $alias;
    $alias = pop @path if !defined($files{$alias});

    $files{$alias} = undef;
}

=item file_c($alias)

Return the real name for $alias, or undef if not found.

=cut

sub file_c {
    shift if (@_ > 1);
    my ($alias) = @_;

    return $files{$alias};
}

=item date($time)

Return a string based on $time, or time(), if not specified, that complies
with HTTP/1.1 date standards.

=cut

sub date {
    shift if (@_ > 1);
    my ($time) = @_;

    $time = time() unless ($time);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);
    my $dayofweek = (qw(Mon Tue Wed Thu Fri Sat Sun))[$wday];
    my $month = (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$mon];
    $year += 1900;

    return sprintf ("${dayofweek}, %02d $month $year %02d:%02d:%02d GMT",
                    $mday, $hour, $min, $sec);
}

sub DESTROY {
    TLily::Event::send (type => 'http_terminate');
    $inst->SUPER::DESTROY();
    $inst = undef;
}

1;
