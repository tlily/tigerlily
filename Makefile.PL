#!/usr/bin/perl -w
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/Makefile.PL,v 1.10 2000/12/16 01:32:59 neild Exp $

use strict;
use Config;
use Symbol;
use Getopt::Long;

#
# Parse options.
#

sub usage {
    print STDERR "Usage: $0 [PREFIX=<path>] [BINDIR=<path>] [ETCDIR=<path>]\n";
    exit 1;
}

my %opts = (PREFIX => "/usr/local",
	    BINDIR => "%PREFIX/bin",
	    ETCDIR => "%PREFIX/lib");

for my $opt (@ARGV) {
    if ($opt =~ /^([^=]+)=(.*)/) {
	$opts{$1} = $2;
    } else {
	usage();
    }
}

$opts{BINDIR} =~ s/\%PREFIX/$opts{PREFIX}/g;
$opts{ETCDIR} =~ s/\%PREFIX/$opts{PREFIX}/g;


#
# EAGAIN is nigh-impossible to determine on many systems.  Give it a try.
#

my $have_eagain;
my $fallback_EAGAIN;

eval { require "Errno"; EAGAIN(); };
if ($@) {
    print STDERR "You don't seem to have a working Errno.ph.\n";
} else {
    $have_eagain = 1;
}

unless ($have_eagain) {
    eval { require "errno.ph"; EAGAIN(); };
    if ($@) {
	print STDERR "It looks as if your errno.ph is broken.\n";
    } else {
	$have_eagain = 1;
    }
}

unless ($have_eagain) {
    print STDERR "Trying to compile a program to tell us what EAGAIN is...\n";
    my $fh = gensym;
    open(F, ">/tmp/en.c") or die "/tmp/en.c: $!\n";
    print F <<END
#include <stdio.h>
#include <sys/errno.h>

int main() {
    printf("EAGAIN=\%d\\n", EAGAIN);
    return 0;
}
END
  ;
    close F;
    system($Config{cc}, "/tmp/en.c", "-o", "/tmp/en");
    if (`/tmp/en` =~ /EAGAIN=(\d+)/) {
	$fallback_EAGAIN = $1;
	print STDERR "Using $fallback_EAGAIN.\n";
    } else {
	print STDERR "That didn't work.  I fear you may be out of luck.\n";
    }
}


#
# Build the tlily binary.  (tlily.plx)
#

my $tlily = "tlily.plx";

my $out = gensym;
open($out, ">$tlily") or die "$tlily: $!\n";

my $PERL = $Config{'startperl'} ? $Config{'startperl'}     : 
           $Config{'perlpath'}  ? "#!".$Config{'perlpath'} :
                                  "#/usr/bin/perl";
print $out $PERL, "\n\n";
print $out <<END
##########################################################################
##########################################################################
###
### Tigerlily:  A client for the lily CMC, written in Perl.
### Copyright (C) 1999  The TigerLily Team, <tigerlily\@einstein.org>
###                             http://www.hitchhiker.org/tigerlily/
###
### This program is free software; you can redistribute it and/or modify it
### under the terms of the GNU General Public License version 2, as published
### by the Free Software Foundation; see the included file COPYING.
###
##########################################################################
##########################################################################


##########################################################################
### Configuration section
###

# Tigerlily will look for the "tlily.site" file in this directory.
\$::TL_ETCDIR = "$opts{ETCDIR}";

# Tigerlily will load extensions from this directory.
\$::TL_EXTDIR = "//INTERNAL/extensions";

# Tigerlily library directory.
\$::TL_LIBDIR = "//INTERNAL/lib";

# Tigerlily modules directory.
\$::TL_LIBMODDIR = "//INTERNAL";
END
  ;

if (defined $fallback_EAGAIN) {
    print $out <<END

# Fallback value for EAGAIN, if it cannot be determined by other means.
\$::fallback_EAGAIN = $fallback_EAGAIN;
END
  ;
}

print $out <<END

###
### End of user-configurable data.  Do not edit below this line.
##########################################################################

END
  ;

my @modules =
  qw(
     TLily::ExoSafe
     TLily::Config
     TLily::Registrar
     TLily::Event
     TLily::UI::Util
     TLily::UI::Curses::Generic
     TLily::UI::Curses::Input
     TLily::UI::Curses::StatusLine
     TLily::UI::Curses::Text
     TLily::UI
     TLily::Utils
     TLily::User
     TLily::Extend
     TLily::Version
     TLily::Server
     TLily::Server::SLCP
     TLily::Server::HTTP
     TLily::Daemon
     TLily::Daemon::Connection
     TLily::Daemon::HTTP
     TLily::Bot
     TLily::UI::Curses
    );

my %added;

sub writeperl {
    my($file) = @_;

    my $fh = gensym;
    open($fh, $file) or die "$file: $!\n";

    print $out "#line 0 $file\n";

    my $inpod = 0;
    while (<$fh>) {
	if (/^__(?:END|DATA)__/) {
	    last;
	}
	if ($inpod) {
	    if (/^=cut/) {
		$inpod = 0;
	    }
	} else {
	    if (/^=/) {
		$inpod = 1;
	    } elsif (/^use\s+(TLily::[^\s;\(]+)(.*)/) {
		print "$file depends on $1\n" unless $added{$1};
		print $out "BEGIN { import $1$2 }\n";
	    } elsif (/^\@(?:ISA|EXPORT|EXPORT_OK|EXPORT_TAGS)\s*=/) {
		print $out "BEGIN {\n    $_}\n";
	    } else {
		print $out $_;
	    }
	}
    }
}

for my $module (@modules) {
    $added{$module} = 1;

    my $file = $module . ".pm";
    $file =~ s|::|/|g;

    print $out "{\n";
    writeperl($file);
    print $out "}\n";
}

print $out "{\n";
print $out "package main;\n";
writeperl("tlily.PL", 1);
print $out "}\n";

print $out "__END__\n";

for my $f (<extensions/*.pl>) {
    #next unless ($f =~ /^extensions\/(.*\.pl$/);
    #my $name = $1;

    print $out "#### EMBEDDED \"$f\"\n";
    writeperl($f);
    print $out "#### END\n";
}

print $out "#### EMBEDDED \"lib/tlily.global\"\n";
writeperl("tlily.global");
print $out "#### END\n";

close $out;

chmod(0777, $tlily);

print "Tigerlily executable built as \"$tlily\".\n";
