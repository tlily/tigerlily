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

use TLily::Version;

BEGIN {
    # Various bits of code key off the version - use "-aqua" to 
    # ID this version.
    $TLily::Version::VERSION .= "-aqua";
    
    # $::TL_LIBDIR needs to be the directory which contains tlily.global
    # This is going to be the first path in @INC that ends in Resources.
    
    foreach my $path (@INC) {
        if ($path =~ /Resources$/) {
            $::TL_LIBDIR = $path;
            last;
        }
    }
}

require "tlily.PL";
