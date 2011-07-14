#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

package TLily::Server::IRC::Driver;

use strict;
use warnings;
use vars qw(@ISA);

use Carp;
use TLily::Event;
use Data::Dumper;

my $IRC_avail;
BEGIN {
    eval { require Net::IRC; };
    if ($@) {
        $IRC_avail = 0;
    } else {
        $IRC_avail = 1;
        @ISA = qw(Net::IRC);
    }

}

my %tlily_io_handlers;

sub new {
    return unless $IRC_avail;
    my $proto = shift;
    my $class = ref($proto) || $proto;
    return $class->SUPER::new(@_);
}

sub addfh {
    my $self = shift;
    my ($fh, $code, $flag) = @_;

    my $id = TLily::Event::io_r(handle => $fh,
                                mode => lc($flag),
                                call => \&Net::IRC::do_one_loop,
                                obj => $self);

    push @{$tlily_io_handlers{fileno($fh)}}, $id;

    return $self->SUPER::addfh(@_);
}

sub removefh {
    my $self = shift;
    my ($fh) = @_;

    if (exists $tlily_io_handlers{fileno($fh)}) {
        foreach my $id (@{$tlily_io_handlers{fileno($fh)}}) {
            TLily::Event::io_u($id);
            delete $tlily_io_handlers{fileno($fh)};
        }
    } else {
        warn("Could not find tlily handler for IRC filehandle.  Please report this as a bug using '%submit client', and provide details on what you were doing when it happened.  If possible, please give a recipe for reproducing the bug.");
    }

    return $self->SUPER::removefh(@_);
}

1;
