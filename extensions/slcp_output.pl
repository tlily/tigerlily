# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/slcp_output.pl,v 1.11.2.2 1999/12/08 07:28:44 mjr Exp $

use strict;

use TLily::UI;
use TLily::Config qw(%config);

=head1 NAME

output.pl - The lily output formatter

=head1 DESCRIPTION

The job of output.pl is to register event handlers to convert the events
that the parser module (slcp.pl) send into appopriate output for the user.

=cut


# Print private sends.
sub private_fmt {
    my($ui, $e) = @_;
    my $ts = '';
    my $blurb = $e->{server}->get_blurb(HANDLE => $e->{SHANDLE});
    
    $ui->print("\n");
    
    my $source = $e->{SOURCE};
    $source .= "\@" . $e->{server}->name()
      if (scalar(TLily::Server::find()) > 1);

    $ts = timestamp($e->{TIME}) if ($e->{STAMP});
    $ui->indent(private_header => " >> ");
    $ui->prints(private_header => "${ts}Private message from ",
		private_sender => $source);
    $ui->prints(private_header => " [$blurb]")
      if (defined $blurb && ($blurb ne ""));
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
    my $blurb = $e->{server}->get_blurb(HANDLE => $e->{SHANDLE});
    
    $ui->print("\n");
    
    my $source = $e->{SOURCE};
    $source .= "\@" . $e->{server}->name()
      if (scalar(TLily::Server::find()) > 1);

    $ts = timestamp ($e->{TIME}) if ($e->{STAMP});
    $ui->indent(public_header => " -> ");
    $ui->prints(public_header => "${ts}From ",
		public_sender => $source);
    $ui->prints(public_header => " [$blurb]")
      if (defined $blurb && ($blurb ne ""));
    $ui->prints(public_header => ", to ",
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
    my $ts = '';
    
    my $dest = $e->{RECIPS};
    $dest .= "\@" . $e->{server}->name()
      if (scalar(TLily::Server::find()) > 1);

    $ts = etimestamp ($e->{TIME}) if ($e->{STAMP} || $config{'stampemotes'});
    $ui->indent(emote_body   => "> ");
    $ui->prints(emote_body   => "(${ts}to ",
		emote_dest   => $dest,
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
# %D: title of discussion whose name is in VALUE.
# %R: RECIPS
# %P: TARGETS
# %O: name of thingy whose OID is in VALUE.
# %T: timestamp, if STAMP is defined, empty otherwise.
# %S: '(servername)', if connected to more than one, empty otherwise.
# %B: if SOURCE has a blurb " with the blurb [blurb]", else "".
# %E: SUBEVT
#
# leading characters (up to first space) define behavior as follows:
#### Catch all: mutually exclusive with all other flags
# A: always use this message
#### VALUE flags: mutually exclusive with each other
# E: use this message if VALUE is EMPTY.  Always order this before U, since
#    U will also match EMPTY.
# V: use this message if VALUE is defined.
# U: use this message if VALUE is undefined.
#### RECIPS flags: mutually exclusive with each other
# D: use this message if RECIP is defined. (hack for EVENT=info)
####
# S: SOURCE is "me"
####
# M: TARGETS contains "me"
# T: TARGETS defined
# t: TARGETS undefined
####
# C="val"; : use this message if SUBEVT is defined and equals val.
# C: use this message if SUBEVT is defined.
# c: use this message if SUBEVT is undefined.
####

# the first matching message is always used.

my @infomsg = (
    'connect'    => 'A'    => '*** %S%T%U has entered lily ***',
    'attach'     => 'A'    => '*** %S%T%U has reattached ***',
    'disconnect' => 'V'    => '*** %S%T%U has left lily (%V) ***',
    'disconnect' => 'U'    => '*** %S%T%U has left lily ***',
    'detach'     => 'U'    => '*** %S%T%U has detached ***',
    'detach'     => 'V'    => '*** %S%T%U has been detached %V ***',
    'here'       => 'SU'   => '(you are now here%B)',
    'here'       => 'U'    => '*** %S%T%U is now "here" ***',
    'away'       => 'SU'   => '(you are now away%B)',
    'away'       => 'U'    => '*** %S%T%U is now "away" ***',
    'away'       => 'V'    => '*** %S%T%U has idled "away" ***', # V=idled really.
    'rename'     => 'SV'   => '(you are now named %V)',
    'rename'     => 'V'    => '*** %S%T%u is now named %V ***',
    'blurb'      => 'SE'   => '(your blurb has been turned off)',
    'blurb'      => 'SV'   => '(your blurb has been set to [%V])',
    'blurb'      => 'V'    => '*** %S%T%u has changed their blurb to [%V] ***',
    'blurb'      => 'E'    => '*** %S%T%u has turned their blurb off ***',
    'info'       => 'DSE'  => '(you have cleared the info for %R)',
    'info'       => 'DS'   => '(you have changed the info for %R)',
    'info'       => 'SE'   => '(your info has been cleared)',
    'info'       => 'SU'   => '(your info has been changed)',
# For compatibility with older cores:
    'info'       => 'SV'   => '(your info has been changed)',
    'info'       => 'ED'   => '*** %S%T%u has cleared the info for discussion %R ***',
    'info'       => 'D'    => '*** %S%T%u has changed the info for discussion %R ***',
    'info'       => 'E'    => '*** %S%T%u has cleared their info ***',
    'info'       => 'U'    => '*** %S%T%u has changed their info ***',
# For compatibility with older cores:
    'info'       => 'V'    => '*** %S%T%u has changed their info ***',
    'ignore'     => 'tcE'  => '*** %S%T%u is no longer ignoring you ***',
    'ignore'     => 'A'    => '*** %S%T%u is now ignoring you %V ***',
    'unignore'   => 'A'    => '*** %S%T%u is no longer ignoring you ***',
    'unidle'     => 'A'    => '*** %S%T%u is now unidle ***',
    'create'     => 'DSU'   => '(you have created discussion %R "%D")',
    'create'     => 'U'    => '*** %S%T%u has created discussion %R "%D" ***',
    'destroy'    => 'DSU'   => '(you have destroyed discussion %R)',
    'destroy'    => 'DU'    => '*** %S%T%u has destroyed discussion %R ***',
    'permit'     => 'DSMC="owner";' => '(You have accepted ownership of discussion %R)',
    'permit'     => 'DSTC="owner";' => '(You have offered %P ownership of discussion %R)',
    'permit'     => 'DSTC'  => '(You have given %P %E privileges to discussion %R)',
    'permit'     => 'DMC="owner";'  => '*** %S%T%u has offered you ownership of discussion %R ***',
    'permit'     => 'DMC'   => '*** %S%T%u has given you %E privileges to discussion %R ***',
    'permit'     => 'DTC="owner";'  => '*** %S%T%u has taken ownership of discussion %R ***',
    'permit'     => 'DTC'   => '*** %S%T%u has given %P %E privileges to discussion %R ***',
    'permit'     => 'DMc'   => '*** %S%T%u has permitted you to discussion %R ***',
    'permit'     => 'DTc'   => '*** %S%T%u has permitted %P to discussion %R ***',
    'permit'     => 'DSUtc'  => '(%R is now public)',
    'permit'     => 'DUtc'   => '*** %S%T%u has made discussion %R public ***',
    'permit'     => 'SDtC'  => '(%R is no longer moderated)',
    'permit'     => 'DtC'   => '*** %S%T%u has unmoderated discussion %R ***',
    'depermit'   => 'DSTC="owner";'  => '(You have rescinded your offer to %P for ownership of discussion %R)',
    'depermit'   => 'DSTC'  => '(You have removed %P\'s %E privileges on discussion %R)',
    'depermit'   => 'DMC="owner";' => '*** %S%T%u has rescinded their ownership offer of discussion %R ***',
    'depermit'   => 'DMC'   => '*** %S%T%u has removed your %E privileges on discussion %R ***',
    'depermit'   => 'DTC'   => '*** %S%T%u has removed %P\'s %E privileges on discussion %R ***',
    'depermit'   => 'DMc'   => '*** %S%T%u has depermitted you from discussion %R ***',
    'depermit'   => 'DTc'   => '*** %S%T%u has depermitted %P from discussion %R ***',
    'depermit'   => 'DSUtc'  => '(%R is now private)',
    'depermit'   => 'DUtc'   => '*** %S%T%u has made discussion %R private ***',
    'depermit'   => 'DStC'  => '(%R is now moderated)',
    'depermit'   => 'DtC'   => '*** %S%T%u has moderated discussion %R ***',
    'depermit'   => 'DV'    => '*** %S%T%O is now depermitted from %R ***',
    'join'       => 'DSU'   => '(you have joined %R)',
    'join'       => 'DU'    => '*** %S%T%u is now a member of %R ***',
    'quit'       => 'DSU'   => '(you have quit %R)',
    'quit'       => 'DU'    => '*** %S%T%u is no longer a member of %R ***',
    'retitle'    => 'DSV'   => '(you have changed the title of %R to "%V")',
    'retitle'    => 'DV'    => '*** %S%T%u has changed the title of %R to "%V" ***',
    'sysmsg'     => 'V'    => '%S%V',
    'pa'         => 'V'    => '** %S%TPublic address message from %U: %V **'
    # need to handle review, sysalert, pa, game, and consult.
);

my $sub = sub {
    my ($e, $h) = @_;
    my $serv = $e->{server};
    return unless ($serv);
    
    # optimization?
    return unless ($e->{NOTIFY});

    my $Me =  $serv->user_name;
    
    my $i = 0;
    my $found;
    while ($i < $#infomsg) {
	my $type  = $infomsg[$i++];
	my $flags = $infomsg[$i++];
	my $msg   = $infomsg[$i++];
        my %flags = ();
	
	next unless ($type eq $e->{type});

        while ($flags =~ /\G([AEVUDSMTtCc])(?:="([^"]+)";)?/g) {
            $flags{$1} = $2;
        }

	if (exists $flags{A}) {
	    $found = $msg; last;
	}

	if (exists $flags{S}) {
            next if ($e->{'SOURCE'} ne $Me);
	}

	if (exists $flags{M}) {
            my $targMe = 0;
            # FOO: Huh?
            for ($e->{'TARGETS'}) { $targMe = 1 if ($e->{'TARGETS'} eq $Me) };
            next unless $targMe;
	} elsif (exists $flags{T}) {
            next unless (defined($e->{TARGETS}));
	} elsif (exists $flags{t}) {
            next unless (!defined($e->{TARGETS}));
        }

        if (exists $flags{C}) {
            next if (!defined($e->{'SUBEVT'}) ||
                    (defined($flags{C}) && ($flags{C} ne $e->{'SUBEVT'})));
        } elsif (exists $flags{c}) {
            next unless (!defined($e->{SUBEVT}));
        }

        if (exists $flags{V}) {
            next unless (defined ($e->{VALUE}));
        } elsif (exists $flags{E}) {
            next unless (defined($e->{EMPTY}));
        } elsif (exists $flags{U}) {
            next if (defined($e->{VALUE}));
        }

        if (exists $flags{D}) {
            next unless (defined($e->{RECIPS}));
        }
	$found = $msg;
	last;
    }
    
    if ($found) {
        my $servname = $serv->name();
	my $source = $e->{SOURCE};
	$found =~ s/\%u/$source/g;
	my $blurb = $serv->get_blurb(HANDLE => $e->{SHANDLE});
	$source .= " [$blurb]" if (defined ($blurb) && ($blurb ne ""));
	$found =~ s/\%U/$source/g;
        my $ss = (scalar(TLily::Server::find()) > 1) ? "($servname) ": '';
	$found =~ s/\%S/$ss/g;
	$found =~ s/\%V/$e->{VALUE}/g;
	$found =~ s/\%R/$e->{RECIPS}/g;
	$found =~ s/\%E/$e->{SUBEVT}/g;
	$found =~ s/\%P/$e->{TARGETS}/g;
	my $ts = ($e->{STAMP}) ? timestamp($e->{TIME}) : '';
	$found =~ s/\%T/$ts/g;
	if ($found =~ m/\%O/) {
	    my $target = $serv->get_name(HANDLE => $e->{VALUE});
	    $found =~ s/\%O/$target/g;
	}
	if ($found =~ m/\%D/) {
	    my $title = $serv->get_title(NAME => $e->{RECIPS});
	    $found =~ s/\%D/$title/g;
	}
	if ($found =~ m/\%B/) {
	    if (defined ($blurb) && ($blurb ne "")) {
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

sub etimestamp {
    my ($time) = @_;
    
    my ($min, $hour) = (localtime($time))[1,2];
    my $t = ($hour * 60) + $min;
    my $ampm = '';
    $t += $config{zonedelta} if defined($config{zonedelta});
    $t += (60 * 24) if ($t < 0);
    $t -= (60 * 24) if ($t >= (60 * 24));
    $hour = int($t / 60);
    $min  = $t % 60;
    if (defined($config{zonetype}) and ($config{zonetype} eq '12')) {
	if ($hour >= 12) {
	    $ampm = 'p';
	    $hour -= 12 if $hour > 12;
	} else {
	    $ampm = 'a';
		}
	}
	return sprintf("%02d:%02d%s - ", $hour, $min, $ampm);
}

sub timestamp {
    my ($time) = @_;
    
    my ($min, $hour) = (localtime($time))[1,2];
    my $t = ($hour * 60) + $min;
    my $ampm = '';
    $t += $config{zonedelta} if defined($config{zonedelta});
    $t += (60 * 24) if ($t < 0);
    $t -= (60 * 24) if ($t >= (60 * 24));
    $hour = int($t / 60);
    $min  = $t % 60;
    if (defined($config{zonetype}) and ($config{zonetype} eq '12')) {
	if ($hour >= 12) {
	    $ampm = 'p';
	    $hour -= 12 if $hour > 12;
	} else {
	    $ampm = 'a';
		}
	}
	return sprintf("(%02d:%02d%s) ", $hour, $min, $ampm);
}
