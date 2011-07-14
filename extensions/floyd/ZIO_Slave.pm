# NOTES
#
# This is not a REMOTELY correct IO module.  I'm trying to implement JUST
# ENOUGH so that I can play some old infocom games through tlily.  Do not
# use this as a model.  It's wrong in some ways-- but it works
#  --Josh Wilmes <josh@hitchhiker.org>
#
# Here's the basic methodology:
# @screen has one element per screen row, each of which is a string.   The
# screen is fixed-size, at 76x24. (for wrapping purposes)
#
# In addition, the @flushed array has one element per screen line, which is
# a 1 or 0, indicating whether that screen line has been sent to the user.
#
# When we see it printing what looks like a prompt (something matching the
# prompt regexp below), we sweep up from the bottom of the screen until we
# find a line which was already sent to the user, and then stop.  The resulting
# lines are then grouped together into a send to the user and marked 'flushed'.
#
# scrolling is handled by the newline function as well.

package ZIO_Slave;

my $debug  = 0;
my $init   = 0;
my $prompt = "^\s*\>\s*\$";
my $end    = 0;

use strict;

use Games::Rezrov::GetKey;
use Games::Rezrov::GetSize;
use Games::Rezrov::ZIO_Tools;
use Games::Rezrov::ZIO_Generic;

use vars qw(@ISA);
@ISA = qw(Games::Rezrov::ZIO_Generic);

my ($rows, $columns);

my @screen;
my @flushed;
my $abs_x = 0;
my $abs_y = 0;
my $in_other_window = 0;
my $split_line = 0;

$|=1;

sub new {
    my ($type, %options) = @_;
    my $self = new Games::Rezrov::ZIO_Generic();
    bless $self, $type;

    ($columns, $rows) = (76, 24);

    $self->clear_screen();

    return $self;
}

sub write_string {
    my ($self, $string, $x, $y) = @_;
    return if $in_other_window;

    $self->absolute_move($x, $y) if defined($x) and defined($y);

    if ($string =~ /$prompt/) {
        # we treat prompts specially, eating them up and sending out any
        # unflushed output

        print "WRITE_STRING($abs_x,$abs_y) [PROMPT]: $string\n" if $debug;

        $self->flush_output();
    } else {
        print "WRITE_STRING($abs_x,$abs_y): $string\n" if $debug;

        # otherwise, add it to the screen
        substr($screen[$abs_y],$abs_x) = $string;
        $flushed[$abs_y] = 0;
        $abs_x += length($string);
    }
}

sub flush_output {
    my @out;
    my $a;
    for (0..$rows-1) {
        my $l = $rows-1-$_;
        last if ($_ > 0 && $flushed[$l]);
        push @out, $screen[$l] if (! $flushed[$l]);
        $flushed[$l] = 1;
    }

    my $send = "";
    foreach (reverse @out) {
        $send .= "$_\n";
    }
    $send =~ s/[\n\s]*$//g;
    $send =~ s/^[\n\s]*//g;
    $send = wrap_lines($send);
    print "#\$# SEND $send\n" if $send;
    if ($send eq "*** End of session ***") {
        $end = 1;
    }
}


sub clear_to_eol {
    my ($self) = @_;
    return if $in_other_window;

    print "CLEAR_TO_END\n" if $debug;

    my $diff = $columns - $abs_x;
    if ($diff > 0) {
        substr($screen[$abs_y],$abs_x, $diff) = " " x $diff;
        $flushed[$abs_y] = 0;
    }
}


sub update {
    print "UPDATE\n" if $debug;
}

sub can_split {
    # true or false: can this zio split the screen?
    return 1;
}

sub split_window {
    my ($self, $line) = @_;

    $split_line = $line;
}

sub can_change_title {
    return 1;
}

sub set_game_title {
    print "#\$# RETITLE $_[1]\n";
}


sub set_version {
    my ($self, $status_needed, $callback) = @_;
    print "SET_VERSION\n" if $debug;
    Games::Rezrov::StoryFile::rows($rows);
    Games::Rezrov::StoryFile::columns($columns);
    $self->clear_screen();
    return 0;
}

sub absolute_move {
    my ($self, $nx, $ny) = @_;
    return if $in_other_window;
    return if ($ny <= $split_line);

    print "ABSOLUTE_MOVE($nx,$ny)\n" if $debug;

    $abs_x = $nx;
    $abs_y = $ny;
}

sub newline {
    my ($self) = @_;
    return if $in_other_window;

    print "NEWLINE\n" if $debug;

    if ($abs_y >= $rows - 1) {
        # cursor is at bottom of screen; scroll needed
        my $str = shift @screen;
        my $flushed = shift @flushed;

        # add a new line at the bottom.
        push @screen, "";
        push @flushed, 0;
    } else {

        $abs_y++;
    }

    $abs_x = 0;
    Games::Rezrov::StoryFile::register_newline();
}

sub write_zchar {
    return if $in_other_window;
    $_[0]->write_string(chr($_[1]));
}

sub get_input {
    my ($self, $max, $single_char, %options) = @_;

    $self->flush_output();

    if ($single_char) {
          print "#\$# INPUT CHAR\n";
        if ($end) {
            $end = 0;
            return " ";
        }
    } else {
          print "#\$# INPUT LINE\n";
    }
    my $input = <STDIN>;

    chomp($input);
    return $input;
}

sub get_position {
    print "GET_POSITION => $abs_x,$abs_y\n" if $debug;
    my ($self, $sub) = @_;
    if ($sub) {
        return sub { };
    } else {
        return ($abs_x, $abs_y);
    }
}

sub clear_screen {
    my ($self) = @_;
    return if $in_other_window;

    $self->flush_output() if ($init);
    $init=1;

    print "CLEAR_SCREEN\n" if $debug;

    for (0..25) {
        $screen[$_] = " " x $columns;
        $flushed[$_] = 0;
    }
}

sub status_hook {
    my ($self, $when) = @_;

    # 0 = before
    # 1 = after

    if ($when == 0) {
        $in_other_window = 1;
    } else {
        $in_other_window = 0;
    }
}

sub set_window {
    my ($self, $window) = @_;
    print "SET_WINDOW: $window\n" if $debug;

    $self->SUPER::set_window($window);
    if ($window != Games::Rezrov::ZConst::LOWER_WIN) {
        $in_other_window=1;
        # ignore output except on lower window
        unless ($self->warned()) {
            $self->warned(1);
            my $pb = Games::Rezrov::StoryFile::prompt_buffer();
            $self->newline();
            Games::Rezrov::StoryFile::set_window(Games::Rezrov::ZConst::LOWER_WIN);
            my $message = "WARNING: this game is attempting to use multiple windows, which this interface can't fully handle.";
            $self->newline();
            $self->SUPER::buffer_zchunk(\$message);
            Games::Rezrov::StoryFile::flush();
            $self->newline();
            Games::Rezrov::StoryFile::prompt_buffer($pb) if $pb;
            $self->clear_screen();
            Games::Rezrov::StoryFile::set_window($window);
        }
    } else {
        $in_other_window=0;
    }
}

sub cleanup {
    print "CLEANUP\n" if $debug;
}

sub warned {
    return (defined $_[1] ? $_[0]->{"warned"} = $_[1] : $_[0]->{"warned"});
}

# format messages with space so a multi-line send looks ok on a normal 80
# column client.
sub wrap_lines {
    my ($str) = @_;
    my $ret;

    return $str unless ($str =~ /\n/);

    foreach (split /\n/, $str) {
        $ret .= $_;
        $ret .= " " x (76 - length($_));
    }

    $ret =~ s/\s*$//g;

    return($ret);
}

1;
