# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/info.pl,v 1.6 1999/04/03 01:03:26 neild Exp $

use strict;

sub fetch {
    my(%args) = @_;

    my $server = $args{server};
    my $call   = $args{call};
    my $type   = defined($args{type}) ? $args{type} : "info";
    my $target = defined($args{target}) ? $args{target} : "me";
    my $name   = $args{name};
    my $ui     = $args{ui};

    my $uiname;
    $uiname    = $ui->name() if ($ui);

    my @data;
    my $sub = sub {
	my($event) = @_;
	$event->{NOTIFY} = 0;
	if (defined($event->{text}) && $event->{text} =~ /^\* (.*)/) {
	    return if (($type eq "info") && (@data == 0) &&
		       ($event->{text} =~ /^\* Last Update: /));
	    push @data, substr($event->{text},2);
	} elsif ($event->{type} eq 'endcmd') {
	    $call->(server => $event->{server},
		    ui     => ui_name($uiname),
		    type   => $type,
		    target => $target,
		    name   => $name,
		    text   => \@data);
	}
	return;
    };

    if ($type eq "info") {
	$ui->print("(fetching info from server)\n") if ($ui);
	cmd_process("/info $target", $sub);
    } elsif ($type eq "memo") {
	$ui->print("(fetching memo from server)\n") if ($ui);
	cmd_process("/memo $target $name", $sub);
    }

    return;
}

sub store {
    my(%args) = @_;

    my $server = $args{server};
    my $text   = $args{text};
    my $type   = defined($args{type}) ? $args{type} : "info";
    my $target = defined($args{target}) ? $args{target} : "me";
    my $name   = $args{name};

    my $uiname;
    $uiname    = $args{ui}->name() if ($args{ui});

    if ($type eq "info") {
	my $size = @$text;
	my $t = $target;  $t = "" if ($target eq "me");
	$server->sendln("\#\$\# export_file info $size $t");
    }
    elsif ($type eq "memo") {
	my $size = 0;
	foreach (@$text) { $size += length($_); }
	my $t = $target;  $t = "" if ($target eq "me");
	$server->sendln("\#\$\# export_file memo $size $t $name");
    }

    push @{$server->{_export_queue}},
      { uiname => $uiname, text => $text, type => $type };

    return;
}

sub export_handler {
    my($event, $handler) = @_;

    my $ex = shift @{$event->{server}->{_export_queue}};
    return unless $ex;

    my $ui;
    $ui = ui_name($ex->{uiname}) if (defined $ex->{uiname});

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


sub edit_text {
    my($ui, $text) = @_;

    local(*FH);
    my $tmpfile = "/tmp/tlily.$$";
    my $mtime = 0;

    unlink($tmpfile);
    if (@{$text}) {
	open(FH, ">$tmpfile") or die "$tmpfile: $!";
	foreach (@{$text}) { chomp; print FH "$_\n"; }
	$mtime = (stat FH)[10];
	close FH;
    }

    $ui->suspend;
    TLily::Event::keepalive();
    system($config{editor}, $tmpfile);
    TLily::Event::keepalive(5);
    $ui->resume;

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
	$ui->print("(edit buffer file not found)\n");
	return;
    }

    if ((stat FH)[10] == $mtime) {
	close FH;
	unlink($tmpfile);
	$ui->print("(file unchanged)\n");
	return;
    }

    @{$text} = <FH>;
    chomp(@{$text});
    close FH;
    unlink($tmpfile);

    return 1;
}


sub info_cmd {
    my($ui, $args) = @_;
    my ($cmd,$disc) = split /\s+/, $args;
    my $server = server_name();

    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	store(server => $server,
	      ui     => $ui,
	      type   => "info",
	      target => $disc,
	      text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    store(@_);
	};

	fetch(server => $server,
	      ui     => $ui,
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

    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	store(server => $server,
	      ui     => $ui,
	      type   => "memo",
	      target => $target,
	      name   => $name,
	      text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    store(@_);
	};

	fetch(server => $server,
	      ui     => $ui,
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
    store(server => $server,
	  ui     => $ui,
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
