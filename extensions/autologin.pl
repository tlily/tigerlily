# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/autologin.pl,v 1.8 1999/05/08 04:36:00 josh Exp $

#
# Handle autologins.
#

use strict;

# List of places to look for an autologin file.
my @files = ("$ENV{HOME}/.lily/tlily/autologin",
	     "$ENV{HOME}/.lily/lclient/autologin");
unshift @files, $config{'autologin_file'} if ($config{'autologin_file'});

shelp_r("autologin", "Module for automating the login process.", "concepts");
help_r("autologin", 
"Reads files containing lines of the format: <green>alias host port login passwd</green> in order to automate your login process to the specified server.  Unlike lclient, all fields must be present or the line will be ignored. (FIXME!)
Config options for autologin:
    \$autologin_file = 'filename';
        Prepends [filename] to the list of filenames containing autologin information.
");

sub load {
    $config{server_info} = [];

    local *FD;
    foreach my $file (@files) {
	open(FD, $file) or next;
	while (<FD>) {
	    next if (/^\s*(\#.*)?$/);
	    my ($alias, $host, $port, $user, $pass) = split;
	    next unless defined($port);

	    push @{$config{server_info}}, {
		alias => $alias,
		host  => $host,
		port  => $port,
		user  => $user,
		pass  => $pass
	    };
	}
	close(FD);
	
	last;
    }
}
