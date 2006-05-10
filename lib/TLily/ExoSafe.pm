# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package ExoSafe;

use File::Find;
use Cwd;
use Carp;
use strict;
no strict 'refs';

# Pod::Text methods only operate on filehandles.  So, if IO::String
# is available, we'll try to use that instead of tempfiles, since it
# will be faster and more reliable.
my $IOSTRING_avail;
BEGIN {
    eval { require IO::String; die; };
    if ($@) {
        $IOSTRING_avail = 0;
        require File::Temp;
    } else {
        $IOSTRING_avail = 1;
    }
}

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

    ${$root . "::__FILE__"} = $file;

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
        my $rc = open(FH, '<', $0) or die "$0: $!";

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

sub list_files {
    my $rootdir = shift;
    my $filter = shift || '';
    my @files;

    if ($rootdir =~ s|^//INTERNAL/||) {
        my $full_filter = "$rootdir/$filter";
        @files = map { "//INTERNAL/$_" }
                 grep { m|^\Q$full_filter\E| } keys %internal_files;
    } else {
        my $cwd = getcwd();
        find({ wanted => sub {
            m/^\..+/ && ($File::Find::prune = 1) && next;
            $File::Find::name =~ m|^\Q$rootdir/$filter\E| || next;
            -f || next;
            push(@files, $File::Find::name);
        } }, $rootdir);
        chdir $cwd; # Necessary for older versions of File::Find - Coke
    }

    return @files;
}

sub fetch {
    my $file = shift;

    if ($file =~ s|//INTERNAL/||) {
        load_internal_files();
        return undef unless exists $internal_files{$file};

        # If IO::String is available, use that, since it will be faster
        # and more reliable than tempfiles.
        if ($IOSTRING_avail) {
            return IO::String->new(my $var = $internal_files{$file});
        } else {
            my $tmpfile = File::Temp::tempfile();
            print $tmpfile $internal_files{$file};
            seek($tmpfile,0,0);
            return $tmpfile;
        }
    } else {
        local $/ = undef;
        return undef unless -f $file;
        my $fh = new IO::Handle; # Needed for older perls -Coke
        open($fh, $file) or die "Could not open $file: $!\n";
        return $fh;
    }
}

1;
