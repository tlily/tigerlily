# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/autologin.pl,v 1.6 1999/04/09 23:43:13 neild Exp $

#
# Handle autologins.
#

use strict;

# List of places to look for an autologin file.
my @files = ("$ENV{HOME}/.lily/tlily/autologin",
	     "$ENV{HOME}/.lily/lclient/autologin");
unshift @files, $config{'autologin_file'} if ($config{'autologin_file'});

init() unless $config{noauto};

shelp_r("autologin", "Module for automating the login process.");
help_r("autologin", 
"Reads files containing lines of the format: <green>alias host port login passwd</green> in order to automate your login process to the specified server.  Unlike lclient, all fields must be present or the line will be ignored. (FIXME!)
Config options for autologin:
    \$autologin_file = 'filename';
        Prepends [filename] to the list of filenames containing autologin information.
");

sub init {
    my $file;
    foreach $file (@files) {
	open(FD, $file) or next;
	while (<FD>) {
	    next if (/^\s*(\#.*)?$/);
	    my ($alias, $host, $port, $user, $pass) = split;
	    next unless defined($pass);

	    if ($alias eq $config{'server'}) {
		$config{'server'} = $host;
		$config{'port'}   = $port;
	    }

	    if (($host eq $config{'server'}) && ($port eq $config{'port'})) {
		event_r(type => 'prompt',
			order => 'before',
			call => sub {
			    my($event, $handler) = @_;
			    return 0 unless ($event->{text} =~ /^login:/);
			    my $ui = ui_name();
			    $ui->print("(using autologin information)\n");
			    my $server = server_name();
			    $server->sendln("${user} ${pass}");
			    return 1;
			});
		
		last;
	    }
	}
	close(FD);
	
	last;
    }
}
