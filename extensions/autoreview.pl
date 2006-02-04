# -*- Perl -*-
# $Id$

use strict;

=head1 NAME

autoreview.pl - '/review detach' designated discussions

=head1 DESCRIPTION

This extension provides the %autoreview command, which will perform a
'/review detach' on the discusions listed in the @autoreview configuration
variable.  If the extension is autoloaded (see ...), it will perform
an %autoreview at connect-time.

=head1 COMMANDS

=over 10

=item %autoreview

Reviews the discussions listed in the @autoreview configuration
variable.  See "%help autoreview" for more details.

=back

=head1 CONFIGURATION

=over 10

=item autoreview

A list of discussions to be reviewed by the %autoreview command, or
when connecting to the server, if the autoreview.pl extension is
autoloaded.

=back

=cut

event_r(type  => 'connected',
	order => 'after',
	call  => \&connected_handler);

command_r('autoreview', \&review_cmd);

shelp_r('autoreview' => 'A list of discussions to autoreview', 'variables');
help_r('variables autoreview' => 'A list of discussions to autoreview.');

shelp_r('autoreview', '/review detach on multiple discs');
help_r('autoreview', <<END );
%autoreview reviews the discussions listed in the \@autoreview configuration
variable.  It removes all lines beginning with *** from the review.  It
does not print timestamp lines unless the review contains actual sends to
the discussions.

When the autoreview extension is autoloaded, an autoreview will be performed
at connect-time.

By default, autoreview will perform a "/review detach".  You may pass
alternate criteria to the autoreview command--for example, "%autoreview
last 1h".
END

my @to_review;
my $rev_interesting = 0;
my $rev_start;
my $rev_args;

sub connected_handler {
    my($event, $handler) = @_;

    $rev_args = "detach";
    review_start($event->{server});
    return 0;
}

sub review_cmd {
    my ($ui, $args) = @_;
    if (@to_review) {
	$ui->print("(You are currently autoreviewing)\n");
	return 0;
    }
    my $server = active_server();
    $rev_args = $args || "detach";
    review_start($server);
    return 0;
}

sub review_start {
    my ($server) = @_;       

    eval { @to_review = @{$config{autoreview}} };
    return unless (@to_review); 
    review($server);
}

sub review {
    my ($server) = @_;
    
    return unless (@to_review);
    my $target = shift @to_review;
    $rev_interesting = 0;
    $rev_start = undef;
    $server->cmd_process("/review $target $rev_args", \&review_handler);
}

sub review_handler {
    my($event) = @_;
    if ($event->{type} eq 'begincmd') {
    } elsif ($event->{type} eq 'endcmd') {
	review($event->{server});
    } elsif ($event->{text} =~ /^\(Beginning review.*\)/) {
	$rev_start = $event->{text};
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^\(End of review.*\)/) {
	$event->{NOTIFY} = 0 unless ($rev_interesting);
    } elsif ($event->{text} eq "") {
	$event->{NOTIFY} = 0 unless ($rev_interesting);
    } elsif ($event->{text} =~ /^\(No events to review for .*\)/) {
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^\(There are no events that match.*\)/) {
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^\# \*\*\*/) {
	$event->{NOTIFY} = 0;
    } elsif ($event->{text} =~ /^\# \#\#\#/ && !$rev_interesting) {
	$event->{NOTIFY} = 0;
	$rev_start .= "\n" . $event->{text};
    } elsif (!$rev_interesting) {
	$rev_interesting = 1;
	ui_name()->print("$rev_start\n") if (defined $rev_start);
    }
    return 0;
}


1;
