# -*- Perl -*-

use strict;
use warnings;

=head1 NAME

rm.pl - Convert HTML unicode escapes into actual unicode.

=head1 DESCRIPTION

When loaded, this extension will reformat any sends (emote, private, public)
to be utf8-encoded instead.

=cut

help_r( 'rm', <<'END_HELP');
Convert html escape codes to utf8. Note: for utf8 codepoints above ASCII,
only works on the Text UI. (ascii codepoints like &#64; work fine.)

This extension was named after its inspiration, rm@RPI.
END_HELP


# XXX: A smarter version of this would this translation based on context.
#      For example, is this sequence inside a url? 

# Needed for the Text UI to avoid wide character warnings.
binmode(STDOUT, ":encoding(UTF-8)");

sub handler {
    my($event, $handler) = @_;

    $event->{VALUE} =~ s/&#(\d+);/chr($1)/ge;
    return 0;
}

event_r(type  => 'emote',
    call  => \&handler,
    order => 'before');

event_r(type  => 'public',
    call  => \&handler,
    order => 'before');

event_r(type  => 'private',
    call  => \&handler,
    order => 'before');


