use strict;


sub paste_mode {
    my($ui, $command, $key) = @_;
    return 1 if ($ui->{_paste_nl_flag} && ($key eq "nl" || $key eq " "));
    if ($key eq "nl") {
	$ui->{_paste_nl_flag} = 1;
	$ui->command("insert-self", " ");
	return 1;
    }
    $ui->{_paste_nl_flag} = 0;
    return;
}

sub toggle_paste_mode {
    my($ui, $command) = @_;
    $ui->{_paste_nl_flag} = 0;
    if ($ui->intercept_u("paste-mode")) {
	$ui->prompt("");
    }
    elsif ($ui->intercept_r("paste-mode")) {
	$ui->prompt("Paste:");
    }
}


sub load {
    TLily::UI::command_r("paste-mode"        => \&paste_mode);
    TLily::UI::command_r("toggle-paste-mode" => \&toggle_paste_mode);
    TLily::UI::bind("M-p" => "toggle-paste-mode");
}
