use strict;

event_r(type  => 'connected',
	order => 'after',
	call  => \&connected_handler);

command_r('autoreview', \&review_cmd);
shelp_r('autoreview', '/review detach on multiple discs');
help_r('autoreview', <<END );
%autoreview reviews the discussions listed in the \@autoreview configuration
variable.  It removes all lines beginning with *** from the review.  It
does not print timestamp lines unless the review contains actual sends to
the discussion.

When the autoreview extension is autoloaded, an autoreview will be performed
at connect-time.
END

my @to_review;
my $rev_interesting = 0;
my $rev_start;

sub connected_handler {
    my($event, $handler);
    event_u($handler);
    
    review_start();
    return 0;
}

sub review_cmd {
    my ($ui) = @_;
    if (@to_review) {
	$ui->print("(You are currently autoreviewing)\n");
	return 0;
    }
    review_start();
    return 0;
}

sub review_start {
    eval { @to_review = @{$config{autoreview}} };
    return unless (@to_review); 
    review();
}

sub review {
    return unless (@to_review);
    my $target = shift @to_review;
    cmd_process("/review " . $target . " detach", \&review_handler);
}

sub review_handler {
    my($event) = @_;
    if ($event->{type} eq 'begincmd') {
	$rev_interesting = 0;
	$rev_start = undef;
    } elsif ($event->{type} eq 'endcmd') {
	review();
    } elsif ($event->{text} =~ /^\(Beginning review of.*\)/) {
	$rev_start = $event->{text};
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^\(End of review of.*\)/) {
	$event->{NOTIFY} = 0 unless ($rev_interesting);
    } elsif ($event->{text} eq "") {
	$event->{NOTIFY} = 0 unless ($rev_interesting);
    } elsif ($event->{text} =~ /^\(No events to review for .*\)/) {
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^ \# \*\*\*/) {
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^ \# \#\#\#/ && !$rev_interesting) {
	$event->{NOTIFY} = 0;
	$rev_start .= "\n" . $event->{text};
    } elsif (!$rev_interesting) {
	$rev_interesting = 1;
	ui_name()->print("$rev_start\n") if (defined $rev_start);
    }
    return 0;
}


1;
