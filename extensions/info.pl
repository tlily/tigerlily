# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/info.pl,v 1.12 1999/09/25 18:30:28 mjr Exp $

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
    my $server = server_name();

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

sub memo_cmd {
    my($ui, $args) = @_;
    my($cmd,@args) = split /\s+/, $args;
    my $server = server_name();

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

    my $server = server_name();
    $server->store(ui     => $ui,
		   type   => $type,
		   target => $target,
		   name   => $name,
		   text   => \@text);
}

command_r('info'   => \&info_cmd);
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


1;
