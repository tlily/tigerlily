use strict;

=head1 NAME

fumble.pl - Prevent accidental sends when typing ' or "

=head1 DESCRIPTION

=head2 UI COMMANDS

=over 10

=item toggle-fumble-mode

Toggles fumble mode.

=item fumble-mode

Used internally to intercept each keystroke when fumble mode is enabled,
and perform the appropriate magic.

=cut

sub fumble_mode {
    my($ui, $command, $key) = @_;

    if ($key eq "'" || $key eq '"') {
        $ui->{_eat_nl_flag} = 1;
        return;
    } elsif ($key eq "nl" && $ui->{_eat_nl_flag}) {
        $ui->{_eat_nl_flag} = 0;
        return 1;
    } else {
        $ui->{_eat_nl_flag} = 0;
        return;
    }
}

sub toggle_fumble_mode {
    my($ui, $command) = @_;

    $ui->{_eat_nl_flag} = 0;

    if ($ui->intercept_u("fumble-mode")) {
    } elsif ($ui->intercept_r(name => "fumble-mode", order => 990)) {
    } else {
        $ui->style("input_error");
        $ui->print("(cannot start fumble mode)\n");
        $ui->style("normal");
    }
}

TLily::UI::command_r("fumble-mode"        => \&fumble_mode);
TLily::UI::command_r("toggle-fumble-mode" => \&toggle_fumble_mode);

sub load {
    my $ui = TLily::UI::name();

    $ui->intercept_r(name => "fumble-mode", order => 990);
}

=back

=cut
