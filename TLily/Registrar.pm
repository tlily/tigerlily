#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

package TLily::Registrar;

use strict;

use Carp;

=head1 NAME

Registrar - State tracker.

=head1 DESCRIPTION

=head2 FUNCTIONS
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


=item Registrar->pop_default()

Pops the top entry off the registrar stack.  If called as $reg->pop_default(),
throws an error if the top entry is not $reg.  (Useful for debugging.)

=cut

sub pop_default {
    croak "The registrar stack is out of joint."
      if (ref($_[0]) && ($_[0] ne $default[-1]));
    pop @default;
}


=item Registrar->default()

Returns the current default registrar, or undef if there is none.

=cut

sub default {
    return @default ? $default[-1] : undef;
}


sub class_r {
    shift if (@_ > 2);
    my($name, $dereg_fn) = @_;
    $classes{$name} = $dereg_fn;
}


sub class_u {
    shift if (@_ > 2);
    my($name) = @_;
    delete $classes{$name};
}


sub add {
    my $self;
    $self = shift if (@_ > 2);
    $self = ref($self) ? $self : $default[-1];
    return unless $self;
    
    my($class, $data) = @_;
    push @{$self->{$class}}, $data;
}


sub remove {
    my $self;
    $self = shift if (@_ > 2);
    $self = ref($self) ? $self : $default[-1];
    return unless $self;
    
    my($class, $data) = @_;
    @{$self->{$class}} = grep { $_ ne $data } @{$self->{$class}};
}


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

1;
