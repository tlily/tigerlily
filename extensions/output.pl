# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/Attic/output.pl,v 1.17 1999/03/03 23:18:22 josh Exp $

use strict;

use TLily::UI;
use TLily::Config qw(%config);

=head1 NAME

output.pl - The lily output formatter

=head1 DESCRIPTION

The job of output.pl is to register event handlers to convert the events
that the parser module (slcp.pl) send into appopriate output for the user.

=back

=cut


# Print private sends.
sub private_fmt {
    my($ui, $e) = @_;
    my $ts = '';
    
    $ui->print("\n");
    
    $ts = timestamp($e->{TIME}) if ($e->{STAMP});
    $ui->indent(private_header => " >> ");
    $ui->prints(private_header => "${ts}Private message from ",
		private_sender => $e->{SOURCE});
    if ($e->{RECIPS} =~ /,/) {
	$ui->prints(private_header => ", to ",
		    private_dest   => $e->{RECIPS});
    }
    $ui->prints(private_header => ":\n");
    
    $ui->indent(private_body => " - ");
    $ui->prints(private_body => $e->{VALUE}."\n");
    
    $ui->indent();
    $ui->style("default");
    return;
}
event_r(type  => 'private',
	order => 'before',
	call  => sub { $_[0]->{formatter} = \&private_fmt; return });

# Print public sends.
sub public_fmt {
    my($ui, $e) = @_;
    my $ts = '';
    
    $ui->print("\n");
    
    $ts = timestamp ($e->{TIME}) if ($e->{STAMP});
    $ui->indent(public_header => " -> ");
    $ui->prints(public_header => "${ts}From ",
		public_sender => $e->{SOURCE},
		public_header => ", to ",
		public_dest   => $e->{RECIPS},
		public_header => ":\n");
    
    $ui->indent(public_body   => " - ");
    $ui->prints(public_body   => $e->{VALUE}."\n");
    
    $ui->indent();
    $ui->style("default");
    
    return;
}
event_r(type  => 'public',
	order => 'before',
	call  => sub { $_[0]->{formatter} = \&public_fmt; return });

# Print emote sends.
sub emote_fmt {
    my($ui, $e) = @_;
    
    $ui->indent(emote_body   => "> ");
    $ui->prints(emote_body   => "(to ",
		emote_dest   => $e->{RECIPS},
		emote_body   => ") ",
		emote_sender => $e->{SOURCE},
		emote_body   => $e->{VALUE}."\n");
    
    $ui->indent();
    $ui->style("default");
    
    return;
}
event_r(type  => 'emote',
	order => 'before',
	call  => sub { $_[0]->{formatter} = \&emote_fmt; return });


# %U: source's pseudo and blurb
# %u: source's pseudo
# %V: VALUE
# %T: title of discussion whose name is in VALUE.
# %R: RECIPS
# %O: name of thingy whose OID is in VALUE.
# %S: timestamp, if STAMP is defined, empty otherwise.
# %B: if SOURCE has a blurb " with the blurb [blurb]", else "".
#
# leading characters (up to first space) define behavior as follows: 
# A: always use this message
# V: use this message if VALUE is defined.
# E: use this message if VALUE is empty.
# D: use this message if RECIP is defined. (hack for EVENT=info)
# v: use this message if the source of the event is "me" and VALUE is defined
# e: use this message if the source of the event is "me" and the VALUE is empty
# d: use this message if the source of the event is "me" and RECIP is defined
#    (hack for EVENT=info)

# the first matching message is always used.

my @infomsg = ('connect'  => 'A *** %S%U has entered lily ***',
	       attach     => 'A *** %S%U has reattached ***',
	       disconnect => 'V *** %S%U has left lily (%V) ***',
	       disconnect => 'E *** %S%U has left lily ***',
	       detach     => 'E *** %S%U has detached ***',
	       detach     => 'V *** %S%U has been detached %V ***',
	       here       => 'e (you are now here%B)',
	       here       => 'E *** %S%U is now "here" ***',
	       away       => 'e (you are now away%B)',
	       away       => 'E *** %S%U is now "away" ***',
	       away       => 'V *** %S%U has idled "away" ***', # V=idled really.
	       'rename'   => 'v (you are now named %V)',
	       'rename'   => 'V *** %S%u is now named %V ***',
	       blurb      => 'e (your blurb has been turned off)',
	       blurb      => 'v (your blurb has been set to [%V])',
	       blurb      => 'V *** %S%u has changed their blurb to [%V] ***',
	       blurb      => 'E *** %S%u has turned their blurb off ***',
	       info       => 'd (you have changed the info for %R)',
	       info       => 'e (your info has been cleared)',
	       info       => 'v (your info has been changed)',
	       info       => 'D *** Discussion %R has changed info ***',
	       info       => 'V *** %S%u has changed their info ***',
	       info       => 'E *** %S%u has cleared their info ***',
	       ignore     => 'A *** %S%u is now ignoring you %V ***',
	       unignore   => 'A *** %S%u is no longer ignoring you ***',
	       unidle     => 'A *** %S%u is now unidle ***',
	       create     => 'e (you have created discussion %R "%T")',
	       create     => 'E *** %S%u has created discussion %R "%T" ***',
	       destroy    => 'e (you have destroyed discussion %R)',
	       destroy    => 'E *** %S%u has destroyed discussion %R ***',
	       # bugs in slcp- permit/depermit don't specify people right.
#	       permit     => 'e (someone is now permitted to discussion %R)',
#	       permit     => 'E (You are now permitted to some discussion)',
#	       depermit   => 'e (Someone is now depermitted from %R)',
	       # note that slcp doesn't do join and quit quite right
	       permit     => 'V *** %S%O is now permitted to discussion %R ***',
	       depermit   => 'V *** %S%O is now depermitted from %R ***',
	       'join'     => 'e (you have joined %R)',
	       'join'     => 'E *** %S%u is now a member of %R ***',
	       quit       => 'e (you have quit %R)',
	       quit       => 'E *** %S%u is no longer a member of %R ***',
	       retitle    => 'v (you have changed the title of %R to "%V")',
	       retitle    => 'V *** %S%u has changed the title of %R to "%V" ***',
	       sysmsg     => 'V %V',
	       pa         => 'V ** %SPublic address message from %U: %V **'
	       # need to handle review, sysalert, pa, game, and consult.
	      );

my $sub = sub {
    my ($e, $h) = @_;
    my $serv = $e->{server};
    return unless ($serv);
    
    # optimization?
    #return unless ($e->{NOTIFY});
    
    my $Me =  $serv->user_name;
    
    my $i = 0;
    my $found;
    while ($i < $#infomsg) {
	my $type = $infomsg[$i];
	my $msg  = $infomsg[$i + 1];
	my $flags;
	$i += 2;
	
	next unless ($type eq $e->{type});
	($flags,$msg) = ($msg =~ /(\S+) (.*)/);
	if ($flags =~ /A/) {
	    $found = $msg; last;
	}
	if ($flags =~ /V/ && ($e->{VALUE} =~ /\S/)) { 
	    $found = $msg; last; 
	}
	if ($flags =~ /E/ && ($e->{VALUE} !~ /\S/)) {
	    $found = $msg; last;
	}
	if ($flags =~ /D/ && (defined ($e->{RECIPS}))) {
	    $found = $msg; last;
	}
	if ($flags =~ /v/ && ($e->{SOURCE} eq $Me)
	    && (defined($e->{VALUE}) && length($e->{VALUE}))) {
	    $found = $msg; last;
	}
	if ($flags =~ /e/ && ($e->{SOURCE} eq $Me)
	    && (!defined($e->{VALUE}) || !length($e->{VALUE}))) {
	    $found = $msg; last;
	}
	if ($flags =~ /d/ && ($e->{SOURCE} eq $Me)
	    && (defined ($e->{RECIPS}))) {
	    $found = $msg; last;
	}
    }
    
    if ($found) {
	my $source = $e->{SOURCE};
	$found =~ s/\%u/$source/g;
	my $blurb = $serv->get_blurb(HANDLE => $e->{SHANDLE});
	$source .= " [$blurb]" if $blurb;
	$found =~ s/\%U/$source/g;
	$found =~ s/\%V/$e->{VALUE}/g;
	$found =~ s/\%R/$e->{RECIPS}/g;
	my $ts = ($e->{STAMP}) ? timestamp($e->{TIME}) : '';
	$found =~ s/\%S/$ts/g;
	if ($found =~ m/\%O/) {
	    my $target = $serv->get_name(HANDLE => $e->{VALUE});
	    $found =~ s/\%O/$target/g;
	}
	if ($found =~ m/\%T/) {
	    my $title = $serv->get_title(NAME => $e->{RECIPS});
	    $found =~ s/\%T/$title/g;
	}
	if ($found =~ m/\%B/) {
	    if ($blurb) {
		$found =~ s/\%B/ with the blurb [$blurb]/g;
	    } else {
		$found =~ s/\%B//g;
	    }
	}
	
	$e->{text} = $found;
	$e->{slcp} = 1;
    }
    
    return;
};

event_r(type  => 'all',
	order => 'before',
	call  => $sub);

sub timestamp {
    my ($time) = @_;
    
    my ($min, $hour) = (localtime($time))[1,2];
    my $t = ($hour * 60) + $min;
    my $ampm = '';
    $t += $config{zonedelta};
    $t += (60 * 24) if ($t < 0);
    $t -= (60 * 24) if ($t >= (60 * 24));
    $hour = int($t / 60);
    $min  = $t % 60;
    if ($config{zonetype} eq '12') {
	if ($hour >= 12) {
	    $ampm = 'p';
	    $hour -= 12 if $hour > 12;
	} else {
	    $ampm = 'a';
		}
	}
	return sprintf("(%02d:%02d%s) ", $hour, $min, $ampm);
}
