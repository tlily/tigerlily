# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/ExoSafe.pm,v 1.6 2000/12/16 01:32:59 neild Exp $

package ExoSafe;

use Carp;
use strict;
no strict 'refs';

# Originally hacked out of Safe.pm by Chistopher Masto.
# Expanded and fitted into tigerlily by Matthew Ryan

# This is a trimmed-down version of Safe.pm.  It provides only the
# namespace seperation, not the opcode control, since tlily doesn't
# need opcode control, and it interferes with calls to 'use' and the
# _ pseudo filehandle.

my $default_root = 0;
my %internal_files;

sub new {
    my $class = shift;
    my $self = bless({ }, $class);
    $self->{Root} = "ExoSafe::Root" . $default_root++;
    return $self;
}

sub share {
    my ($self, @vars) = @_;
    $self->share_from(scalar(caller), \@vars);
}

sub share_from {
    my $self = shift;
    my $pkg = shift;
    my $vars = shift;
    my $root = $self->{Root};
    my ($var, $arg);
    croak("vars not an array ref") unless ref $vars eq 'ARRAY';
    # Check that 'from' package actually exists
    croak("Package \"$pkg\" does not exist")
      unless keys %{"$pkg\::"};
    foreach $arg (@$vars) {
	# catch some $safe->share($var) errors:
	croak("'$arg' not a valid symbol table name")
	  unless $arg =~ /^[\$\@%*&]?\w[\w:]*$/
	    or $arg =~ /^\$\W$/;
	($var = $arg) =~ s/^(\W)//; # get type char
	# warn "share_from $pkg $1 $var";
	*{$root."::$var"} = ($1 eq '$') ? \${$pkg."::$var"}
                      : ($1 eq '@') ? \@{$pkg."::$var"}
                      : ($1 eq '%') ? \%{$pkg."::$var"}
                      : ($1 eq '*') ?  *{$pkg."::$var"}
                      : ($1 eq '&') ? \&{$pkg."::$var"}
                      : (!$1)       ? \&{$pkg."::$var"}
                      : croak(qq(Can't share "$1$var" of unknown type));
    }
}

sub rdo {
    my ($self, $file) = @_;
    my $root = $self->{Root};
    my $subref;

    if ($file =~ s|^//INTERNAL/||) {
	load_internal_files();
	die "cannot open \"$file\"" unless defined($internal_files{$file});
	my $evalcode = sprintf('package %s; sub { eval $internal_files{$file}; }', $root);
	{ no strict; $subref = eval $evalcode; }
    } else {
	$subref = eval "package $root; sub { do \$file }";
    }

    return &$subref;
}

sub reval {
    my ($self, $expr) = @_;
    my $root = $self->{Root};
    my $evalcode = sprintf('package %s; sub { eval $expr; }', $root);
    my $subref = eval $evalcode;
    return &$subref;
}

sub symtab {
    my ($self) = @_;
    my $root = $self->{Root};
    #print "package $root; sub { eval '*${root}::' }\n";
    #my $subref = eval "package $root; sub { eval '*${root}::' }";
    #return &$subref;
    return eval "package $root; *${root}::";
}

sub load_internal_files {
    if (keys %internal_files == 0) {
	local *FH;
	my $rc = open(FH, $0) or die "$0: $!";
	
	my $name;
	my $data = "";
	while (<FH>) {
	    if (defined($name)) {
		if (/^\#\#\#\# END/) {
		    $internal_files{$name} = $data;
		    $data = "";
		    undef $name;
		} else {
		    $data .= $_;
		}
	    } else {
		if (/^\#\#\#\# EMBEDDED \"([^\"]+)\"/) {
		    $name = $1;
		}
	    }
	}
    }
}

1;
