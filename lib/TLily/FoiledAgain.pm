#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003-2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

package TLily::FoiledAgain;

use strict;
use Carp;

use vars qw($DEBUG);

$DEBUG = 0;
my $UI_CLASS = undef;

=head1 NAME

TLily::FoiledAgain - An interface that UIs can call against instead of Curses.pm

=head2 CLASS (SCREEN) METHODS

=over 10

=item set_ui($package_name)

Choose the underlying UI implementation.   This must be called before anything else will work.

=cut

sub set_ui {
    ($UI_CLASS) = @_;

    eval "require $UI_CLASS;";
    die $@ if $@;
}


=item start()

Brings up the user interface.

=item stop()

Tears down the user interface.  Note that the UI can be restarted by
re-calling start(), but no state needs to be preserved- it is up to the
caller to re-draw the screen if this is done.

=item has_resized()

Returns true if the terminal has been resized since the last call.

=item suspend()

=item resume()

=item screen_width()

=item screen_height()

=item update_screen()

Copy the current contents of the virtual screen described by any windows
(see below) to the real screen.  The cursor should be left at the location of
the point (in the last window?)

=item want_color($bool)

=item reset_styles()

=item defstyle($style, @attrs)

=item defcstyle($style, $fg, $bg, @attrs)

=back

=head2 OBJECT (WINDOW) METHODS

In addition to the above class methods, this is also an object representing
a virtual window within the real screen.   The following methods apply to one
of these windows.   Note that coordinates (other than in the constructor) are
relative to the window, not the screen.

=over 10

=item new($lines, $cols, $begin_x, $begin_y)

Allocate the window of the given size, at the given position on the screen.

=item destroy()

Clean up the window.

=item clear()

Clear the contents of the window.

=item clear_background($style)

Clear the window and set its background to $style.

=item set_style($style)

Set the style for text to be added.

=item clear_line($line)

This function should clear the given line and set the point to the
beginning of the deleted line.

=item move_point($line, $col)

Move the current cursor position.

=item addstr_at_point($string)

Add a string at the current cursor position.

=item addstr($line, $col, $string)

Add a string at the specified position.

=item insch($line, $col, $character)

Insert a character at the given position, pushing the rest of the
line over one character.

=item delch_at_point()

Remove a character at the given postion, pulling back the rest of the line.

=item position_cursor($line, $col)

=item scroll($num_lines)

Scroll up $num_lines lines.  $num_lines may be negative to scroll the
other direction.

=item commit()

Must be called after any changes to the window in order for the changes
to show up on the next call to update_screen.

=item read_char()

Return a character of input, if available.  Otherwise return undef.

=cut

# screen operations
sub start            { dispatch_classmethod(start            => @_); }
sub stop             { dispatch_classmethod(stop             => @_); }
sub refresh          { dispatch_classmethod(refresh          => @_); }
sub has_resized      { dispatch_classmethod(has_resized      => @_); }
sub suspend          { dispatch_classmethod(suspend          => @_); }
sub resume           { dispatch_classmethod(resume           => @_); }
sub screen_width     { dispatch_classmethod(screen_width     => @_); }
sub screen_height    { dispatch_classmethod(screen_height    => @_); }
sub update_screen    { dispatch_classmethod(update_screen    => @_); }
sub bell             { dispatch_classmethod(bell             => @_); }
sub want_color       { dispatch_classmethod(want_color       => @_); }
sub reset_styles     { dispatch_classmethod(reset_styles     => @_); }
sub defstyle         { dispatch_classmethod(defstyle         => @_); }
sub defcstyle        { dispatch_classmethod(defcstyle        => @_); }

sub new              { shift; new $UI_CLASS(@_); }
sub destroy          { NOTIMPLEMENTED(@_); }
sub clear            { NOTIMPLEMENTED(@_); }
sub clear_background { NOTIMPLEMENTED(@_); }
sub set_style        { NOTIMPLEMENTED(@_); }
sub clear_line       { NOTIMPLEMENTED(@_); }
sub move_point       { NOTIMPLEMENTED(@_); }
sub addstr_at_point  { NOTIMPLEMENTED(@_); }
sub addstr           { NOTIMPLEMENTED(@_); }
sub insch            { NOTIMPLEMENTED(@_); }
sub delch_at_point   { NOTIMPLEMENTED(@_); }
sub scroll           { NOTIMPLEMENTED(@_); }
sub commit           { NOTIMPLEMENTED(@_); }
sub read_char        { NOTIMPLEMENTED(@_); }


sub dispatch_classmethod {
    my $method = shift @_;

    croak "TLily::FoiledAgain::set_ui has not been called!\n"
        unless defined($UI_CLASS);

    if ($DEBUG) {
        open my $f, '>>', 'uilog' or die;
        print $f "$method(@_)\n";
        close $f;
    }

    no strict 'refs';
    &{"${UI_CLASS}::${method}"}(@_);
}

sub NOTIMPLEMENTED {
    my ($object) = @_;

    my $method = (caller(1))[3];
    $method =~ s/TLily::FoiledAgain:://g;

    if (ref($object) ne $UI_CLASS) {
       confess "$method(@_) not called as an object method of $UI_CLASS!\n";
    } else {
       confess "$method(@_) not implemented by subclass $UI_CLASS.\n";
    }
}

1;
