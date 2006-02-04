# -*- Perl -*-
# $Id: $

use strict;

#
# The newline extension reformats public and private
# sends from the server. If a character sequence that represents a newline
# is seen, convert that to a real newline.
#

=head1 NAME

newline.pl - Convert faux newlines into real ones.

=head1 DESCRIPTION

Reformat public, and private sends with fake newlines to use real ones.

=cut

my $newline_re = qr{ 
  (?:   
    \\n |
    < \s* br \s* /? >   # a br tag, with an optional close brace
  )
  \s*  # match any trailing whitespace to line things up.
}xms;

sub newline_handler {
    my($event) = @_;
    
    $event->{VALUE} =~ s/$newline_re/\n/g;
    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'before',
	    call  => \&newline_handler);
    event_r(type  => 'public',
	    order => 'before',
	    call  => \&newline_handler);

    help_r('newline' => "
Automatically add newlines to incoming sends where appropriate.
");
} 


1;

