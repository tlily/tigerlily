# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/info.pl,v 1.15 1999/12/13 08:32:07 mjr Exp $

use strict;

sub export_handler {
    my($event, $handler) = @_;

    my $ex = shift @{$event->{server}->{_export_queue}};
    return unless $ex;

    my $ui;
    $ui = ui_name($ex->{ui_name}) if (defined $ex->{ui_name});

    if ($event->{response} eq 'OKAY') {
	foreach my $l (@{$ex->{text}}) {
	    $event->{server}->sendln($l);
	}
    } else {
	return unless $ui;

	my $deadfile = $ENV{HOME}."/.lily/tlily/dead.".$ex->{type};
	local *DF;
	my $rc = open(DF, ">$deadfile");
	if (!$rc) {
	    $ui->print("(export refused, edits lost!)\n");
	    return;
	}

	foreach my $l (@{$ex->{text}}) {
	    print DF $l, "\n";
	}
	$ui->print("(export refused, info saved to $deadfile)\n");
    }

    return;
}
event_r(type => 'export',
	call => \&export_handler);


sub info_cmd {
    my($ui, $args) = @_;
    my ($cmd,$disc) = split /\s+/, $args;
    my $server = active_server();

    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "info",
		       target => $disc,
		       text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(@_);
	};

	$server->fetch(ui     => $ui,
		       type   => "info",
		       target => $disc,
		       call   => $sub);
    }
    else {
	$server->sendln("/info $args");
    }
}

sub helper_cmd {
    my($ui, $args) = @_;
    my($cmd,@args) = split /\s+/, $args;
    my $server = active_server();

    my($target, $name);
    if (@args == 1) {
	($name) = @args;
    } else {
	($target, $name) = @args;
    }

    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "help",
		       target => $target,
		       name   => $name,
		       text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(@_);
	};

	$server->fetch(ui     => $ui,
		       type   => "help",
		       target => $target,
		       name   => $name,
		       call   => $sub);
    }
    elsif ($cmd eq 'list') {
        if (!defined($name)) {
            $server->sendln("?lsindex")
        } elsif (!defined($target)) {
            $server->sendln("?ls $name");
        } else {
            $server->sendln("?gethelp $target $name");
        }
    }
    elsif ($cmd eq 'clear' && defined($target)) {
        $server->sendln("?rmhelp $target $name");
    }
    else {
        $ui->print("Usage: %helper [list|set|edit|clear] index topic\n");
    }

}

sub memo_cmd {
    my($ui, $args) = @_;
    my($cmd,@args) = split /\s+/, $args;
    my $server = active_server();

    my($target, $name);
    if (@args == 1) {
	($name) = @args;
    } else {
	($target, $name) = @args;
    }

    if (!defined ($cmd)) {
	$server->sendln("/memo");
	return;
    }

    if ($cmd eq 'set') {
	if ($name =~ /^\d+$/) {
	    $ui->print("(memo name is a number)\n");
	    return;
	}

	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "memo",
		       target => $target,
		       name   => $name,
		       text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	if ($name =~ /^\d+$/) {
	    $ui->print("(you can only edit memos by name)\n");
	    return;
	}

	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(@_);
	};

	$server->fetch(ui     => $ui,
		       type   => "memo",
		       target => $target,
		       name   => $name,
		       call   => $sub);
    }
    else {
	$server->sendln("/memo $args");
    }
}

sub export_cmd {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    my $usage = "(%export [memo] file target; type %help for help)\n";

    # Ugh.  There HAS to be something cleaner than what follows.

    my($type, $file, $target, $name);

    if (@args > 0 && $args[0] eq "memo") {
	$type = "memo";
	shift @args;
    } else {
	$type = "info";
    }

    if (@args < 1) {
	$ui->print($usage); return;
    }
    $file = shift @args;

    if ($type eq "memo") {
	if (@args == 1) {
	    ($name) = @args;
	} elsif (@args == 2) {
	    ($target, $name) = @args;
	} else {
	    $ui->print($usage); return;
	}
    }
    else {
	if (@args == 1) {
	    ($target) = @args;
	} elsif (@args > 0) {
	    $ui->print($usage); return;
	}
    }

    local *FH;
    my $rc = open(FH, "<$file");
    unless ($rc) {
	$ui->print("(\"$file\": $!)\n");
	return;
    }
    my @text=<FH>;
    chomp(@text);
    close(FH);

    my $server = active_server();
    $server->store(ui     => $ui,
		   type   => $type,
		   target => $target,
		   name   => $name,
		   text   => \@text);
}

command_r('info'   => \&info_cmd);
command_r('helper' => \&helper_cmd);
command_r('memo'   => \&memo_cmd);
command_r('export' => \&export_cmd);
	       
shelp_r("info", "Improved /info functions");
help_r("info", "
%info set  [discussion]      - Loads your editor and allows you to set your 
                               /info
%info edit [discussion|user] - Allows you to edit or view (in your editor)
                               your /info, or that of a discussion or user.
			       (a handy way to save out someone's /info to 
			        a file or to edit a /info)
%info clear [discussion]     - Allows you to clear a /info.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");

shelp_r("export", "Export a file to /info");
help_r("export", "
%export \<filnename\> [discussion] - Allows you to set a /info to the contents of 
                               a file
");

shelp_r("memo", "Improved /memo functions");
help_r("memo", "
%memo [disc|user] name      - View a memo "name" on your memo pad, or that
                              of a discussion or another user.
%memo set [disc] name       - Allows you to set a memo "name" on your memo
                              pad, or a discussion's memo pad.
%memo edit [disc|user] name - Edit or view (in your editor) one of your memos,
                              or that of a discussion or another user (you can
                              only view those of users, of course).
%memo clear [disc] name     - Erase a memo.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");


shelp_r("helper", "lily help management functions");
help_r("helper", "
%helper set index topic      - Loads your editor and allows you to write help
                               text for the given topic in the given index. 
%helper edit index topic     - Allows you to edit help text for the given
                               topic in the given index. 
%helper clear index topic    - Clears the help text for the given topic in
                               the given index. 
%helper list [index [topic]] - Prints the index list if given no arguments.
                               Prints the contents of a given index, or if
                               and index and topic is given, will print the
                               current help text for it.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");

1;
