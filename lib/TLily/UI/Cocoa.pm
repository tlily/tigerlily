# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::UI::Cocoa;

use strict;
use vars qw($AUTOLOAD @ISA $a $b); #) cperl mode is getting confused.
use Carp;

use Foundation;
use Foundation::Functions;
use AppKit;
use AppKit::Functions;

use TLily::Event;

our @ISA = qw(Exporter TLily::UI);

#XXX There is a lot of stuff missing from TLily::UI right now.

our %OBJC_EXPORT;

sub new {
    my ($proto,$ui,$name) = @_;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new('name' => $name);

    # Outlets - Need to predeclare these for CB magic.
    for my $predefine (qw/Window Screen StatusLeft StatusCenter StatusRight Entry/)  {
        $self->{$predefine} = undef;
    }

    bless($self,$class);

    $self->{'NSWindowController'} = NSWindowController->alloc->initWithWindowNibName_owner("MainWindow", $self);
    $self->{'NSWindowController'}->window;

    $self->{indent} = "";
    $self->{_timer} = NSTimer->scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(0.25, $self, 'doTlilyEvent:', $self, 1);

    return $self;
}

# XXX this is a selector for when input occurs. name seems conflict-prone
sub input {
  my ($self,$sender) = @_;

  $self->{'Screen'}->insertText($sender->stringValue."\n");

  my $text = $sender->stringValue;
  # If we're prompting, we should strip it off before sending the event.
    if ($self->{prompt}) {
        $text =~ s/^\Q$self->{prompt}->[0]->{prompt}\E//g;
    } else {
      $self->print($text."\n");
    }

    TLily::Event::send(type => 'user_input',
                   ui   => $self,
                   text => $text);
  delete $self->{prompt};
  $sender->setStringValue("");

  $sender->becomeFirstResponder();
}

sub reportBug {
    system("open http://www.centauri.org/cgi-bin/tigerlily");
}

$OBJC_EXPORT{'doTlilyEvent:'} = { args=>'@', 'return'=>'c'};
sub doTlilyEvent {
# Need to integrate tlily's event loop with NSapp's run loop.
# While it would be nice to rework Tlily::Event to be more NS-ishy,
# It should be possible to setup a timer and just run the tlily events
# as they come in.
    my ($self) = shift;
    eval { TLily::Event::loop_once; };
   if ($@ =~ /^Undefined subroutine/) {
        $self->print("ERROR: ", $@);
        next;
    } elsif ($@) {
        die "$@";
    }
}

#this don't work.
$OBJC_EXPORT{'keyDown:'} = {args=>'@', 'return' => 'c'};
sub keyDown {
  print "KEYDOWN\n";
  use Data::Dumper;print Dumper(@_);
}

sub bell {
    NSBeep();
}

sub define {
    # print "DEFINE\n";
    my($self, $name, $pos) = @_;
    push (@{$self->{statuspositions}}, {name => $name, pos =>$pos});
}

sub set {

    my($self, $name, $val) = @_;
    $self->{statusvalues}->{$name} = $val;
    my $self = shift;
    my (@left,@center,@right);
    foreach my $foo (@{$self->{statuspositions}}) {
        my $value = $self->{statusvalues}->{$foo->{name}};
        my $pos = $foo->{pos};
        next if $value eq "";
        if ($pos eq "override") {
            @left=@right=@center=();
            push @center,$value;
            last;
        } elsif ($pos eq "left") {
            unshift @left, $value;
        } elsif ($pos eq "center") {
            unshift @center, $value;
        } elsif ($pos eq "right") {
            unshift @right, $value;
        }
    }
    my $sep = " | ";

    $self->{StatusLeft}->setEditable(1);
    $self->{StatusCenter}->setEditable(1);
    $self->{StatusRight}->setEditable(1);
    $self->{StatusLeft}->setStringValue(join($sep,@left));
    $self->{StatusCenter}->setStringValue(join($sep,@center));
    $self->{StatusRight}->setStringValue(join($sep,@right));
    $self->{StatusLeft}->setEditable(0);
    $self->{StatusCenter}->setEditable(0);
    $self->{StatusRight}->setEditable(0);
}

sub print {
    my ($self,@text) = @_;
    $self->{Screen}->setEditable(1);

    # If we ended on a newline last time, print the indent.
    if (! $self->{_noIndent}) {
        $self->{Screen}->insertText($self->{_indent}->[1]);
    }

    my $text = join("",@text);
    # Trim off the last \n.
    my $trim = 0;
    if ($text =~ s/\n$//) {
        $trim = 1;
    }

    # If we didn't end with a \n, then we don't need to print the indent next time through.
    if ($trim) {
        $text .= "\n";
        $self->{_noIndent} = 0;
    } else {
        $self->{_noIndent} = 1;
    }


    #$text =~ s/\n/\n$self->{_indent}->[1]/g;
    $self->{Screen}->insertText($text);

    $self->{Screen}->setEditable(0);
}

sub prompt {
    my ($self,$prompt) = @_;
    $self->{Entry}->setStringValue($prompt . $self->{Entry}->stringValue);
}

sub prompt_for {
    my($self, %args) = @_;
    croak("required parameter \"call\" missing.") unless ($args{call});

    push @{$self->{prompt}}, \%args;
    return if (@{$self->{prompt}} > 1);

    $self->prompt($args{prompt}) if (defined($args{prompt}));
    $self->password(1) if ($args{password});
    return;
}

sub populate_statusbar {
    #print "POPULATE STATUSBAR\n";
    my($self) = @_;
    foreach my $var (@{$self->{statuspositions}}) {
        $self->define($var->{name}, $var->{pos});
    }
    foreach my $key (keys(%{$self->{statusvalues}})) {
        $self->set($key, $self->{statusvalues}->{$key});
    }
}

sub clear_statusbar {
   #print "CLEAR STATUSBAR\n";
    my($self) = @_;
    foreach my $var (@{$self->{statuspositions}}) {
        $self->{status}->define($var->{name}, 'nowhere');
    }
}

sub indent {
    my ($self,@indent) = @_;
    $self->{_indent} = [ @indent ];
}

# XXX had pulled this out of status for some reason.
# It may be able to go back in there.

sub redraw {
   #print "REDRAW\n";
}

# XXX Don't use Autoload for this hack, since the OBCJ stuff wants it.
# This list is very likely overly long.
my @noimplementation = qw/about accept_line bind build_string clearstyle close_window command command_r co
mmand_u configure dump_to_file force_redraw get_input insert_self intercept_r in
tercept_u istyle_fn_r istyle_fn_u layout make_active mark_output needs_terminal
next_history next_line not_supported password previous_history replacing resume
run search_history set_input size_request split_window splitwin start_curses sto
p_curses suspend switch_window ui_bindings update_input wrap style defstyle defcstyle page/;

foreach my $foo (@noimplementation) {
    eval "sub $foo { _writeit(\"$foo\");}"
}

my %stuff;
{
sub _writeit {
  return if $stuff{$_[0]};
  $stuff{$_[0]} = 1;
  NSLog("$_[0] is not implemented\n");
}
}
1;
