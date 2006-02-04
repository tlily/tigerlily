# -*- Perl -*-
# $Id$

use TLily::Version;
use Config;
use strict;

my $TLILY_BUGS = "tigerlily-bugs\@tlily.org";

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
    
    if (!defined(determine_mail_method($ui))) {
        $ui->print("(Sorry, %submit is not available on the $^O platform at this time.)\n");
	return;
    }
    
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
					  type => $submit_to,
					  version => $version,
					  recover => $recover);
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
    $form =~ s/^OS:$/OS: $Config{'archname'}/m;
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
	$ui->print("(No description - report not submitted; please re-edit with %submit $args{'type'} -r)\n");
	return;
    }
    if ($form =~ /^Subject:$/m) {
	$ui->print("(No subject - report not submitted; please re-edit with %submit -r)\n");
	return;
    }
    if ($form !~ /^From:.* <?([^\@\n]+\@[^\@\s\n]+)>?.*$/m) {
	$ui->print("(No From address - report not submitted; please re-edit with %submit -r)\n");
        return;
    }
    my $from_addr = $1;
    
    TLily::Event::keepalive();
    eval { sendmail($from_addr, $form, $ui); };
    if ($@) {
        $ui->print("(Submission failed: $@)\n");
        return;
    }
    TLily::Event::keepalive(5);

    unlink($tmpfile);
    
    $ui->print("(Report submitted)\n");
}


sub determine_mail_method {
    my $ui = shift;
    my $method = undef;
    foreach ('/usr/lib/sendmail', '/usr/sbin/sendmail') {
        if (-x $_) {
            $method = $_;
            last;
        }
    }
    if (!defined($method)) {
        eval 'use Net::SMTP;';
        $method = 'Net::SMTP' unless ($@);
    }

    return $method;
}


sub sendmail {
    my $from = shift;
    my $mail = shift;
    my $ui = shift;

    my $method = determine_mail_method($ui);

    if ($method =~ m|^/|) {
        my $rc = open(FH, "|$method -oi $TLILY_BUGS");
        if ($rc) {
            print FH $mail;
            close FH;
        } else {
            die "sendmail: $!";
        }
    } elsif ($method eq 'Net::SMTP') {
        my $smtp = Net::SMTP->new('bugs.tlily.org');
        my $rc;
        $smtp->mail($from) ||
            die "Remote server didn't like from address ($from).";
        $smtp->to($TLILY_BUGS) ||
            die "Remote server didn't like recipient address ($TLILY_BUGS).";
        $rc = $smtp->data($mail) ||
            die "Remote server didn't like message body.";
        $smtp->quit;
    } else {
        die "No method available to send mail.";
    }
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

# ' <- This single quote is here to resync Emacs font-lock-mode

1;
