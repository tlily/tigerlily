#!/usr/bin/perl
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2003  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

use strict;
use Config;
use ExtUtils::MakeMaker;
use Getopt::Long;
use lib qw(lib);
use TLily::Version;

use vars qw($current $opt_p $opt_w 
	$TL_PREFIX $TL_BINDIR $TL_LIBDIR $TL_ETCDIR $TL_MANDIR);

$current=0; $opt_w=0;
GetOptions("help|h"   => \&Usage,
	   "current|c"   => \$current,
	   "warn|w"   => \$opt_w,
	   "prefix|p=s" => \$opt_p) or die "Error parsing options";

sub Usage {
    print STDERR "Usage: $0 [-help|-h][-current|-c][-warn|-w][-prefix dir|-p dir]\n",
	"    -help or\n",
	"    -h               : This help.\n",
	"    -current or\n",
	"    -c               : Configure tlily for use in the current dir.\n",
	"    -warn or\n",
	"    -w               : Enable -w on the perl command line in tlily\n",
	"    -prefix <dir> or : Configure tlily for installation\n",
	"    -p <dir>         : under <dir>\n";
    exit(0);
}

sub ask_dirs {
    if($current) {
	print "Configuring for use in the current directory.\n";
	$TL_PREFIX = ".";
	$TL_BINDIR = $TL_PREFIX;
	$TL_LIBDIR = "lib";
	$TL_ETCDIR = $TL_PREFIX;
	$TL_MANDIR = $TL_PREFIX;
	return;
    } elsif($opt_p) {
	print "Configuring to use installation prefix $opt_p\n";
	$TL_PREFIX = tilde_expand($opt_p);
	$TL_BINDIR = "$TL_PREFIX/bin";
	$TL_LIBDIR = "$TL_PREFIX/lib/tlily";
	$TL_ETCDIR = "$TL_PREFIX/etc";
	$TL_MANDIR = "$TL_PREFIX/man";
	return;
    } else {
	$TL_PREFIX='/usr/local';
	print qq(By default, tlily will be installed in $TL_PREFIX/bin, global extensions
under $TL_PREFIX/lib/tlily/extensions, etc..., i.e. with
$TL_PREFIX as prefix for all installation directories.  It is typically
set to /usr/local, but you may choose /usr if you wish to install
tlily among your system binaries.  If you wish to have binaries under
/bin but support files under /usr/local/lib, that's ok: you will be
prompted separately for each of the installation directories, the
prefix only used to set the defaults.

Use an installation prefix of 'current' or the -c command line option
to configure tlily for use in the current directory only.

);

	my $inp = ask("Installation prefix to use?", $TL_PREFIX);
	if($inp) {
	    if($inp =~ /current/i) {
		print "Configuring for use in the current directory.\n";
		$TL_PREFIX = ".";
		$TL_BINDIR = $TL_PREFIX;
		$TL_LIBDIR = "$TL_PREFIX/lib";
		$TL_ETCDIR = $TL_PREFIX;
		$TL_MANDIR = $TL_PREFIX;
		return;
	    }
	    $TL_PREFIX=tilde_expand($inp);
	}
        $TL_PREFIX = $TL_PREFIX;
	
	$TL_BINDIR=$TL_PREFIX."/bin";
	$inp = ask("\nInstallation directory for the tlily script?",
	    $TL_BINDIR);
	$TL_BINDIR=tilde_expand($inp);
		
	$TL_LIBDIR = $TL_PREFIX."/lib/tlily";
	print "\nInstallation directory for the tlily support files?  (This",
	    " is where the\ninternal TLily library, the global extensions, ",
	    "and the global configuration\n";
	$inp = ask("file will be installed.)", $TL_LIBDIR);
	$TL_LIBDIR=tilde_expand($inp);

	$TL_ETCDIR = $TL_PREFIX."/etc";
	$inp = ask("\nInstallation directory for the site-specific ".
	    "configuration file 'tlily.site'?", $TL_ETCDIR);
	$TL_ETCDIR=tilde_expand($inp);

        $TL_MANDIR = $TL_PREFIX."/man";
	$inp = ask("\nInstallation directory for the manual pages for tlily".
	    " and its internals?", $TL_MANDIR);
	$TL_MANDIR = tilde_expand($inp);
    }
}

sub tilde_expand {
    my($inp) = @_;
    my @inp = split('/', $inp);

    my $elem;
    foreach $elem (@inp) {
	if($elem eq '~') {
	    my $dir = (getpwuid($>))[7];
	    if(!$dir) {
		print "No home directory for uid ", $>, ", ignoring ~.\n";
		next;
	    }
	    $elem = $dir;
	}
	elsif($elem =~ /~(\w+)/o) {
	    my $dir = (getpwnam($1))[7];
	    if(!$dir) {
		print "No home directory for user $1, ignoring ~$1.\n";
		next;
	    }
	    $elem =~ s/~(\w+)/$dir/;
	}
    }
    join("/", @inp);
}

sub ask {
    local $|=1;
    my($q,$d) = @_;
    if(length($q. " [". $d. "]: ") > 80) {
        print $q,"\n[", $d, "]: ";
    }
    else {
        print $q, " [", $d, "]: ";
    }
    my $l = <STDIN>;
    chomp $l;
    $l eq '' ? $d : $l;
}

ask_dirs();


my $prereq;

if ($^O eq 'MSWin32') {
    $prereq = {
	'Win32::Console' => 0,
	'Win32::Sound'   => 0
    };
} else {
    $prereq = {
        'Curses'         => 0
    };    
}

# support 5.6(MM5) and 5.8(MM6)
my @incompat_options;
if($ExtUtils::MakeMaker::VERSION >= 6) {
    @incompat_options = (
	INSTALLSITEBIN      => $TL_BINDIR,
	INSTALLSITEMAN1DIR  => $TL_MANDIR."/man1",
	INSTALLSITEMAN3DIR  => $TL_MANDIR."/man3",);
} else {
    @incompat_options = (
	INSTALLBIN      => $TL_BINDIR,
	INSTALLMAN1DIR  => $TL_MANDIR."/man1",
	INSTALLMAN3DIR  => $TL_MANDIR."/man3",);
}

WriteMakefile(
    NAME	    => 'TLily',
    DISTNAME        => 'tlily',
    VERSION_FROM    => 'lib/TLily/Version.pm',
    EXE_FILES       => [ 'tlily' ],
    PMLIBDIRS       => [qw(extensions lib/TLily)],
    PREREQ_PM       => $prereq,
    
    PL_FILES        => { 'tools/build_tlily' => [ 'tlily', 
	                                          'tlily.curses.plx',
                                                  'tlily.tk.plx',	
                                                  'tlily.win32.plx' ] },
    
    INSTALLDIRS     => 'site',
    INSTALLSITELIB  => $TL_LIBDIR,
    INSTALLSITEARCH => $TL_LIBDIR,

    INSTALLSCRIPT   => $TL_BINDIR,

    @incompat_options,

    dist            => { COMPRESS => 'gzip -9 -f', SUFFIX => 'gz' },
    realclean       => { FILES => 'MANIFEST.bak Makefile.old' },
    clean           => { FILES => 'tlily tlily.win32.plx tlily.tk.plx '
                                . 'tlily.curses.plx' },
);

sub MY::install {
    package MY; # so that "SUPER" works right
    my $inherited = shift->SUPER::install(@_);
    if($inherited =~ /^\s*install\s*::/) {
	$inherited =~ s/\s*doc_install\s*$//m;
    }
#    $inherited =~ s/(read|write).*packlist//mg;
#    $inherited =~ s/\@\$\(UNINSTALL\).*packlist//mg;
#    $inherited =~ s|\$\(\S+\)/auto/\$\(\S+\)||mg;
#    $inherited =~ s|\$\(INST_ARCHLIB\)\s+\$\(INSTALLSITEARCH\)\s+|\$\(INST_ETC\) \$\(INSTALLSITEETC\) |m;
    $inherited =~ s|(\$\(INST_ARCHLIB\)\s+\$\(INSTALLSITEARCH\).*$)|$1\n\t\t\$\(INST_ETC\) \$\(INSTALLSITEETC\) \\|m;
    $inherited;
}

sub MY::processPL {
    package MY; # so that "SUPER" works right
    my $inherited = shift->SUPER::processPL(@_);
    my @inherited = split(/\n/, $inherited);
    my $f;
    foreach (@inherited) {
	s|(tools/build_tlily\s+tlily\S*)|$1 TL_ETCDIR=$::TL_ETCDIR TL_LIBDIR=$::TL_LIBDIR|g;
    }
    join("\n", @inherited)."\n";
}

sub MY::postamble {
    return <<"ETCDIR" . <<'SETUP_CONFIG';
INSTALLSITEETC=$main::TL_ETCDIR
ETCDIR
INST_ETC=./blib/etc
TL_SITE_CF=$(INST_ETC)/tlily.site
TL_GLOBAL_CF=$(INST_LIBDIR)/tlily.global

all :: $(TL_SITE_CF) $(TL_GLOBAL_CF)

$(INST_ETC):
	@$(MKPATH) $(INST_ETC)
	-@$(CHMOD) 755 $(INST_ETC)

$(TL_SITE_CF): $(INST_ETC)
	echo "Writing tlily.site"
	echo '# Site configuration file for TigerLily.' > $(TL_SITE_CF)
	echo '# Please edit this, NOT the global configuration file.' >> $(TL_SITE_CF)
	-$(CP) $(INSTALLSITEETC)/tlily.site $(TL_SITE_CF)
	$(CHMOD) 644 $(TL_SITE_CF)

$(TL_GLOBAL_CF):
	-$(RM_F) $(TL_GLOBAL_CF)
	$(CP) lib/tlily.global $(TL_GLOBAL_CF)

release:
	@echo "Please use tools/makerelease to make a release."
SETUP_CONFIG
}

sub MY::libscan {
    my($self, $path) = @_;
    return '' if $path =~ m:\binfobot-:;
    $path;
}
