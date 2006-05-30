# -*- Perl -*-
# $Id: bmw.pl 839 2003-12-16 05:09:33Z mjr $

use strict;

=head1 NAME

rm.pl - Convert HTML unicode escapes into actual unicode.

=head1 DESCRIPTION

When loaded, this extension will reformat any sends (emote, private, public)
to be utf8-encoded instead.

=cut

help_r( 'rm', "convert html escape codes to utf8.

Note: Currently only works on the Text UI.

This extension was named its inspiration, rm\@RPI.
");


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


