use strict;

use TLily::UI;

=head1 NAME

output.pl - The lily output formatter

=head1 DESCRIPTION

The job of output.pl is to register event handlers to convert the events
that the parser module (slcp.pl) send into appopriate output for the user.

=back

=cut

my $sub = sub {
    my($e, $h) = @_;
    
    my $ui = TLily::UI::name("main");
    $ui->print("Event: $e->{type}\n");
    foreach (sort keys %$e) {
	next if ($_ eq "type");
	my $val = $e->{$_};
	$ui->print("  $_=");
	if (defined($val)) {
	    $val =~ s/\r/\\r/gs;
	    $val =~ s/\n/\\n/gs;
	    $ui->print("\"$val\"");
	} else {
	    $ui->print("undef");
	}
    }
    $ui->print("\n");
    return;
};
#TLily::Event::event_r(type => 'all', call => $sub);


sub private_fmt {
    my($ui, $e) = @_;
    
    $ui->print("\n");
    
    $ui->indent(" >> ");
    $ui->prints(privhdr => "Private message from ",
		sender  => $e->{SOURCE});
    if ($e->{RECIPS} =~ /,/) {
	$ui->prints(privhdr => ", to ",
		    dest    => $e->{RECIPS});
    }
    $ui->style("privhdr");
    $ui->print(":\n");
    
    $ui->indent(" - ");
    $ui->style("privmsg");
    $ui->print($e->{VALUE}, "\n");
    $ui->indent("");
  
    $ui->style("default");
  return;
}
TLily::Event::event_r(type  => 'private',
		      order => 'before',
		      call  => sub { $_[0]->{formatter} = \&private_fmt; return });

sub public_fmt {
    my($ui, $e) = @_;
    
    $ui->print("\n");
    
    $ui->indent(" -> ");
    $ui->prints(pubhdr => "From ",
		sender => $e->{SOURCE},
		pubhdr => ", to ",
		dest   => $e->{RECIPS},
		pubhdr => ":\n");
    
    $ui->indent(" - ");
    $ui->style("pubmsg");
    $ui->print($e->{VALUE}, "\n");
    $ui->indent("");
    
    $ui->style("default");
    
    return;
}
TLily::Event::event_r(type  => 'public',
		      order => 'before',
		      call  => sub { $_[0]->{formatter} = \&public_fmt; return });

sub emote_fmt {
    my($ui, $e) = @_;
    
    $ui->style("emote");
    $ui->indent("> ");
    $ui->print("(to ", $e->{RECIPS}, ") ", $e->{SOURCE}, $e->{VALUE},"\n");
    $ui->indent("");
    $ui->style("default");
    
    return;
}
TLily::Event::event_r(type  => 'emote',
		      order => 'before',
		      call  => sub { $_[0]->{formatter} = \&emote_fmt;
				     return });


# %U: source's pseudo and blurb
# %u: source's pseudo
# %V: VALUE
# %T: title of discussion whose name is in VALUE.
# %R: RECIPS
# %O: name of thingy whose OID is in VALUE.
#
# leading characters (up to first space) define behavior as follows: 
# A: always use this message
# V: use this message if VALUE is defined.
# E: use this message if VALUE is empty.
# v: use this message if the source of the event is "me" and VALUE is defined
# e: use this message if the source of the event is "me" and the VALUE is empty

# the first matching message is always used.

my @infomsg = ('connect'  => 'A *** %U has entered lily ***',
	       attach     => 'A *** %U has reattached ***',
	       disconnect => 'V *** %U has left lily (%V) ***',
	       disconnect => 'E *** %U has left lily ***',
	       detach     => 'E *** %U has detached ***',
	       detach     => 'V *** %U has been detached %V ***',
	       here       => 'e (you are now here)',
	       here       => 'E *** %U is now "here" ***',
	       away       => 'e (you are now away)',
	       away       => 'E *** %U is now "away" ***',
	       away       => 'V *** %U has idled "away" ***', # V=idled really.
	       'rename'   => 'v (you are now named %V)',
	       'rename'   => 'V *** %u is now named %V ***',
	       blurb      => 'e (your blurb has been turned off)',
	       blurb      => 'v (your blurb has been set to [%V])',
	       blurb      => 'V *** %u has changed their blurb to [%V] ***',
	       blurb      => 'E *** %u has turned their blurb off ***',
	       info       => 'e (your info has been cleared)',
	       info       => 'v (your info has been changed)',
	       info       => 'V *** %u has changed their info ***',
	       info       => 'E *** %u has cleared their info ***',
	       ignore     => 'A *** %u is now ignoring you %V ***',
	       unignore   => 'A *** %u is no longer ignoring you ***',
	       unidle     => 'A *** %u is now unidle ***',
	       create     => 'e (you have created discussion %R "%T")',
	       create     => 'E *** %u has created discussion %R "%T" ***',
	       destroy    => 'e (you have destroyed discussion %R)',
	       destroy    => 'E *** %u has destroyed discussion %R ***',
	       # bugs in slcp- permit/depermit don't specify people right.
	       #	       permit     => 'e (someone is now permitted to discussion %R)',
	       #	       permit     => 'E (You are now permitted to some discussion)',
	       #	       depermit   => 'e (Someone is now depermitted from %R)',
	       # note that slcp doesn't do join and quit quite right
	       permit     => 'V *** %O is now permitted to discussion %R ***',
	       depermit   => 'V *** %O is now depermitted from %R ***',
	       'join'     => 'e (you have joined %R)',
	       'join'     => 'E *** %u is now a member of %R ***',
	       quit       => 'e (you have quit %R)',
	       quit       => 'E *** %u is no longer a member of %R ***',
	       retitle    => 'v (you have changed the title of %R to "%V")',
	       retitle    => 'V *** %u has changed the title of %R to "%V" ***',
	       sysmsg     => 'V %V',
	       pa         => 'V ** Public address message from %U: %V **'
	       # need to handle review, sysalert, pa, game, and consult.
	      );

$sub = sub {
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
	if ($flags =~ /v/ && ($e->{SOURCE} eq $Me)
	    && (defined($e->{VALUE}) && length($e->{VALUE}))) {
	    $found = $msg; last;
	}
	if ($flags =~ /e/ && ($e->{SOURCE} eq $Me)
	    && (!defined($e->{VALUE}) || !length($e->{VALUE}))) {
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
	if ($found =~ m/\%O/) {
	    my $target = $serv->get_name(HANDLE => $e->{VALUE});
	    $found =~ s/\%O/$target/g;
	}
	if ($found =~ m/\%T/) {
	    my $title = $serv->get_title(NAME => $e->{RECIPS});
	    $found =~ s/\%T/$title/g;
	}
	
	$e->{text} = "SLCP: $found";
    }
    
    return;
};

TLily::Event::event_r(type  => 'all',
		      order => 'before',
		      call  => $sub);

