# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/info.pl,v 1.3 1999/02/28 21:54:24 steve Exp $

sub info_set {
    my ($ui,%args)=@_;
    
    my $disc=$args{disc};
    my $edit=$args{edit};
    my @data=@{$args{data}};
    
    if ($edit) {
	local(*FH);
        my $tmpfile = "/tmp/tlily.$$";
	my $mtime = 0;
	
	unlink($tmpfile);
	if (@data) {
	    open(FH, ">$tmpfile") or die "$tmpfile: $!";
	    foreach (@data) { chomp; print FH "$_\n"; }
	    $mtime = (stat FH)[10];
	    close FH;
	}

	$ui->suspend;
	system("$config{editor} $tmpfile");
	$ui->resume;

	my $rc = open(FH, "<$tmpfile");
	unless ($rc) {
	    $ui->print("(info buffer file not found)\n");
	    return;
	}

	if ((stat FH)[10] == $mtime) {
	    $ui->print("(info not changed)\n");
	    close FH;
	    unlink($tmpfile);
	    return;
	}
	
	@data = <FH>;
	close FH;
	unlink($tmpfile);
    }
    
    my $size=@data;
    

    my $sub = sub {
	my($event,$handler) = @_;
	my $server = server_name();
	my $ui = ui_name();

	if ($event->{response} eq 'OKAY') {
	    my $l;
	    foreach $l (@data) {
		$server->send($l);
	    }
	} else {
	    my $deadfile = $ENV{HOME}."/.lily/tlily/dead.info";
	    my $rc = open(DF, ">$deadfile");
	    if ($rc) {
		print DF @data;
		close(DF);
		$ui->print("(export refused, info saved to $deadfile)\n");
	    } else {
		$ui->print("(export refused, edits lost!)\n");
	    }
	}
	event_u($handler->{id});
	return 0;
    };
    event_r(type => 'export',
	    call => $sub);
    
    my $server = server_name();
    $server->sendln("\#\$\# export_file info $size $disc");
}


sub info_edit {
    my($ui,$target) = @_;
    
    my $server = server_name();
    my $itarget = $target || $server->user_name();
    
    $ui->print("(getting info for $itarget)\n");
    my @data = ();
    cmd_process("/info $itarget", sub {
		    my($event) = @_;
		    $event->{NOTIFY} = 0;
		    if ($event->{text} =~ /^\* (.*)/) {
			return if ((@data == 0) &&
				   ($event->{text} =~ /^\* Last Update: /));
			push @data, substr($event->{text},2);
		    } elsif ($event->{type} eq 'endcmd') {
			map { s/\\(.)/$1/g } @data;
			info_set($ui,
				 disc=>$target,
				 data=>\@data,
				 edit=>1);
		    }
		    return 0;
		});
}
	      
	      
sub info_cmd {
    my $ui = shift @_;
    my ($cmd,$disc) = split /\s+/,"@_";
    if ($cmd eq 'set') {
	info_set($ui,
		 disc=>$disc,
		 edit=>1);
    } elsif ($cmd eq 'edit') {
	info_edit($ui,$disc);
    } else {
	my $server = server_name();
	$server->sendln("/info @_");
    }
}
	     
sub export_cmd {
    my ($file, $disc);
    my $ui = shift @_;
    my @args=split /\s+/,"@_";
    if (@args == 1) {
	($file) = @args;
    } else {
	($file,$disc) = @args;
    }
    my $rc=open(FH, "<$file");
    unless ($rc) {
	$ui->print("(file \"$file\" not found)\n");
	return;
    }
    @lines=<FH>;
    close(FH);
    info_set($ui,
	     data=>\@lines,
	     disc=>$disc,
	     edit=>0);
}


command_r('info'   => \&info_cmd);
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
