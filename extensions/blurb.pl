# -*- Perl -*-

use strict;
use warnings;


# Author: Will "Coke" Coleda (will@coleda.com)

#
# It's possible that multiple compressions will render readability undef.
# Ping me if you think this is happening.
#

shelp_r("server_all" => "(boolean) run %command on -all- cores?", "variables");
shelp_r("blurb_verbose" => "(boolean) show diag output for %blurb", "variables");
command_r('blurb', \&blurb_cmd);
command_r('here', \&here_cmd);
command_r('away', \&away_cmd);
shelp_r('blurb', "Format your blurb so it fits.");
shelp_r('here', "like /here, but also does %blurb, and respects multi-core");
shelp_r('away', "like /away, but also does %blurb, and respects multi-core");
help_r('here', "like /here, but also does %blurb, and respects multi-core");
help_r('away', "like /away, but also does %blurb, and respects multi-core");
help_r( 'blurb',"%blurb <blurb> will try to wedge your blurb into the available space
if it won't fit. There is, by default, a 35 character limit on the length
of your psuedo + the length of your blurb. (Toss in another 3 for the ' []',
and the total of 38 is what's allowed to satisfy those lame old telnet
clients.)

The extension will use a variety of techniques to try to cut your blurb
down to size, and failing those, will lop off the end of your blurb.

The multi-core version of %blurb calculates things based on your current
psuedo. This might cause problems if you use psuedos of various lengths on
different cores.
");

$config{"server_all"} = 0 if !exists($config{"server_all"});
# print out the tries as we go.
$config{"blurb_verbose"} = 0 if !exists($config{"blurb_verbose"});

#
# Abbrs: a hash of regexen and their abbreviations.
#

my %abbr = (
    'fou?r' => "4",
    'ate|eight' => "8",
    '\b(too?|two)' => "2",
    'and' => "&",
);

sub unload {
    ## Nothing to do here right now.
}

my $max = 35;
my $psuedo;

#
# Is this blurb ok?
#
sub check_blurb {
        if (length($psuedo) + length($_[0]) <=$max) {
        return 1;
    }
    return 0;
}


#
# Go here or away, respecting multicore
#
sub away_cmd {
    my ($ui, $blurb) = @_;
    state_cmd($ui,$blurb,"away");
    return;
}

sub here_cmd {
    my ($ui, $blurb) = @_;
    state_cmd($ui,$blurb,"here");
    return;
}

sub state_cmd {
     my ($ui, $blurb,$state) = @_;
     my @servers;
    if ($config{server_all}) {
        @servers = TLily::Server::find();
    } else {
        $servers[0] = TLily::Server->active();
    }

    foreach my $core (@servers) {
        next if !defined $core;
        $core->cmd_process("/$state", sub {
            # I don't see how to get the output of the cmd back...
        });
    };
    if ($blurb && $blurb ne "") {
        blurb_cmd($ui,$blurb);
    }
    return;
}

#
# Apply a set of rules to reduce your blurb into something that will
# fit into a smaller space. Apply this rules in order of readability.
#

sub blurb_cmd {
    my ($ui,$blurb) = @_;
    $psuedo = active_server()->user_name(); #psuedo can change..
    my $modified = 0;
    my @words;
    my $failed=1;

    if (lc($blurb) eq "off") {
        my @servers=();
        if ($config{server_all}) {
            @servers = TLily::Server::find();
        } else {
            $servers[0] = TLily::Server->active();
        }

        foreach my $core (@servers) {
            next if !defined $core;
            $core->cmd_process("/blurb off", sub {
                # I don't see how to get the output of the cmd back...
            });
        };
        return;
    }

    ## strip off exterior braces/quotes.

    if ($blurb =~ /^"(.*)"$/) {
        $blurb = $1;
    } elsif ($blurb =~ /^\[(.*)\]$/) {
        $blurb = $1;
    }

    $ui->print("BRACES/QUOTES:" .$blurb. "\n") if $config{blurb_verbose};
        goto DONE if (check_blurb($blurb));

    $modified = 1;

    #Trim any left/right spaces...

    $blurb =~ s/^(\s*)//;
    $blurb =~ s/(\s*)$//;

    $ui->print("LEADING/TRAILING SPACE:" .$blurb. "\n") if $config{blurb_verbose};
    goto DONE if (check_blurb($blurb));

    #Reduce any multiple spaces to singletons.

    $blurb =~ s/(\s+)/ /g;
    $ui->print("MULTIPLE SPACES:" .$blurb. "\n") if $config{blurb_verbose};

    goto DONE if (check_blurb($blurb));

    #Handle any abbreviations;

    foreach my $re (keys %abbr) {
        while ($blurb =~s /$re/$abbr{$re}/i) {
            $ui->print("ABBR ($re):" .$blurb. "\n") if $config{blurb_verbose};
                goto DONE if (check_blurb($blurb));
        }
    }

    #Remove all spaces.. convert to a list in the process,
        #since we need to keep track of words from this point out.

    @words = map {ucfirst $_} (split(' ',$blurb));
    $blurb = join('',@words);
    $ui->print("ALL SPACES:" .$blurb. "\n") if $config{blurb_verbose};
    goto DONE if (check_blurb($blurb));

    #Remove punctuation
        my $punc = "'\""; # don't remove &, as it could be there intentionally

    while (grep /$punc/, @words) { #if -any- puncutation
        foreach my $word (@words) { # remove from each word in turn.
            if ($word =~ s/$punc//) {
                $blurb=join('',@words);
                $ui->print("PUNCTUATION:" .$blurb. "\n") if $config{blurb_verbose};
                goto DONE if (check_blurb($blurb));
            }
        }
    }

    #Remove some vowels?

    my $vowelRE = '([^AEIOUaeiou])[aeiou]([^AEIOUaeiou])';

    while (grep /$vowelRE/, @words) { #if -any- cases,
        foreach my $word (reverse @words) { # remove from each word in turn.
            if ($word =~ s/$vowelRE/$1$2/) {
                $blurb=join('',@words);
                $ui->print("VOWELS:" .$blurb. "\n") if $config{blurb_verbose};
                goto DONE if (check_blurb($blurb));
            }
        }
    }

    FAIL:
    $ui->print("FAIL:\n") if $config{blurb_verbose};
    $failed=1;
    $blurb = substr(join('',@words),0,($max-length($psuedo)));
    $ui->print("(your compressed blurb is is " . abs($max - length($psuedo) - length($blurb)) . " chars too long)\n") if $config{blurb_verbose};

    DONE:
    my @servers=();
    if ($config{server_all}) {
        @servers = TLily::Server::find();
    } else {
        $servers[0] = TLily::Server->active();
    }

    foreach my $core (@servers) {
        next if !defined $core;
        $core->cmd_process("/blurb [" . $blurb . "]", sub {
            # I don't see how to get the output of the cmd back...
        });
    };
    $ui->print("BLURB: " . $blurb . "\n") if $config{blurb_verbose};
    return;
}

#TRUE! They return TRUE!
1;
