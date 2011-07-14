#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

use strict;

package TLily::UI::Util;

use vars qw(@ISA @EXPORT_OK);
use Exporter;

@ISA       = qw(Exporter);
@EXPORT_OK = qw(next_line wrap);


# These are handy in a couple of places.
sub max { return ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min { return ($_[0] < $_[1]) ? $_[0] : $_[1] }


# Returns the starting and ending indices of the next line in a string.
# The search starts at pos($s), and pos is updated by this function.
# Returns undef if no lines remain.  $len, if supplied is the maximum line
# length to return; this defaults to 78.
sub next_line {
    my $len = (defined $_[1]) ? $_[1] : 78;

    # Bail if we are at the end of the buffer.
    return if (pos($_[0]) && pos($_[0]) == length($_[0]));

    # Wordwrapping is in the lily style: words longer than N
    # (currently 10) characters will not be broken.  We consider the
    # string to find as containing two parts: the initial portion
    # which cannot be wordwrapped ($len - 10 here), and the remainder
    # which can.

    # The initial, non-breakable portion.
    my $imatch = $len - 10;
    $imatch = 0 if ($imatch < 0);

    # The remainder, less one.
    my $nmatch = $len - $imatch - 1;
    return if ($nmatch <= 0);

    # Here is the wordwrapper.
    my $mstart = pos($_[0]);
    $_[0] =~ m(\G
        # These need not be wrapped.
            (?: .{0,$imatch})
            (?:
            # Either break on a space/newline...
            (?: .{0,$nmatch} (?: \s | $ )) |
            # Or none is available, so take what we can fit.
                (?: ..{0,$nmatch} \n ? )
            )
        )xg or return;
    my $mend = pos($_[0]);

    # I don't think this is strictly necessary, but why take chances?
    $mend-- if (substr($_[0], $mend-1, 1) eq "\n");

    #my $ll = substr($_[0], $mstart, $mend-$mstart);
    #$ll =~ s/\n/*/g;
    #print STDERR "  == $mstart $mend \"$ll\"\n";
    return ($mstart, $mend);
}


sub wrap {
    my $s = shift;
    my %h = @_;
    my @r;

    my $indent = $h{indent} || "";
    my $len    = ($h{cols} || 78) - length($indent);

    while (my($b, $e) = next_line($s, $len)) {
        push @r, $indent . substr($s, $b, $e-$b);
    }

    return @r;
}

1;
