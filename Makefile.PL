#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/Makefile.PL,v 1.4 1999/03/24 00:55:38 albert Exp $

use ExtUtils::MakeMaker;

# Configurable Section
#$PREFIX   = '/usr/local';
#$TL_BINDIR = '/usr/local/bin';
#$TL_LIBDIR = '/usr/local/lib/tlily';
#$TL_MANDIR = '/usr/local/man';
$PREFIX   = '/home/albert/src/inst';
$TL_BINDIR = $PREFIX.'/bin';
$TL_LIBDIR = $PREFIX.'/lib/tlily';
$TL_MANDIR = $PREFIX.'/man';



WriteMakefile(
    NAME	    => 'TLily',
    DISTNAME        => 'tlily',
    VERSION_FROM    => 'TLily/Version.pm', # finds $VERSION
    PL_FILES        => { 'tlily.PL' => 'tlily'},
    EXE_FILES       => [ 'tlily' ],
    PMLIBDIRS       => [qw(extensions TLily)],
    PREREQ_PM       => { 'Curses'         => 0,
			 'Term::ReadLine' => 0 },

    INSTALLDIRS     => 'site',
    INSTALLSITEARCH => $TL_LIBDIR,
    INSTALLSITELIB  => $TL_LIBDIR,
    INSTALLSCRIPT   => $TL_BINDIR,
    INSTALLMAN1DIR  => $TL_MANDIR."/man1",
    INSTALLMAN3DIR  => $TL_MANDIR."/man3",
    dist            => { COMPRESS => 'gzip -f', SUFFIX => 'gz' },
    realclean       => { FILES => 'MANIFEST.bak Makefile.old' },
    clean           => { FILES => 'tlily' },
);

sub MY::install {
    package MY; # so that "SUPER" works right
    my $inherited = shift->SUPER::install(@_);
    if($inherited =~ /^\s*install\s*::/) {
	$inherited =~ s/\s*doc_install\s*$//m;
    }
    $inherited =~ s/(read|write).*packlist//mg;
    $inherited =~ s/\@\$\(UNINSTALL\).*packlist//mg;
    $inherited =~ s|\$\(\S+\)/auto/\$\(\S+\)||mg;
    $inherited =~ s|\$\(INST_ARCHLIB\)\s+\$\(INSTALLSITEARCH\)\s+||m;
    $inherited;
    return q(install:
	@echo "'make install' is not implemented yet."
);
}

sub MY::dist_core {
    return q(
dist:
	@echo "'make dist' is not implemented yet."
release:
	@echo "'make release' is not implemented yet."

);
}

sub MY::top_targets {
    package MY; # so that "SUPER" works right
    my $inherited = shift->SUPER::top_targets(@_);
    $inherited =~ s/(?=^\ball\b\s*\:\:)(.*?)$/$1 \$\(TL_SITE_CF\) \$\(TL_GLOBAL_CF\)/m;
    $inherited;
}

sub MY::postamble {
    q|
TL_SITE_CF=$(INST_LIB)/tlily.site
TL_GLOBAL_CF=$(INST_LIB)/tlily.global

$(TL_SITE_CF):
	-rm -f $(TL_SITE_CF)
	@echo '# Site configuration file for TigerLily.' > $(TL_SITE_CF)
	@echo '# Please edit this, NOT the global configuration file.' >> $(TL_SITE_CF)

$(TL_GLOBAL_CF):
	-rm -f $(TL_GLOBAL_CF)
	cp tlily.global $(TL_GLOBAL_CF)

|;
}

sub MY::libscan {
    my($self, $path) = @_;
    return '' if $path =~ m:\bCVS/:;
    $path;
}
