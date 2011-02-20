# -*- Perl -*-

use strict;

command_r('mirror' => \&mirror_cmd);
command_r('unmirror', \&unmirror_cmd);
shelp_r('mirror', "mirror a discussion into another");
shelp_r('unmirror', "undo a %mirror");
help_r('mirror',
       " usage: %mirror [fromdisc] [todisc]");

help_r('unmirror',
       " usage: %unmirror [disc]");

my(%mirrored);

sub mirror_cmd {
    my $ui = shift;
    my ($fromdisc,$todisc) = split /\s+/, "@_";
    $fromdisc = lc($fromdisc);
    $todisc = lc($todisc);

    if ("@_" =~ /^\S*$/) {
        my $f;
        foreach (sort keys %mirrored) {
            $f=1;
            $ui->print("($_ is mirrored to " . (split /,/,$mirrored{$_})[2] . ")\n");
        }
        if (! $f) {
            $ui->print("(no discussions are currently being mirrored)\n");
        }
        return 0;
    }

    if (! (($fromdisc =~ /\S/) && ($todisc =~ /\S/))) {
        $ui->print("usage: %mirror [fromdisc] [todisc]\n");
        return 0;
    }

    if ($mirrored{$fromdisc}) {
        $ui->print("(error: $fromdisc is already mirrored)\n");
        return 0;
    }

    my $e1 = event_r(type => 'public',
                     call => sub { send_handler($fromdisc,$todisc,@_); });

    my $e2 = event_r(type => 'emote',
                     call => sub { send_handler($fromdisc,$todisc,@_); });

    $mirrored{$fromdisc}="$e1,$e2,$todisc";

    $ui->print("(mirroring $fromdisc to $todisc)\n");
    0;
}

sub unmirror_cmd {
    my ($ui,$disc) = @_;

    if ($mirrored{$disc}) {
        my ($e1,$e2) = split ',',$mirrored{$disc};
        event_u($e1);
        event_u($e2);
        delete $mirrored{$disc};
        $ui->print("(\"$disc\" will no longer be mirrored.)\n");
    } else {
        $ui->print("(\"$disc\" is not being mirrored!)\n");
    }

}

sub send_handler {
    my ($from,$to,$e) = @_;

    my $match = 0;
    foreach (split ',',$e->{RECIPS}) {
        if (lc($_) eq $from) { $match=1; last; }
    }

    if ($match) {
        if ($e->{type} eq "emote") {
            $e->{server}->sendln("$to;mirrors: (to $e->{RECIPS}) $e->{SOURCE}$e->{VALUE}");
        } else {
            $e->{server}->sendln("$to;($e->{SOURCE} => $e->{RECIPS}) $e->{VALUE}");
        }
    }

    0;
}

sub unload {
    my $ui = ui_name();
    foreach (sort keys %mirrored) {
        unmirror_cmd($ui,$_);
    }
}

1;
