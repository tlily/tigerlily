#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Registrar.pm,v 1.9 2001/01/26 03:01:48 neild Exp $

package TLily::Registrar;

use strict;

use Carp;

=head1 NAME

Registrar - State tracker

=head1 SYNOPSIS

use TLily::Registrar;

=head1 DESCRIPTION

This class implements a resource tracking mechanism.  A Registrar object
contains a list of allocated resources (registered event handlers, commands,
and so forth).  It is possible to deallocate all resources allocated in
a single Registrar with the unwind() method.

=head1 FUNCTIONS

=over 10

=cut

# All registrars, indexed by name.
my %registrars;

# All resource classes, indexed by name.  Values are deregistration functions.
my %classes;

# The stack of default registrars.  The currently active one is $default[-1].
my @default;


=item Registrar->new()

Creates a new Registrar object.

=cut

sub new {
    my($proto, $name) = @_;
    return $registrars{$name} if ($registrars{$name});
    
    my $class = ref($proto) || $proto;
    my $self  = {};
    $registrars{$name} = $self;
    bless $self, $class;
}


=item $reg->push_default()

Makes the registrar the current default registrar.  A stack of defaults
is maintained; pop_default can be used to unwind this stack.  Returns the
pushed registrar.

=cut

sub push_default {
    my($self) = @_;
    push @default, $self;
    return $self;
}


=item pop_default()

Pops the top entry off the registrar stack.  If called as $reg->pop_default(),
throws an error if the top entry is not $reg.  (Useful for debugging.)

=cut

sub pop_default {
    croak "The registrar stack is out of joint."
      if (ref($_[0]) && ($_[0] ne $default[-1]));
    pop @default;
}


=item default()

Returns the current default registrar, or undef if there is none.

=cut

sub default {
    return @default ? $default[-1] : undef;
}

=item class_r($class, $dereg_fn)

Allocates a class of resources to track.  The $dereg_fn argument gives
a function to call to deregister this particular resource type.  When the
time comes to deregister this resource, this function will be called with
the $data argument passed to the add() method.  (See below.)

    TLily::Registrar::class_r("io_event", \&io_u);

=cut

sub class_r {
    shift if (@_ > 2);
    my($name, $dereg_fn) = @_;
    $classes{$name} = $dereg_fn;
}

=item class_u($class)

Deallocates a resource class.

=cut

sub class_u {
    shift if (@_ > 2);
    my($name) = @_;
    delete $classes{$name};
}

=item $reg->add($class, $data)

Records a resource allocation.

=cut

sub add {
    my $self;
    $self = shift if (@_ > 2);
    $self = ref($self) ? $self : $default[-1];
    return unless $self;
    
    my($class, $data) = @_;
    push @{$self->{$class}}, $data;
}

=item $reg->remove($class, $data)

Records a resource deallocation.

=cut

sub remove {
    my $self;
    $self = shift if (@_ > 2);
    $self = ref($self) ? $self : $default[-1];
    return unless $self;
    
    my($class, $data) = @_;
    @{$self->{$class}} = grep { $_ ne $data } @{$self->{$class}};
}

=item $reg->unwind()

Deallocates all resources allocated in a Registrar object.

=cut

sub unwind {
    my $self = shift;
    $self = ref($self) ? $self : $default[-1];
    return unless $self;
    
    my $class;
    foreach $class (keys %$self) {
	my $data;
	foreach $data (@{$self->{$class}}) {
	    $classes{$class}->($data);
	}
    }
}

=head1 EXAMPLE

    TLily::Registrar::class_r("memory", \&free);

    sub xmalloc {
	my $mem = malloc(@_);
	TLily::Registrar::add("memory", $mem);
	return $mem;
    }

    sub xfree {
	my($mem) = @_;
	TLily::Registrar::remove("memory", $mem);
	free($mem);
    }

    my $reg = Registrar->new();

    my $a = xmalloc(50);
    $reg->push_default();
    my $b = xmalloc(50);
    my $c = xmalloc(50);
    $reg->pop_default();
    my $d = xmalloc(50);

    xfree($a);
    # $a is now freed.

    $reg->unwind();
    # $b is now freed.

=cut

1;
