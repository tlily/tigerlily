# -*- Perl -*-

use strict;
eval 'use Xmms::Remote;';
if ($@) {
    die "xmms.pl requires Xmms::Remote to be installed.\n";
}

# Author:   Will "Coke" Coleda
# Created:  August, 2000
# Purpose:  Control xmms from tigerlily.

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

my $r;

my %simple = (
        stop => "stop",
        pause => "pause",
        next => "playlist_next",
        prev => "playlist_prev",
        play => "play",
);

sub xmms_cmd {
    my ($ui,$cmd) = @_;

    unless ($r->is_running()) {
        $ui->print("(Xmms is not running)\n");
        return;
    }

    if (exists $simple{$cmd}) {
        $cmd = $simple{$cmd};
        my $res = $r->$cmd();
        $ui->print("($res)\n") if $res;
    } elsif ($cmd =~ m{play ((?:http|file)://.+)}i) {
        my $res = $r->playlist_add_url($1);
        $ui->print("($res)\n") if $res;
        $r->set_playlist_pos($r->get_playlist_length());
        $r->play();
    } elsif ($cmd eq "vol") {
        my $vol = $r->get_main_volume();
        $ui->print("(vol is approximately $vol)\n");
    } elsif ($cmd =~ /vol (\d+)/) {
        $r->set_main_volume($1);
        $ui->print("(vol is approximately $1)\n");
    } elsif ($cmd =~ /vol ([+-])(\d+)/) {
        my $vol = $r->get_main_volume();
         if ($1 eq "+") {
                $vol += $2;
        } else {
                $vol -= $2;
        }
        $r->set_main_volume($vol);
        $ui->print("(vol is approximately $vol)\n");
    } elsif ($cmd eq "song") {
        my $title = $r->get_playlist_title();
        $ui->print("($title)\n");
    } elsif ($cmd eq "playlist") {
        my $pl = $r->get_playlist_titles();
        foreach my $song (@{$pl}) {
                $ui->print("(" . $song . ")\n" );
        }
    } else {
        $ui->print("(Invalid subcommand. see %help xmms)\n");
    }
}

sub load {
  $r = Xmms::Remote->new;
}

1;
