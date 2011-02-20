# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2002  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::UI;

use strict;
use Carp;

use TLily::UI::Util qw(wrap);
use TLily::Config qw(%config);
use TLily::Registrar;

=head1 NAME

TLily::UI - UI base class.

=head1 SYNOPSIS


use TLily::UI;

=head1 DESCRIPTION

TLily::UI is the base UI class.  All UIs inherit from it.  This document
describes the UI functionality provided by this class and its subclasses.

The UI, once created, will generate user_input events containing the
lines typed by the user in the "text" field..

=head1 FUNCTIONS

=head2 FUNCTIONS DEFINED BY UI.pm:

=over 10

=cut

# List of all UIs, indexed by name.
my %ui;

# Global commands, will be autoregistered into new UIs.
my %gcommand;

# Global bindings, will be autoregistered into new UIs.
my %gbind;

my $gstyle_fn;

=item TLily::UI->new()

Create a new UI object.  This function should only be called by subclasses
of UI.  Takes a hash list containing the "name" parameter as its argument.

    TLily::UI->new(name => 'main');

=cut

sub new {
    my($proto, %a) = @_;
    my $class = ref($proto) || $proto;

    croak "Required UI parameter \"name\" missing."  unless ($a{"name"});
    croak "UI \"$a{name}\" already exists." if (exists $ui{$a{"name"}});

    my $self        = {};
    $self->{"name"} = $a{"name"};

    $ui{$a{"name"}} = $self;

    bless($self, $class);
}

sub purge {
    delete $ui{$_[0]};
}


# Utility function for UI subclasses -- call this during startup to
# inherit all globally-defined bindings.
sub inherit_global_bindings {
    my($self) = @_;

    while (my($command, $func) = each %gcommand) {
        $self->command_r($command, $func);
    }

    my $user_bindings = $config{bindings} || {};
    # The pile of punctuation here just joins to the two hashes into one.
    my %bindings = %{{(%{$user_bindings}, %gbind)}};

    while (my($key, $command) = each %bindings) {
        $self->bind($key, $command);
    }

    $self->istyle_fn_r($gstyle_fn) if ($gstyle_fn);
}


=item name()

When the name() method is called without a parameter, it returns the name
of the UI object it is called upon.  When it is called with a parameter,
it returns the UI object with that name, or the UI object with the name
"main" if no UI object has that name.

    $name = $ui->name();
    $ui = TLily::UI::name($name);

=cut

sub name {
    shift if (@_ > 1);
    my($a) = @_;
    $a ||= "";
    if (ref($a)) {
        return $a->{"name"};
    } else {
        return $ui{$a} || $ui{"main"};
    }
}


sub DESTROY {
    my($self) = @_;
    delete $ui{$self->{"name"}};
}


=item needs_terminal()

Returns true if the UI runs on the terminal, false otherwise.

=cut

sub needs_terminal {
    0;
}

=item printf($fmt, @params)

Identical to C<$ui-E<gt>print(C<sprintf($fmt, C<@params>)>)>.

=cut

sub printf {
    my($self, $s, @args) = @_;
    $self->print(sprintf($s, @args));
};


=item prints($style, $text, ...)

Takes a list of style/text pairs.  Prints each piece of text in the given
style.

    $ui->prints(normal => "This is ",
        em     => "important",
        normal => ".");

=cut

sub prints {
    my($self, @args) = @_;

    while (@args) {
        my ($style) = shift @args;
        my ($text)  = shift @args;

        $self->style($style);
        $self->print($text);
    }
}

=item print(@text)

Sends the text to the UI.

=cut

sub print {
    my $self = shift;
    return if $config{quiet};
    return unless ($self->{log_fh});
    $self->{log_queued} .= join('', @_);
    return unless ($self->{log_queued} =~ s/^(.*\n)//s);
    my $s = $1;
    foreach my $l (wrap($s, cols => 80, 'indent' => $self->{log_indent})) {
        print {$self->{log_fh}} $l, "\n";
    }
    return;
};


=item indent($text)

Sets the current indentation string.  All lines output from this point on
will be prefixed with this string.

=cut

sub indent {
    my($self, $style, $indent) = @_;
    $self->{log_indent} = defined($indent) ? $indent : "";
}

sub log {
    my $self = shift;
    return $self->{log_file} if (@_ == 0);

    my($file) = @_;
    $self->{log_file}   = undef;
    $self->{log_fh}     = undef;
    $self->{log_queued} = "";

    if (defined $file) {
        local *FH;
        open(FH, '>>', $file) or die "$file: $!\n";
        my $fh = select(FH); $|=1; select($fh);
        $self->{log_file} = $file;
        $self->{log_fh}   = *FH;
    }

    return;
}

=item command_r($command, $func)

Registers a named command.  When this command is executed, the command
function will be called with the UI object, command executed, and key
pressed to invoke this command as parameters.

=cut

sub command_r {
    return if (ref($_[0])); # Don't do anything as an object method.
    shift if (@_ > 2);      # Lose the package, if called as a class method.
    my($command, $func) = @_;

    $gcommand{$command} = $func;

    my $ui;
    foreach $ui (values %ui) {
        $ui->command_r($command, $func);
    }

    TLily::Registrar::add("global_ui_command", $command);
    return;
}

=item command_u($command)

Unregisters a named command.

=cut

sub command_u {
    return if (ref($_[0])); # Don't do anything as an object method.
    shift if (@_ > 2);      # Lose the package, if called as a class method.
    my($command) = @_;

    delete $gcommand{$command};

    my $ui;
    foreach $ui (values %ui) {
        $ui->command_u($command);
    }

    TLily::Registrar::remove("global_ui_command", $command);
    return;
}


=item bind($key, $command)

Binds a key to a named command -- when the key is pressed, the command will
be invoked.

=cut

sub bind {
    return if (ref($_[0])); # Don't do anything as an object method.
    shift if (@_ > 2);      # Lose the package, if called as a class method.
    my($key, $command) = @_;

    $gbind{$key} = $command if defined($key) && defined($command);

    my $ui;
    foreach $ui (values %ui) {
        $ui->bind($key, $command);
    }
}


sub istyle_fn_r {
    return if (@_ >= 2 && ref(shift)); # Lose the package, if called as a class
                                       # method.  Don't act as an object method.
    my($style_fn) = @_;

    $gstyle_fn = $style_fn;

    my $ui;
    foreach $ui (values %ui) {
        $ui->istyle_fn_r($style_fn);
    }

    TLily::Registrar::add("global_istyle_fn", $style_fn);
}


sub istyle_fn_u {
    shift if (@_ > 2);      # Lose the package, if called as a class method.
    my($style_fn) = @_;

    $gstyle_fn = undef;

    my $ui;
    foreach $ui (values %ui) {
        $ui->istyle_fn_u($style_fn);
    }

    TLily::Registrar::remove("global_istyle_fn", $style_fn);
}

TLily::Registrar::class_r(global_ui_command => \&command_u);
TLily::Registrar::class_r(global_istyle_fn  => \&istyle_fn_u);

1;

=back

=head2 FUNCTIONS DEFINED BY SUBCLASSES:

=over 10

=item defstyle($style, @attrs)

Defines the given style to have the given attributes on a monochrome display.
Valid attributes are currently "normal", "standout", "underline", "reverse",
"blink", "dim", "bold", "italic", and "altcharset".  Not all UIs will support
all styles.

=item defcstyle($style, $fg, $bg, @attrs)

Defines the given style to have the given color and attributes on a
color display.  Valid colors are "black", "red", "yellow", "blue",
"magenta", and "white".

=item clearstyle

Clears all styles.

=item style($style)

Sets the current style.

=item page($page)

Enables/disables paging.  When called with no argument, returns the current
setting.

=item prompt($prompt)

Sets the current prompt.

=item prompt_for(%args)

This command takes a hash list with three parameters: "prompt", "password",
and "call".  All but "call" are optional.  The UI will ask the user for a
response, and call the function passed as "call" with the UI object and
the text entered as parameters.  If "prompt" is set, it will be used as
a prompt, and if "password" is set, the response will not be echoed to
the screen.

    $ui->prompt_for(prompt => "password:"
            password => 1,
            call => sub { my($ui, $password) = @_; ... });

=item suspend

Temporarily shuts down a UI which uses the terminal.  May have no effect
on UIs which do not use the terminal.

=item resume

Resumes a suspended UI.

=item intercept_r(name => $command, order => $order)

Sets a named command to intercept all keys pressed.  When the command function
is called for a key, if it returns 1, no further action will be taken
for that key.  If it returns false, processing will continue as usual.

Multiple intercept function may be defined at a given time.  The order in
which they are called is determined by the 'order' argument.  The various
command which use key intercepting have the following 'order' values:

    name-self           100
    input-search-mode   100
    paste-mode          900
    leet-mode        950

Observe that it is perfectly ok for more than one function to have the same
order value.  You cannot get into name-self from input-search-mode and vice
versa.

=item intercept_u($command)

Unregisters the given intercept function.  Returns true if $command was
registered as the current intercept function, false otherwise.

=item command($command, $key)

Invokes the given command, with $key as a parameter.

=item get_input

In an array context returns ($point, $text), where $point is the current
location of the input cursor, and $text is the current contents of the
input line.  In a scalar context, returns $text.

=item set_input($point, $text)

Sets the current contents of the input line.

=item bell()

Sounds a bell.

=item dump_to_file($filename)

Dump out the current scrollback buffer to a file.  Return the number of lines
written out.

=back

=head1 COMMANDS

The UI has the concept of named commands.  Commands may be tied to functions
with the command_r() method, which are called when that command is invoked.
Commands may be tied to keys with the bind() method, which then invoke that
command when pressed.  A single command may be designated to intecept all
keystrokes with the intercept() method.

The following example will convert all 'a's input to 'b's.

    sub a_to_b {
        my($ui, $command, $key) = @_;
        $ui->command('insert-self', 'z');
    }
    $ui->command('a-to-b' => \&a_to_b);
    $ui->bind('a' => 'a-to-b');

The 'insert-self' command handles any keys not handled by another command,
and inserts the key it is invoked with into the input line.

=head1 BUGS

The status line needs to be thought out more, fixed up, and documented.

=cut
