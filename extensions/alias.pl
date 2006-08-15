# -*- Perl -*-
# $Id$

use strict;
use warnings;

=head1 NAME

alias.pl - Command-line aliasing

=head1 DESCRIPTION

This extension adds the %alias command, which allows you to set up aliases
for commands, much like in many shells.

=head1 COMMANDS

=over 10

=cut

my %alias;

sub load {
    event_r(type  => "user_input",
            order => "before",
            call  => \&aliaser);
    command_r(alias => \&alias_cmd);

    shelp_r(alias => "Define client aliases");
    help_r(alias => qq{%alias <alias> <commands>
%alias clear <alias>
%alias list [<alias>]

<alias> must contain only A-Z, a-z, 0-9 and _.

You cannot alias "clear" or "list".

Supports the following special characters in <commands>:
\$1 .. \$9  arguments to command
\$*        all arguments to command
\\n        command separator

Examples:

%alias hi bob;hi there\\njim;I hate you!
%alias inbeener /who beener \$*
    });

    return;
}

=item %alias

Establishes an alias for a command line.  See "%help %alias" for details.

=cut

sub alias_cmd {
    my ($ui,$args) = @_;

    if ($args =~ m/^\s*$/ || $args =~ /^\s*list\s*$/) {
        if (scalar keys %alias) {
            $ui->print("The following aliases are defined:\n");
            foreach (sort keys %alias) {
            $ui->print("$_: $alias{$_}\n");
            }
        } else {
            $ui->print("(no aliases are currently defined)\n");
        }
        return;
    }

    my ($key,$val) = ($args =~ /^\s*(\w+)\s*(.*?)\s*$/);

    unless (length($key) > 0) {
        $ui->print("(First argument to %alias must be in set [A-Za-z0-9_])\n");
        return;
    }

    if ($key eq "clear") {
        if($val eq "") {
            $ui->print("(Usage: %alias clear <command>)\n");
            return;
        }
        delete $alias{$val};
        $ui->print("(\%$val is now unaliased.)\n");
        return;
    }

    if ($key eq "list" || ! $val) {
        $val = $key unless $val;
        for (split(/ /, $val)) {
            if (exists $alias{$_}) {
                $ui->print("$_: $alias{$_}\n");
            } else {
                $ui->print("($_ is not aliased)\n");
            }
        }
        return;
    }

    $alias{$key} = $val;
    $ui->print("(\%$key is now aliased to '$val')\n") if not $config{alias_quiet};

    return;
}

sub aliaser {
    my($e, $h) = @_;
    my $server = active_server();

    if ($e->{text} =~ /^%(\S+)\s*(.*)/) {
        my $newstr = $alias{$1};
        my $args = $2;
        my @args = ($1, (split /\s+/,$2));
        if ($newstr) {
            for (0..9) {
                $newstr =~ s/\$$_/$args[$_]/g;
            }
            $newstr =~ s/\$\*/$args/g;
            if ($newstr =~ /\\n/) {
                my @rest;
                ($newstr,@rest) = split /\\n/,$newstr;
                foreach (@rest) {
                    TLily::Event::send({type => 'user_input',
                                        ui   => $e->{ui},
                                        text => "$_\n"});
                }
            }
            $e->{text} = $newstr;
        }
    }

    return 0;
}

1;
