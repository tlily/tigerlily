# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003       The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$
package MyApp;

use Foundation;
use Foundation::Functions;
use AppKit;
use AppKit::Functions;

use TLily::UI::Cocoa;

@ISA = qw(Exporter);

sub new {
    # Typical Perl constructor
    # See 'perltoot' for details
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
        'wc' => new TLily::UI::Cocoa(@_),
    };
    bless ($self, $class);



    return $self;
}

sub applicationWillFinishLaunching {
    my ($self, $notification) = @_;

    return 1;
}



1;

# The MyWindowController you'd normally expect to find here is actually the UI object:
# TLily::UI::Cocoa
