# -*- Perl -*-

use strict;

sub view_cmd($;$$) {
    my ($ui,$cmd,$filter,$doneproc) = @_;

    my @lines = ();
    my $server = active_server();
    $server->cmd_process($cmd, sub {
        my($event) = @_;
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
            if ($doneproc) {
                &{$doneproc}(\@lines);
            } else {
                edit_text($ui,\@lines,1);
            }
        } elsif ( $event->{type} ne 'begincmd' &&
                  ( ! $filter || &{$filter}($event->{text}) ) ) {
            $event->{text}=~s/^\n//g;
            push @lines, $event->{text};
        }
        return 0;
    });
}


command_r('view', \&view_cmd);
shelp_r('view', 'sends output of lily command to an editor');
help_r('view', "This allows you to get the output of a command into a temporary buffer and loads an editor to allow you to save it to a file or perhaps do a quick search or two.  For example, you can do a \"%view /review detach\", and then save your detach buffer, so you can respond to real-time messages, while still keeping an eye on the past in another window.");

1;
