# -*- Perl -*-
# $Id$

#
# Handle autologins.
#

use strict;

=head1 NAME

autologin.pl - Automated login

=head1 DESCRIPTION

Allows you to record a username and password that will be used by tlily to
automatically log in when connecting to the specified server.  See
"%help autologin" for more information.

=cut

# List of places to look for an autologin file.
my @files = ("$ENV{HOME}/.lily/tlily/autologin",
	     "$ENV{HOME}/.lily/lclient/autologin");
unshift @files, $config{'autologin_file'} if ($config{'autologin_file'});

shelp_r('autologin_file' => "Prepended to list of files to check for autologin information.", "variables");

shelp_r('autologin', "Module for automating the login process.", "concepts");
help_r('autologin', 
"Reads files containing lines of the format:
    alias host port login passwd
in order to automate your login process to the specified server.  Unlike lclient, all fields must be present or the line will be ignored. (FIXME!)
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
