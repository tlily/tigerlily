#!/usr/bin/perl -w
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

use strict;
no strict qw(refs);
use Config;
use Carp;
use Cwd;
use FileHandle;
use DirHandle;
use File::Copy;
use File::Path;
use Getopt::Std;
use TLily::Version;

use subs qw(install make_tlily Usage ask_dirs use_current_dir
    use_prefix write_buildcache ask ask_version split_version
    next_version version_part make_version_file tilde_expand install_site_cf
    make_changelog do_announcement);

use vars qw($PERL $perl_exec $VERSION $cachefile
    $nonono $yesdamnit $LIBDIR $f $extdir $ETCDIR $ignore $DIRS_ARE_LOCAL
    $current $opt_p $PREFIX $BINDIR $debug);

# Find perl
$PERL = $Config{'startperl'} ? $Config{'startperl'}     : 
        $Config{'perlpath'}  ? "#!".$Config{'perlpath'} :
                               "#/usr/bin/perl";

$perl_exec = quotemeta($Config{'perl'});
# On broken systems like RPI's, locate perl in the user's path
if(length $PERL > 32) {
    my $P;
    foreach $P (split(/:/,$ENV{PATH})) {
	$PERL = "$P/$perl_exec";
	last if -x $PERL;
    }
    $PERL = '#!'.$PERL;
}

# If the length is still too long, complain
if(length $PERL > 32) {
    warn "WARNING: Path to perl interpreter is long; tlily may not work right.\n";
#    $PERL = qq(\#\!/bin/sh -- \# perl, to stop looping
#    eval 'exec $Config{perlpath} -S \$0 \${1+"\$@"}'
#    if 0;
#);
}

$VERSION = $TLily::Version::VERSION;
$cachefile = "build.cache";

&make_tlily;
	
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
#    &ask_dirs;
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

    my $PREFIX = '.';
    my $BINDIR = '.';
    my $LIBDIR = '.';
    my $ETCDIR = '.';
#    my $LIBMODDIR = './blib/lib';
#    my $LIBEXTDIR = './blib/lib/extensions';
    my $LIBMODDIR = '.';
    my $LIBEXTDIR = './extensions';
    $DIRS_ARE_LOCAL = '1';

    eval "mkpath('./blib/bin');";
    if($@) { die "Error: $@\n" }
    print "mkdir ./blib/bin\n";
    
    my $file = './blib/bin/tlily';
    print "Writing $file\n";
    if(-f $file) { unlink $file; }
	
    my($ifh) = 'DATA';
	
    my($ofh) = new FileHandle($file, "w");
    if(!$ofh) { my($msg) = $!; close($ifh); die $msg; }
	
    while(<$ifh>) {
	s|\@\@PERL\@\@|$PERL|;
	s|\@\@LIBMODDIR\@\@|$LIBMODDIR|;
	s|\@\@LIBEXTDIR\@\@|$LIBEXTDIR|;
	s|\@\@LIBDIR\@\@|$LIBDIR|;
	s|\@\@ETCDIR\@\@|$ETCDIR|;
	print $ofh $_;
    }
    close($ofh);
    chmod(0555, $file); # To discourage editing
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
#	    print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";
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

#    print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";

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
    my($sin) = new_from_fd FileHandle(*STDIN, "r");
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
    print "VERSION=$VERSION\n" if $debug;
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
\$VERSION = '$ver';
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
__END__
@@PERL@@
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

require 5.00307;

$TL_ETCDIR="@@ETCDIR@@";
$TL_LIBDIR="@@LIBDIR@@";
$TL_EXTDIR="@@LIBEXTDIR@@";

use strict;
use lib qw(@@LIBMODDIR@@);

use TLily::Event;
use TLily::Config;
use TLily::UI;
use TLily::Server;
use TLily::Server::SLCP;
use TLily::User;
use TLily::Extend;
use TLily::Version;
use TLily::Command;

if ( -f 'tlily.PL' ) {
    my @tstat = stat('tlily.PL');
    my @mstat = stat($0);
    if ($tstat[9] > $mstat[9]) {
	print "tlily.PL is newer than $0 -- rerun Build.PL.\n";
	exit;
    }
}

TLily::Config::init();
TLily::Event::init();
TLily::Command::init();
my $ui = load_ui();

show_banner();

TLily::User::init;
TLily::Extend::cmd_init;

$SIG{__WARN__} = \&sig_warn;
sub sig_warn {
    $SIG{__WARN__} = \&sig_warn;
    $ui->print("WARNING: ", $_[0]);
}

$SIG{PIPE} = \&sig_pipe;
sub sig_pipe {
    $SIG{PIPE} = \&sig_pipe;
    my ($package, $filename, $line, $subroutine,
	$hasargs, $wantarray, $evaltext, $is_require) = caller(1);
    
    $ui->print("WARNING: Caught SIGPIPE. (from $package::$subroutine)\n");
}

my $sigint = 0;
sub sigint {
    exit if ($sigint);
    $ui->print("(hit ctrl-c again within 5 seconds to exit)\n");
    $sigint = 1;
    TLily::Event::time_r(after => 5,
			 call  => sub {
			     $sigint = 0;
			     $ui->print("(you waited too long to hit ctrl-c; exit aborted)\n");
			 });
}
$ui->command_r("interrupt", \&sigint);
$ui->bind("C-c" => "interrupt");

sub output_handler {
    my($event, $handler) = @_;
    if ($event->{ui_name}) {
	my $ui = TLily::UI::name($event->{ui_name});
	
	if ($event->{BELL}) {
	    $ui->bell();
	}
	
	if ($event->{NOTIFY} && $event->{formatter}) {
	    $event->{formatter}->($ui, $event);
	} elsif ($event->{NOTIFY} && $event->{indent}) {
	    $ui->indent($event->{indent});
	    $ui->print($event->{text}, "\n");
	    $ui->indent();
	} elsif ($event->{NOTIFY} && $event->{slcp}) {
	    $ui->style("slcp");
	    $ui->print($event->{text}, "\n");
	    $ui->style("default");
	} elsif ($event->{NOTIFY}) {
	    $ui->print($event->{text}, "\n");
	}
	
    }
    
    return;
}
TLily::Event::event_r(type  => "all",
		      order => "after",
		      call  => \&output_handler);

sub prompt_handler {
    my($event, $handler) = @_;
    my $server = $event->{server};
    
    if (defined($event->{value})) {
	$server->sendln($event->{value});
	return;
    }
    
    if ($event->{ui_name}) {
	my $ui = TLily::UI::name($event->{ui_name});
	$ui->prompt_for(prompt   => $event->{text},
			password => $event->{password},
			call     => sub { 
			    TLily::Event::send(type => 'user_input',
					       ui   => $ui,
					       text => $_[1]);
			    # or, to bypass the normal handlers (and break
			    # %commands)
			    #$server->sendln($_[1]); 
			});
	return;
    }
    
    # This should never happen.
    warn "Unanswerable prompt: $event->{text}\n";
    return;
}
TLily::Event::event_r(type  => "prompt",
		      order => "after",
		      call  => \&prompt_handler);

TLily::Extend::load_extensions($ui);

$ui->print("\n");

TLily::Event::send(type => 'user_input',
		   ui   => $ui,
		   text => "%connect");

while (1) {
    eval { TLily::Event::loop; };
    
    # Normal exit.
    if ($@ eq '') {
	$ui->print("*** Exiting.");
	exit;
    }
    
    # Non-fatal errors.
    if ($@ =~ /^Undefined subroutine/) {
	$ui->print("ERROR: ", $@);
	next;
    }
    
    # Oh, well.  Guess we have a problem.
    die;
}



sub load_ui {
    my %available;

    $config{UI} ||= "Curses";

    opendir(D,"$::TL_LIBDIR/TLily/UI");
    map { s/.pm$//; $available{$_}++; } grep /\.pm$/, readdir(D);
    closedir D;

    # did they specify a substring or case-insensitive match of an available
    # UI?
    if (! $available{$config{UI}}) {
	foreach (keys %available) { 
	    if (/$config{UI}/i) { $config{UI} = $_; }
	}
    }

    # nope?  ok, fall back to Curses.
    if (! $available{$config{UI}}) {
	print "UI \"$config{UI}\" was not found.\n";
	print "Press ENTER to try the default UI, or Control-C to quit.\n";
	<STDIN>;
	$config{UI}="Curses";
    }

    # OK, load the UI..
    eval "use TLily::UI::$config{UI}; \$ui = TLily::UI::$config{UI}->new(name => 'main');";
    if ($@) {
	warn "ERROR: Unable to load UI \"$config{UI}\".\n$@\n";
	# sometimes they die() in the new(), leaving a half-allocated UI.
	TLily::UI::purge("main");
    }
    
    die "FATAL: Unable to load a UI module.  Exiting.\n" unless $ui;

    return $ui;
}


# This screws up cperl something terrible, so put it at the end where we
# don't care.
sub show_banner() {
    $ui->prints(yellow => qq[     ("`-/")_.-'"``-._ \n],
                yellow => qq[      . . `; -._    )-;-,_`)],
                                             green  => qq[          TigerLily $TLily::Version::VERSION\n],
                yellow => qq[     (v_,)'  _  )`-.\  ``-'],
                                            bwhite => qq[             "Feel Free"\n],
                yellow => qq[    _.- _..-_/ / ((.'\n],
                yellow => qq[  ((,.-'   ((,/ \n],
                bwhite => qq[------------------------------------------------------------------------------\n]);
    $ui->style("default");
}

=pod

=head1 NAME

tlily - TigerLily

=head1 SYNOPSIS

    tlily [-h <host>] [-p <port>] [-UI=<UI Name>]

=head1 DESCRIPTION

This is TigerLily.  Need we say more?  Yes.

=head1 SEE ALSO

F<http://www.hitchhiker.org/tigerlily/>

For hacking on tlily, you may want to see
L<TLily::UI>,
L<TLily::User>,
L<TLily::Event>,
L<TLily::Registrar>,
L<TLily::Daemon>,
L<TLily::Server>,
L<TLily::Daemon::HTTP>,
L<extensions::slcp_parse>,
and 
L<extensions::slcp_output>.

=head1 BUGS

Many.  We will eventually fix them and cause more.

=cut

1;
