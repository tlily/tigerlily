# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/submit.pl,v 1.8 2000/12/21 21:32:22 coke Exp $

use TLily::Version;
use strict;

my $TLILY_BUGS = "tigerlily-bugs\@tlily.centauri.org";

# Issue report template
my $template = 
"From:
To: $TLILY_BUGS
Subject:
Date:

Full_Name:
Lily_Core:
Lily_Server:
tlily_Version: $TLily::Version::VERSION
OS:

Description:
";

my $version;

sub submit_cmd($) {
    my $ui = shift @_;
    my($submit_to,$recover)=split /\s+/, "@_";
 
    if (defined($recover) && $recover ne "-r" && $recover ne "") {
	$ui->print("Usage: %submit {server|client} [-r]\n");
	return;
    }
    $recover = ($recover eq "-r")?1:0;
    
    if ($submit_to =~ /^server$/) {
	$ui->print("(Sorry, %submit server not yet implemented - Feel Free(TM))\n");
	return;
    } elsif ($submit_to =~ "client") {	
	  # Get the version of the lily core we're on.
	  my $server = active_server();
	  $server->cmd_process("/display version", sub {
			  my($event) = @_;
			  $event->{NOTIFY} = 0;
			  if ($event->{text} =~ /^\((.*)\)/) {
			      $version = $1;
			  } elsif ($event->{type} eq 'endcmd') {
			      edit_report(ui => $ui,
					  version=>$version,
					  recover=>$recover);
			  }
			  return 0;
		      });
    } else {
	$ui->print("Usage: %submit {server|client} [-r]\n");
	return;
    }
}
	  
sub edit_report(%) {
    my %args=@_;
    
    my $form = $template;
    my $ui = $args{'ui'};
    
    my $tmpfile = "$::TL_TMPDIR/tlily.submit.$$";
    
    if ($args{'recover'}) {
	$ui->print("(Recalling saved report)\n");
	my $rc = open(FH, "<$tmpfile");
	unless ($rc) {
	    $ui->print("(edit buffer file not found)\n");
	    return;
	}
	$form = join("",<FH>);
	close FH;
    }
    
    $form =~ s/^Lily_Core:$/Lily_Core: $args{'version'}/m;
    $form =~ s/^Lily_Server:$/Lily_Server: $config{'server'}:$config{'port'}/m;
    my $OS = `uname -a`;
    chomp $OS;
    $form =~ s/^OS:$/OS: $OS/m;
    my @pw = getpwuid $<;
    $pw[6] =~ s/,.*$//;
    $form =~ s/^From:$/From: $pw[0]/m;
    $form =~ s/^Full_Name:$/Full_Name: $pw[6]/m;
    my $date = gmtime() . " GMT";
    $form =~ s/^Date:.*$/Date: $date/m;
    local(*FH);
    my $mtime = 0;
    
    unlink($tmpfile);
    open(FH, ">$tmpfile") or die "$tmpfile: $!";
    print FH "$form";
    $mtime = (stat FH)[10];
    close FH;
    
    $ui->suspend;
    TLily::Event::keepalive();
    system("$config{editor} $tmpfile");
    TLily::Event::keepalive(5);
    $ui->resume;
    
    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
	$ui->print("(edit buffer file not found)\n");
	return;
    }
    
    if ((stat FH)[10] == $mtime) {
	$ui->print("(report not submitted)\n");
	close FH;
	unlink($tmpfile);
	return;
    }
    
    my @data = <FH>;
    close FH;
    $form = join("",@data);
    if ($form =~ /Description:$/) {
	$ui->print("(No description - report not submitted; please re-edit with %submit -r)\n");
	return;
    }
    if ($form =~ /^Subject:$/m) {
	$ui->print("(No subject - report not submitted; please re-edit with %submit -r)\n");
	return;
    }
    
    
    open(FH, "|/usr/lib/sendmail -oi $TLILY_BUGS");
    print FH $form;
    close FH;
    
    unlink($tmpfile);
    
    $ui->print("(Report submitted)\n");
}


command_r('submit' => \&submit_cmd);

shelp_r("submit" => "Submit a bug report");
help_r("submit",  <<END
Usage: %submit client [-r]
       %submit server [-r]

Submits a bug report, either for the server or for the client (Tigerlily).
Will start your editor with a form for you to fill out.  Will automatically
retrieve basic information about your environment (versions, OS, etc), and
put that in the form, too.
If for some reason it isn't able submit your report, you can recover the
report with the -r option.
END
);


1;
