#!/usr/bin/perl
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/Attic/Build.PL,v 1.4 1999/03/04 00:45:24 albert Exp $

use Config;
use Carp;
use Cwd;
use FileHandle;
use DirHandle;
use File::Copy;
use File::Path;
use Getopt::Std;
use TLily::Version;

use subs qw(&install);

# You no longer have to edit the paths here to configure tigerlily.
# This build script will ask you where you want to put tigerlily
# and make a build.cache file to save your preferences.

# Find perl
$PERL = $Config{'startperl'} ? $Config{'startperl'}     : 
        $Config{'perlpath'}  ? "#!".$Config{'perlpath'} :
                               "#/usr/bin/perl";

$perl_exec = $Config{'perl'};
# On broken systems like RPI's, locate perl in the user's path
if(length $PERL > 32) {
    my $P;
    foreach $P (split(/:/,$ENV{PATH})) {
	$PERL = "$P/$perl_exec";
	last if -x $PERL;
    }
    $PERL = '#!'.$PERL;
}

# If the place is still broken, try the swiss army perl starter
# FIXME: Insert chainsaw here

getopts("ndhficp:");
if($opt_h) {
    &Usage;
}
if($opt_n) {
    $nonono = 1;
}
if($opt_d) {
    $debug = 1;
}
if($opt_f) {
    $yesdamnit = 1;
}
if($opt_i) {
    $ignore = 1;
}
if($opt_c) {
    $current = 1;
    $ignore = 1;
}
if($opt_p) {
    $prefix = $opt_p;
}
$target=shift;

print "-n: $nonono\n" if $debug;
print "-d: $debug\n" if $debug;
print "-f: $yesdamnit\n" if $debug;
print "-i: $ignore\n" if $debug;
print "-c: $current\n" if $debug;
print "target: $target\n" if $debug;
print "ARGV: @ARGV\n" if $debug;
exit if $debug;

$VERSION = $TLily::Version::TL_VERSION;
$CVSTAG = &ver2tag($VERSION);
$STATE = 'release';
$cachefile = "build.cache";
$moddir="TLily";
$extdir="extensions";
$modext='\.pm';
$extext='\.pl';
@modsubdirs = qw(UI);
@modfiles = &get_files($moddir, $modext);
@extfiles = &get_files($extdir, $extext);

my $dir;
foreach $dir (@modsubdirs) {
    push @modfiles, map {$_ = "$dir/$_"} get_files("$moddir/$dir", $modext)
}

print join("\n", @modfiles), "\n" if $debug;
print join("\n", @extfiles), "\n" if $debug;

if(!$target || $target eq 'tlily' || $target eq 'tigerlily') {
    &make_tlily;
    if(!$DIRS_ARE_LOCAL && !$nonono) {
	print "To install Tigerlily, do a 'perl Build.PL install'.\n";
    }
}
elsif($target eq 'uninstall' || $target eq 'uninst') {
    if(! -e "build.cache") {
	print "You have not configured tigerlily yet.  If you wish to\n",
              "uninstall, please configure tigerlily first.\n";
	exit(1);
    }
    if($ignore) {
	print "Cannot ignore build cache when uninstalling.\n";
	$ignore=0;
    }
    print "Reading cache file $cachefile.\n";
    do "$cachefile";
    if($DIRS_ARE_LOCAL) {
	print "\nWARNING: Your installation directories are set for local development\nof tigerlily.\n";
	if(!$yesdamnit) {
	    $inp = &ask("Do you really want to uninstall tigerlily?", "no");
	    if($inp =~ /(n|no)/i) {
		print "OK, bailing out of uninstall.\n";
		exit(1);
	    }
	    else {
		print "I hope you know what you're doing..\n";
	    }
	}
	else {
	    print "I hope you know what you're doing..\n";
	}
    }

    if($nonono) {
	print "Would have removed $BINDIR/tlily.\n";
	print "Would have attempted to remove $BINDIR.\n";
	print "Would have recursively removed $LIBDIR.\n";
	print "Would NOT have removed $ETCDIR/tlily.site.\n";
	print "Would NOT have removed $ETCDIR.\n";
    } else {
	my($rc,$err);
	print "Uninstalling Tigerlily:\n";
	print "unlink $BINDIR/tlily\n";
	$rc = unlink "$BINDIR/tlily";
	if(!$rc) { print "Warning: file $BINDIR/tlily not removed.  Remove it\n\tmanually if desired.\n"; $err=1; }
	$rc = rmdir $BINDIR;
	if(!$rc) { print "Warning: directory $BINDIR not removed.  Remove it\n\tmanually if desired.\n"; $err=1; }
	rmtree "$LIBDIR", 1, 0;
	print "Information: Site configuration file $ETCDIR/tlily.site\n\tnot removed.\n";
	print "Information: Site configuration file directory $ETCDIR\n\tnot removed.\n";
    }
}
elsif($target eq 'install') {
    &make_tlily;
	
    if($DIRS_ARE_LOCAL) {
	print "\nYour installation directories are set for local development of tigerlily.\n";
	my($inp) = &ask("Do you want to enter new install paths?", "y");
	if($inp =~ /(y|yes)/i) {
	    $ignore = 1;
	    &make_tlily;
	}
	else {
	    if(!$yesdamnit) {
		$inp = &ask("Do you really want to install tigerlily?", "n");
		if($inp =~ /(n|no)/i) {
		    print "OK, bailing out of install.  Use the -i option to this script to ignore the\n";
		    print "build.cache.\n";
		    exit(1);
		}
		else {
		    print "I hope you know what you're doing..\n";
		}
	    }
	    else {
		print "I hope you know what you're doing..\n";
	    }
	}
    }
    print "Installing tlily script...\n";
    &install('DIR' => $BINDIR, 'MODE' => 0755);
    &install('FILE' => 'tlily',
	     'DEST' => "$BINDIR/tlily",
	     'MODE' => 0555);

    print "Installing global configuration file...\n";
    &install('DIR' => $LIBDIR, 'MODE' => 0755);
    &install('FILE' => 'tlily.global',
	     'DEST' => "$LIBDIR/tlily.global",
	     'MODE' => 0444);

    if(! -f "$ETCDIR/tlily.site") {
	print "Installing an initial site configuration file...\n";
    	&install('DIR' => $ETCDIR, 'MODE' => 0755);
	&install_site_cf;
    }

    print "Installing tlily internal modules...\n";
    &install('DIR' => "$LIBDIR/$moddir", 'MODE' => 0755);
	foreach(@modsubdirs) {
		install('DIR' => "$LIBDIR/$moddir/$_", 'MODE' => 0755);
	}

    my($file);
    foreach $file (@modfiles) {
	&install('FILE' => "$moddir/$file",
		 'DEST' => "$LIBDIR/$moddir/$file",
		 'MODE' => 0644);
    }

    print "Installing tlily global extensions...\n";
    &install('DIR' => "$LIBDIR/$extdir", 'MODE' => 0755);

    foreach $file (@extfiles) {
	&install('FILE' => "$extdir/$file",
		 'DEST' => "$LIBDIR/$extdir/$file",
		 'MODE' => 0644);
    }
}
elsif($target eq 'release') {
    if(! -d "CVS") {
	print "You do not appear to be a developer.  You cannot\n",
	    "use this function.\n";
	exit(1);
    }
    my($cmd);

    $VERSION = &next_version($VERSION);
    &ask_version;

    &make_version_file($VERSION);
    $cmd = "cvs commit -m 'Automatic precommit of version file' TLily/Version.pm";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	print "Committing TLily/Version.pm with:\n$cmd\n";
	$rc = system($cmd);
	if($rc) { die "Command returned error!\n"; }
    }

    &make_changelog($VERSION);
    $cmd = "cvs commit -m 'Automatic commit of ChangeLog file' ChangeLog";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	print "Committing ChangeLog with:\n$cmd\n";
	$rc = system($cmd);
	if($rc) { die "Command returned error!\n"; }
    }

    $cmd = "cvs tag -F $CVSTAG";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	print "Tagging release $VERSION with:\n$cmd\n";
	$rc = system("$cmd");
	if($rc) { die "Command returned error!\n"; }
    }

    if($nonono) {
	print "Would have created directory 'buildtmp'\n";
	print "Would have changed directory to 'buildtmp'\n";
    }
    else {
	print "Making temporary release directory..\n";
	mkdir("buildtmp", 0755);
	chdir("buildtmp");
    }

    $cmd = "cvs export -r $CVSTAG -d tlily-$VERSION tlily";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	print "Exporting tlily $VERSION with:\n$cmd\n";
	$rc = system("$cmd");
	if($rc) { die "Command returned error!\n"; }
    }

    $cmd = $Config{'tar'} || "tar";
    $cmd .= " cf ../tlily-$VERSION.tar tlily-$VERSION";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	if(-f "../tlily-$VERSION.tar") { unlink("../tlily-$VERSION.tar"); }
	print "Packaging tlily $VERSION with:\n$cmd\n";
	$rc = system("$cmd");
	if($rc) { die "Command returned error!\n"; }
    }

    if($nonono) {
	print "Would have changed directory to ..\n";
	print "Would have removed directory 'buildtmp'\n";
    }
    else {
	chdir("..");
	print "Removing temporary release directory..\n";
	rmtree("buildtmp", 0, 0);
    }

    $cmd = $Config{'gzip'} || "gzip";
    $cmd .= " -9 tlily-$VERSION.tar";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	if(-f "tlily-$VERSION.tar.gz") { unlink("tlily-$VERSION.tar.gz"); }
	print "Compressing the release archive with:\n$cmd\n";
	$rc = system("$cmd");
	if($rc) { die "Command returned error!\n"; }
    }

    &make_version_file($VERSION."-post");
    $cmd = "cvs commit -m 'Automatic postcommit of version file' TLily/Version.pm";
    if($nonono) {
	print "Would have executed: $cmd\n";
    }
    else {
	print "Committing TLily/Version.pm with:\n$cmd\n";
	$rc = system($cmd);
	if($rc) { die "Command returned error!\n"; }
    }

    &do_announcement($VERSION);
}
elsif($target eq 'announce') {
    if(! -d "CVS") {
	print "You do not appear to be a developer.  You cannot\n",
	    "use this function.\n";
	exit(1);
    }
    $VERSION =~ s/-post$//;
    &do_announcement($VERSION);
}
elsif($target eq 'clean') {
    rmtree('buildtmp', 0, 0);
    unlink("tlily");
#    unlink("lilybot");
    unlink("tlily-$VERSION.tar");
    unlink("tlily-$VERSION.tar.gz");
    unlink("build.cache");
}
else {
    print STDERR "Unknown target $target\n";
    &Usage;
}

exit(0);

sub get_files {
    my($dir,$ext) = @_;
    my($dh) = new DirHandle($dir);
    die $! if not $dh;

    grep { /${ext}$/ && -f "${dir}/$_" } readdir($dh);
}

sub install {
    my(%p) = @_;
    my($file, $dest, $dir, $mode, $rc);

    $file ||= $p{'FILE'};
    $dest ||= $p{'DEST'};
    $dir ||= $p{'DIR'};
    $mode ||= $p{'MODE'};

    if(defined($dir)) {
	$mode ||= 0755;
	if($nonono) {
	    print "Would have made directory ", $dir, ", mode ";
	    printf("%o\n", $mode);
	}
	else {
	    if(! -e $dir) {
		$rc = mkpath($dir, 0, $mode); 
		if(!$rc) { croak $dir,": ",$!; }
	    }
	    chmod($mode,$dir);
	}
	return 1;
    }
    elsif(defined($file) && defined($dest)) {
	$mode ||= 0644;
	if($nonono) {
	    print "Would have copied $file to ", $dest, ", mode ";
	    printf("%o\n", $mode);
	}
	else {
	    if($yesdamnit && -e $dest) {
		unlink($dest);
	    }
	    elsif(!$yesdamnit && -e $dest) {
		my $inp = &ask("\n$dest exists.  Overwrite? (Yes/No/All/Quit)",'y');
		if($inp =~ /(y|yes)/i) {
		    unlink($dest);
		}
		elsif($inp =~ /(n|no)/i) {
		    print "Not overwriting $dest.\n";
		    return 1;
		}
		elsif($inp =~ /(a|all)/i) {
		    $yesdamnit = 1;
		    unlink($dest);
		}
		elsif($inp =~ /(q|quit)/i) {
		    print "Ok, Bailing out of install.\n";
		    exit(0);
		}
	    }
	    $rc = copy($file, $dest);
	    if(!$rc) { croak $file,": ",$!; }

	    $rc = chmod($mode, $dest);
	    if(!$rc) { croak $dest,": ",$!; }
	}
    }
    else {
	croak "Bad args to install()";
    }
}

sub make_tlily {
    if($nonono) {
	print "Would have checked for the Curses module.\n";
	print "Would have checked for the Term::Size module.\n";
    } else {
	$| = 1;
	print "Checking for the Curses module...";
	if(has_module("Curses")) {
	    print "Yes.\n";
	}
	else {
	    print qq(No.
Info:  You will not be able to use the TLily::CTerminal terminal.  Remember
Info:  to set \$terminal to another terminal module (such as TLily::TTerminal)
Info:  in your site and/or user configuration files.
Info:  You can get this module from your nearest CPAN site or
  http://www.perl.com/CPAN-local/modules/by-module/Curses/Curses-1.01.tar.gz
);
	}
	print "Checking for the Term:Size module...";
	if(has_module("Term::Size")) {
	    print "Yes.\n"
	}
	else {
	    print qq(No.
Info:  Resizing your terminal may not work correctly without this module.
Info:  You can get this module from your nearest CPAN site or
  http://www.perl.com/CPAN-local/modules/by-module/Term/Term-Size-0.2.tar.gz
);
	}
    }

    &ask_dirs;
    if($nonono) {
	print "Would have created tlily from tlily.PL with the following\n";
	print "parameters:";
	print qq(
    To start Perl:  $PERL
TigerLily version:  $VERSION
Library directory:  $LIBDIR
);
	return;
    }
    
#    foreach $f (qw(tlily lilybot)) {
    foreach $f (qw(tlily)) {
	print "Writing $f\n";
	if(-f $f) { unlink $f; }
	
	my($ifh) = new FileHandle("$f.PL", "r");
	die $! if not $ifh;
	
	my($ofh) = new FileHandle($f, "w");
	if(!$ofh) {
	    my($msg) = $!; close($ifh); die $msg;
	}
	
	while(<$ifh>) {
	    s|\@\@PERL\@\@|$PERL|;
	    s|\@\@LIBMODDIR\@\@|$LIBDIR|;
	    s|\@\@LIBEXTDIR\@\@|$LIBDIR/$extdir|;
	    s|\@\@LIBDIR\@\@|$LIBDIR|;
	    s|\@\@ETCDIR\@\@|$ETCDIR|;
	    print $ofh $_;
	}
	close($ifh);
	close($ofh);
	chmod(0555, $f); # To discourage editing
    }
}

sub Usage {
    print qq(
Usage: perl Build.PL [-n][-h][-i][tigerlily|install|uninstall|clean|
                     release|announce]
	-n: Show what would have been done without actually doing it.
	-i: Ignore build.cache file.
	-c: Use current directories.
	-f: Force overwrite of previous install.
	-p <dir>: use build prefix <dir> and derive all other paths
	-h: Show this help
	Targets:
	tigerlily: Ask for paths and do path substitutions, generating tlily
	install:   Generate tlily like above and install it in 1 step
	uninstall: Uninstall tlily using the paths found in build.cache
	clean:     Remove the generated tlily and any left-over files and
	           directories possibly left behind by this script.
	release:   Tag the release via CVS and make a .tar.gz for release
	           (Developers only!)
	announce:  Generate an annoucement mail and send it to
	           tigerlily-announce\@einstein.org.  (Developers only!)

	With no targets, will execute tigerlily target.
);
    exit(1);
}

sub ask_dirs {
    my($inp);

    if($ignore) {
	print "Ignoring cache file $cachefile.\n";
    }
    if(-f $cachefile && !$ignore) {
	print "Reading cache file $cachefile.\n";
	do "$cachefile";
	if($DIRS_ARE_LOCAL) {
	    print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";
	}
	return;
    } elsif($current == 1) {
	&use_current_dir; return;
    } elsif($opt_p) {
	&use_prefix($opt_p); return;
    } else {
	$PREFIX='/usr/local';
	print qq(By default, tlily will be installed in $PREFIX/bin, global extensions
under $PREFIX/lib/tlily/extensions, etc..., i.e. with
$PREFIX as prefix for all installation directories.  It is typically
set to /usr/local, but you may choose /usr if you wish to install
tlily among your system binaries.  If you wish to have binaries under
/bin but support files under /usr/local/lib, that's ok: you will be
prompted separately for each of the installation directories, the
prefix only used to set the defaults.

Use an installation prefix of 'Current' or the -c command line option
to configure tlily for use in the current directory only.

);

	$inp = &ask("Installation prefix to use?", $PREFIX);
	if($inp) {
	    if($inp eq 'Current') {
		&use_current_dir; return;
	    }
	    $PREFIX=&tilde_expand($inp);
	}
	
	$BINDIR=$PREFIX."/bin";
	$inp = &ask("\nInstallation directory for the tlily script?", $BINDIR);
	if($inp) { $BINDIR=&tilde_expand($inp); }
		
	$LIBDIR=$PREFIX."/lib/tlily";
	print "\nInstallation directory for the tlily support files?  (This is where the\ninternal TLily library, the global extensions, and the global configuration\n";
	$inp = &ask("file will be installed.)", $LIBDIR);
	if($inp) { $LIBDIR=&tilde_expand($inp); }

	$ETCDIR=$PREFIX."/etc";
	$inp = &ask("\nInstallation directory for the site-specific configuration file 'tlily.site'?", $ETCDIR);
	if($inp) { $ETCDIR=&tilde_expand($inp); }

	$DIRS_ARE_LOCAL = '0';

	&write_buildcache;
    }
}

sub use_current_dir {
    print "\nUsing current directory.\n";
    $PREFIX = ".";
    print "Installation prefix is $PREFIX\n";
    $BINDIR = $PREFIX;
    print "Script location is $BINDIR\n";
    $LIBDIR = $PREFIX;
    print "Support files location is $LIBDIR\n";
    $ETCDIR = $PREFIX;
    print "Site config file location is $ETCDIR\n";
    $DIRS_ARE_LOCAL = 1;

    print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";

    &write_buildcache;
}

sub use_prefix {
    my($p) = @_;
    $PREFIX = $p;
    print "Installation prefix is $PREFIX\n";
    $BINDIR = "$PREFIX/bin";
    print "Script location is $BINDIR\n";
    $LIBDIR = "$PREFIX/lib/tlily";
    print "Support files location is $LIBDIR\n";
    $ETCDIR = "$PREFIX/etc";
    print "Site config file location is $ETCDIR\n";
    $DIRS_ARE_LOCAL = 0;

    &write_buildcache;
}

sub write_buildcache {
    if($nonono) {
	print "Would have written $cachefile with the following\n";
	print "settings:\n";
	print "\$PREFIX = '$PREFIX'\n";
	print "\$BINDIR = '$BINDIR'\n";
	print "\$LIBDIR = '$LIBDIR'\n";
	print "\$ETCDIR = '$ETCDIR'\n";
	print "\$DIRS_ARE_LOCAL = '$DIRS_ARE_LOCAL'\n";
	return;
    }
    print "Writing $cachefile\n";
    if(-f $cachefile) { unlink $cachefile; }
    my($fh) = new FileHandle($cachefile, "w");
    if(!$fh) { die $!; }

    print $fh qq(# build.cache
# Automatically generated by Build.PL.
\$PREFIX = '$PREFIX';
\$BINDIR = '$BINDIR';
\$LIBDIR = '$LIBDIR';
\$ETCDIR = '$ETCDIR';
\$DIRS_ARE_LOCAL = '$DIRS_ARE_LOCAL';
);
    close $fh;
    chmod(0444, $cachefile);
}

sub ask {
    $|=1;
    my($q,$d) = @_;
    my($sin) = new_from_fd FileHandle(STDIN, "r");
    if(length($q." [".$d."]: ") > 80) {
	print $q, "\n[", $d, "]: ";
    }
    else {
	print $q, " [", $d, "]: ";
    }
    chomp(my($l) = $sin->getline);
    $l eq '' ? $d : $l;
}

sub ask_version {
    my($ver) = $VERSION;
    my($inp) = &ask("Release Version?", $ver);

    $inp = version_part($inp);
    if(!$inp) { die "bad version string"; }
    $VERSION = $inp;
    $CVSTAG = &ver2tag($VERSION);
    print "VERSION=$VERSION\nCVSTAG=$CVSTAG\n" if $debug;
}


sub ver2tag {
    my($ver) = @_;
    my($maj,$min,$sub) = split_version($ver);
    "$STATE-$maj-$min".($sub?"-$sub":'');
}

sub split_version {
    my($ver) = @_;
    my($maj,$min,$sub);
    $ver =~ m/(\d+)\.(\d+?)\.?(\d+)?/o;
    ($maj,$min,$sub) = ($1, $2, $3);
    ($maj,$min,$sub);
}

sub next_version {
    my($ver)=@_;
    $ver =~ s/-post$//;
    my($maj,$min,$sub) = split_version($ver);
    if($sub) { $sub++; }
    else { $sub = 1; }
    "$maj.$min".($sub?".$sub":'');
}

sub version_part {
    my($maj,$min,$sub) = split_version($_[0]);
    "$maj.$min".($sub?".$sub":'');
}

sub make_version_file {
    my($ver) = @_;
    if($nonono) {
	print "Would have made TLily/Version.pm with the version number $ver.\n";
	return;
    }
    print "Writing TLily/Version.pm, version $ver\n";
    if(-f "TLily/Version.pm") { unlink "TLily/Version.pm"; }
    my($fh) = new FileHandle("TLily/Version.pm", "w");
    if(!$fh) { die $!; }

    print $fh qq(# Version.pm
# Automatically generated by Build.PL.
package TLily::Version;
\$TL_VERSION = '$ver';
1;
);
    close $fh;
    chmod(0444, "TLily/Version.pm");
}

sub tilde_expand {
    my($inp) = @_;
    my(@inp) = split('/', $inp);

    my($pe);
    foreach $pe (@inp) {
	if($pe eq '~') {
	    my($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell) =
	    getpwuid($>);
	    if(!$dir) {
		print "No home directory for uid ", $>, ", ignoring ~.\n";
		next;
	    }
	    $pe = $dir;
	}
	elsif($pe =~ /~(\w+)/o) {
	    my($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell) =
	    getpwnam($1);
	    if(!$dir) {
		print "No home directory for user ", $1, ", ignoring ~", $1,
		    ".\n";
		next;
	    }
	    $pe =~ s/~(\w+)/$dir/;
	}
    }
    join("/", @inp);
}

sub install_site_cf {
    if($nonono) {
	print "Would have made an initial $ETCDIR/tlily.site.\n";
	return;
    }
    my($fh) = new FileHandle("$ETCDIR/tlily.site", "w");
    if(!$fh) { die $!; }

    print $fh qq(# tlily.site
# Site configuration file for TigerLily.
# Please edit this, NOT the global configuration file.
);
    close $fh;
    chmod(0644, "$ETCDIR/tlily.site");
}

sub make_changelog {
    my($ver,$flag) = @_;
    if($nonono) {
	print "Would have made ChangeLog with the version number $ver.\n";
	return;
    }
    print "Writing ChangeLog, version $ver\n";

    my($fh) = new FileHandle("ChangeLog", "r");
    if(!$fh) { die $!; }
    my @lines = $fh->getlines();
    undef $fh;

    my $rc = unlink('ChangeLog');
    if(!$rc) { die $!; }

    $fh = new FileHandle("ChangeLog", "w");
    if(!$fh) { die $!; }

    $lines[0] = "Version $ver\n";

    print $fh @lines;
    undef $fh;
    chmod(0644, "ChangeLog");
}

sub do_announcement {
    my($version) = @_;
    my $inp = &ask("Do you want to send out an announcement?", 'yes');
    if($inp =~ /(y|yes)/i) {
	my $ChangeLog;
	my $cl = new FileHandle("ChangeLog", "r");
	my $f;
	while(<$cl>) {
	    if($f && ! /^Version/) { $ChangeLog .= $_; next; }
	    elsif($f && /^Version/) { last; }
	    elsif(/^Version\s+$VERSION/) { $f = 1; $ChangeLog = $_; }
	}
	undef $f;
	undef $cl;

	my $msg = qq(From: "Tigerlily Developers" <tigerlily\@hitchhiker.org>
To: "Tigerlily Announcement List" <tigerlily-announce\@einstein.org>
Subject: Tigerlily $version is now available

Hi All -

Tigerlily version $version is now available.

Changes in this release, from the ChangeLog:
$ChangeLog
Once Josh moves it into place, it will be available from:
http://www.hitchhiker.org/tigerlily/

Until then, you can get it from:
http://www.acm.rpi.edu/~neild/
-- 
Share and Enjoy.

The Tigerlily Developers
Damien, Albert, Josh, Jon, Steve & Matt.
----------------------------------------------------------------------------
To unsubscribe from this list, send email to <majordomo\@einstein.org> with
the words "unsubscribe tigerlily-announce" in the body.
);
	my $abort_flag;
	my $editor = $ENV{EDITOR} || $ENV{VISUAL} || "vi";
	while(1) {
	    print $msg;
	    my $ans = &ask("(s)end, (e)dit, or (a)bort:", "s");
	    last if $ans eq 's';
	    if($ans eq 'a') { $abort_flag = 1; last; }
	    if($ans eq 'e') {
		FileHandle->new("msgtmp.$$", 'w')->print($msg);
		system($editor, "msgtmp.$$");
	    }
	    $msg = join("", FileHandle->new("msgtmp.$$", 'r')->getlines());
	    unlink("msgtmp.$$");
	}
	if(!$abort_flag) {
	    my $mail = new FileHandle("|/usr/sbin/sendmail -t");
	    die "Couldn't send mail: $!" if !$mail;
#	    my $mail = STDOUT;
	    print $mail $msg;
	}
    }
    else {
	print "Don't forget to send an announcement of the new release\n",
	    "to tigerlily-announce\@einstein.org.\n";
    }
}

sub has_module {
    my($mod) = @_;
    eval "use $mod;";
    if($@) { return 0; } else { return 1; }
}
