# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/xmms.pl,v 1.1 2000/09/08 02:49:31 coke Exp $

use strict;

# Author:   Will "Coke" Coleda
# Created:  August, 2000
# Purpose:  Control xmms from tigerlily.
# Danger:   Hackery abounds. I cannot even begin to describe how
#           bletcherous this extension is.
# Requires: that you have the Xmms modules installed, and that perl be
#           in your path.
# BUGS:     figure out how to call Xmms IN THIS INSTANCE OF PERL. ugh.

command_r('xmms', \&xmms_cmd);
shelp_r('xmms', "Control xmms from lily");
help_r( 'xmms',"%xmms <subcommand>

<subcommand> of pause, play, stop, next, prev do what you'd expect.

vol <num> sets the volume (0-98)
vol with no arg returns the current (approximate) volume.
vol [+-]<num> modifies the volume by that amount, if possible.

song returns the title of the currently playing song.
playlist returns the entire playlist. be careful.
");

my $command = '`perl -MXmms::Remote -e \'\$r=Xmms::Remote->new; \$t = \$r->%s; if (ref \$t eq "ARRAY") {\$t = join("\n", @\$t)} print \$t;\'`';


my %simple = (
	stop => "stop",
	pause => "pause",
	next => "playlist_next",
	prev => "playlist_prev",
	play => "play",
);
 
sub xmms_cmd {
    my ($ui,$cmd) = @_;

    if (exists $simple{$cmd}) {
      eval sprintf $command, $simple{$cmd};
    } elsif ($cmd eq "vol") {
        my $vol = eval sprintf $command, "get_main_volume" ;
	$ui->print("(vol is approximately $vol)\n");
    } elsif ($cmd =~ /vol (\d+)/) {
	eval sprintf $command, "set_main_volume($1)";
    } elsif ($cmd =~ /vol ([+-])(\d+)/) {
        my $vol = eval sprintf $command, "get_main_volume" ;
 	if ($1 eq "+") {
		$vol += $2;
	} else {
		$vol -= $2;
	}
	eval sprintf $command, "set_main_volume($vol)";
	$ui->print("(vol is approximately $vol)\n");
    } elsif ($cmd eq "song") {
        my $pl = eval sprintf $command, "get_playlist_titles" ;
        my $pos = eval sprintf $command, "get_playlist_pos" ;
	$ui->print("(" . (split(/\n/,$pl))[$pos] . ")\n" );
    } elsif ($cmd eq "playlist") {
        my $pl = eval sprintf $command, "get_playlist_titles" ;
	foreach my $song (split(/\n/,$pl)) {
		$ui->print("(" . $song . ")\n" );
	}
    } else {
	$ui->print("(Invalid subcommand. see %help xmms)\n");
    }
}

1;
