#!/usr/bin/perl -w
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/Makefile.PL,v 1.13 2001/11/10 02:36:32 albert Exp $

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

my $fallback_EAGAIN = `$^X tools/find_eagain`;
if ($fallback_EAGAIN =~ /^OK/) {
    print STDERR "Skipping hardcoded EAGAIN...\n";
    undef $fallback_EAGAIN;
} elsif ($fallback_EAGAIN =~ /^FAILED/) {
    print STDERR "Warning: Cannot determine value for EAGAIN.\n";
    undef $fallback_EAGAIN;
} elsif ($fallback_EAGAIN =~ /^(\d+)/) {
    print STDERR "Warning: Hardcoding EAGAIN as $1.\n";
    $fallback_EAGAIN = $1;
};


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
### Copyright (C) 1999-2001  The TigerLily Team, <tigerlily\@tlily.org>
###                             http://www.tlily.org/tigerlily/
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
     TLily::UI::Tk::Event
     TLily::UI::Tk
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
