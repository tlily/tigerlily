# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/after.pl,v 1.1 1999/02/26 20:21:33 josh Exp $

TLily::User::command_r('after' => \&after_handler);
TLily::User::shelp_r('after' => "Run a lily command after a delay");
TLily::User::help_r('after', qq(Usage:
%after (offset) (command)
Runs (command) after (offset) amount of time.

%after
List all pending afters.

%after cancel (id)
Cancel after #(id).

offset can be:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days
));

my %after;
my %after_id;
my %after_when;
my $id=0;

sub after_handler {
    my($ui, $args) = @_;
    my(@F);
    if($args eq '') {
        $ui->print(sprintf("(%2s\t%-17s\t%s)", "Id", "When", "Command") . "\n");
	my $k;
	foreach $k (keys %after) {
       		($sec,$min,$hour,$mday,$mon,$year) = localtime($after_when{$k});
		$ui->print(sprintf("(%2d\t%02d:%02d:%02d %02d/%02d/%02d\t%s)", $k, $hour,$min,$sec,$mon,$mday,$year, $after{$k}) . "\n");
	}
	return 0;
    }
	
    if($args =~ /cancel\s+(\d+)\s*$/) {
	my $tbc = $1;
	$ui->print("(Cancelling afterid $tbc ($after{$tbc}))" . "\n");
	TLily::Event::time_u($after_id{$tbc});
	delete $after{$tbc}; delete $after_id{$tbc}; delete $after_when{$tbc};
	return 0;
    }

    $args =~ m/^\s*(\d+[hmsd]?)\s+(.*?)\s*$/;
    @F = ($1,$2);

    my $T;
    if($F[0] =~ m/^(\d+)s?$/) {
	$T = $1;
 	$W = time + $1;
    }
    elsif($F[0] =~ m/^(\d+)m$/) {
	$T = $1 * 60;
	$W = time + ($1 * 60);
    }
    elsif($F[0] =~ m/^(\d+)h$/) {
	$T = $1 * 3600;
	$W = time + ($1 * 3600);
    } 
    elsif($F[0] =~ m/^(\d+)d$/) {
	$T = $1 * 86400 ;
	$W = time + ($1 * 86400); 
    } 
    else {
	$ui->print("Usage: %after (offset) (command)" . "\n");
	return 0;
    }

    $after{$id} = $F[1];
    $after_when{$id} = $W;

    my $sub = sub {
	$ui->print("($F[0] of time have passed, running '$F[1]'.)" . "\n");
	TLily::Event::send(type => 'user_input',
			   text => "$F[1]");
	delete $after{$id};
    };
    $after_id{$id} = TLily::Event::time_r(after => $T,
					  call => $sub);

    $ui->print("(After $F[0] of time, I will run '$F[1]'.) (id $id)" . "\n");
    $id++;
    return 0;
}

sub unload() {
  foreach $k (keys %after) {
    $ui->print("(Cancelling afterid $k ($after{$k}))" . "\n");
    TLily::Event::time_u($after_id{$k});
    delete $after{$k}; delete $after_id{$k}; delete $after_when{$k};
  }
}

1;
