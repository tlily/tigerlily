# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/slcp_output.pl,v 1.28 2003/09/28 01:15:43 josh Exp $

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
    my $Me =  $e->{server}->user_name();
    my $blurb = $e->{server}->get_blurb(HANDLE => $e->{SHANDLE});

    my $server_fmt = $e->{server_fmt} || "private_server";
    my $header_fmt = $e->{header_fmt} || "private_header";
    my $sender_fmt = $e->{sender_fmt} || "private_sender";
    my $dest_fmt   = $e->{dest_fmt}   || "private_dest";
    my $body_fmt   = $e->{body_fmt}   || "private_body";
    
    $ui->print("\n");
    
    my $servname = "(" . $e->{server}->name() . ") "
      if (scalar(TLily::Server::find()) > 1);

    $ts = timestamp($e->{TIME}) if ($e->{STAMP});
    $ui->indent($header_fmt => " >> ");
    $ui->prints($server_fmt => $servname)
      if (defined $servname);

    $ui->prints($header_fmt => "${ts}Private message");
    unless ($e->{SOURCE} eq $Me) {
      $ui->prints($header_fmt => " from ",
                  $sender_fmt => $e->{SOURCE});
      $ui->prints($header_fmt => " [$blurb]")
        if (defined $blurb && ($blurb ne ""));
    }
    if (($e->{RECIPS} =~ /,/) || ($e->{SOURCE} eq $Me)) {
        $ui->prints($header_fmt => " to ",
                    $dest_fmt   => $e->{RECIPS});
    }
    $ui->prints($header_fmt => ":\n");
    
    $ui->indent($body_fmt => " - ");
    $ui->prints($body_fmt => $e->{VALUE}."\n");
    
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

    my $server_fmt = $e->{server_fmt} || "public_server";
    my $header_fmt = $e->{header_fmt} || "public_header";
    my $sender_fmt = $e->{sender_fmt} || "public_sender";
    my $dest_fmt   = $e->{dest_fmt}   || "public_dest";
    my $body_fmt   = $e->{body_fmt}   || "public_body";
    
    $ui->print("\n");
    
    my $servname = "(" . $e->{server}->name() . ") "
      if (scalar(TLily::Server::find()) > 1);

    $ts = timestamp ($e->{TIME}) if ($e->{STAMP});
    $ui->indent($header_fmt => " -> ");
    $ui->prints($server_fmt => $servname)
      if (defined $servname);
    $ui->prints($header_fmt => "${ts}From ",
                $sender_fmt => $e->{SOURCE});
    $ui->prints($header_fmt => " [$blurb]")
      if (defined $blurb && ($blurb ne ""));
    $ui->prints($header_fmt => ", to ",
                $dest_fmt   => $e->{RECIPS},
                $header_fmt => ":\n");
    
    $ui->indent($body_fmt   => " - ");
    $ui->prints($body_fmt   => $e->{VALUE}."\n");

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

    my $server_fmt = $e->{server_fmt} || "emote_server";
    my $sender_fmt = $e->{sender_fmt} || "emote_sender";
    my $dest_fmt   = $e->{dest_fmt}   || "emote_dest";
    my $body_fmt   = $e->{body_fmt}   || "emote_body";
    
    my $dest = $e->{RECIPS};
    my $servname = "(" . $e->{server}->name() . ") "
      if (scalar(TLily::Server::find()) > 1);


    $ts = etimestamp ($e->{TIME}) if ($e->{STAMP} || $config{'stampemotes'});
    $ui->indent($body_fmt   => "> ");
    $ui->prints($server_fmt => $servname)
      if (defined $servname);
    $ui->prints($body_fmt   => "(${ts}to ",
                $dest_fmt   => $dest,
                $body_fmt   => ") ",
                $sender_fmt => $e->{SOURCE},
                $body_fmt   => $e->{VALUE}."\n");

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
# %v: VALUE, but insert the server name and timestamp as appropriate
#     after the first occurance of '***' or '###'
# %D: title of discussion whose name is in VALUE.
# %R: RECIPS
# %P: TARGETS
# %O: name of thingy whose OID is in VALUE.
# %T: timestamp, if STAMP is defined, empty otherwise.
# %S: '(servername)', if connected to more than one, empty otherwise.
# %B: if SOURCE has a blurb " with the blurb [blurb]", else "".
# %E: SUBEVT
# %p: source's pronoun
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
# L<op>"val"; : where <op> is =, <, >, <=, or >=.  Use this
#   message by matching the lily server version against "val",
#   using <op>.
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
    'blurb'      => 'V'    => '*** %S%T%u has changed %p blurb to [%V] ***',
    'blurb'      => 'E'    => '*** %S%T%u has turned %p blurb off ***',
    'info'       => 'DSE'  => '(you have cleared the info for %R)',
    'info'       => 'DS'   => '(you have changed the info for %R)',
    'info'       => 'SE'   => '(your info has been cleared)',
    'info'       => 'SU'   => '(your info has been changed)',
# For compatibility with older cores:
    'info'       => 'SV'   => '(your info has been changed)',
    'info'       => 'ED'   => '*** %S%T%u has cleared the info for discussion %R ***',
    'info'       => 'D'    => '*** %S%T%u has changed the info for discussion %R ***',
    'info'       => 'E'    => '*** %S%T%u has cleared %p info ***',
    'info'       => 'U'    => '*** %S%T%u has changed %p info ***',
# For compatibility with older cores:
    'info'       => 'V'    => '*** %S%T%u has changed %p info ***',
    'ignore'     => 'tcE'  => '*** %S%T%u is no longer ignoring you ***',
    'ignore'     => 'A'    => '*** %S%T%u is now ignoring you %V ***',
    'unignore'   => 'A'    => '*** %S%T%u is no longer ignoring you ***',
    'unidle'     => 'A'    => '*** %S%T%u is now unidle ***',
    'create'     => 'DSU'  => '(you have created discussion %R "%D")',
    'create'     => 'U'    => '*** %S%T%u has created discussion %R "%D" ***',
    'destroy'    => 'DSU'  => '(you have destroyed discussion %R)',
    'destroy'    => 'DU'   => '*** %S%T%u has destroyed discussion %R ***',
    'destroy'    => 'U'    => '*** %S%T%u has destroyed a discussion (server didn\'t say which) ***',
    'drename'    => 'V'    => '*** %S%TDiscussion -%R is now named -%V ***',
    'permit'     => 'DSMC="owner";' => '(You have accepted ownership of discussion %R)',
    'permit'     => 'DSTC="owner";' => '(You have offered %P ownership of discussion %R)',
    'permit'     => 'DSTC'  => '(You have given %P %E privileges to discussion %R)',
    'permit'     => 'DMC="owner";'  => '*** %S%T%u has offered you ownership of discussion %R ***',
    'permit'     => 'DMC'   => '*** %S%T%u has given you %E privileges to discussion %R ***',
    'permit'     => 'DTC="owner";'  => '*** %S%T%u has taken ownership of discussion %R ***',
    'permit'     => 'DTC'   => '*** %S%T%u has given %P %E privileges to discussion %R ***',
    'permit'     => 'DMc'   => '*** %S%T%u has permitted you to discussion %R ***',
    'permit'     => 'DTc'   => '*** %S%T%u has permitted %P to discussion %R ***',
# The following two messages should only be used on 2.4 or 2.5 cores.
# Earlier cores gave the same notify for [un]appoints as well as a discussion
# going public/private.
    'permit'     => 'DSUtcL>="2.4";'  => '(%R is now public)',
    'permit'     => 'DUtcL>="2.4";'   => '*** %S%T%u has made discussion %R public ***',
    'permit'     => 'SDtC'  => '(%R is no longer moderated)',
    'permit'     => 'DtC'   => '*** %S%T%u has unmoderated discussion %R ***',
# The older style /permit notify
    'permit'     => 'DtcVL<="2.3";'   => '*** %S%T%u has permitted %O to discussion %R ***',
    'permit'     => 'tcVL<="2.3";'   => '*** %S%T%u has permitted you to a discussion (server didn\'t say which) ***',
    'depermit'   => 'DSTC="owner";'  => '(You have rescinded your offer to %P for ownership of discussion %R)',
    'depermit'   => 'DSTC'  => '(You have removed %P\'s %E privileges on discussion %R)',
    'depermit'   => 'DMC="owner";' => '*** %S%T%u has rescinded %p ownership offer of discussion %R ***',
    'depermit'   => 'DMC'   => '*** %S%T%u has removed your %E privileges on discussion %R ***',
    'depermit'   => 'DTC'   => '*** %S%T%u has removed %P\'s %E privileges on discussion %R ***',
    'depermit'   => 'DMc'   => '*** %S%T%u has depermitted you from discussion %R ***',
    'depermit'   => 'DTc'   => '*** %S%T%u has depermitted %P from discussion %R ***',
# The following two messages should only be used on 2.4 or 2.5 cores.
# Earlier cores gave the same notify for [un]appoints as well as a discussion
# going public/private.
    'depermit'   => 'DSUtcL>="2.4";'  => '(%R is now private)',
    'depermit'   => 'DUtcL>="2.4";'   => '*** %S%T%u has made discussion %R private ***',
    'depermit'   => 'DStC'  => '(%R is now moderated)',
    'depermit'   => 'DtC'   => '*** %S%T%u has moderated discussion %R ***',
# The older style /depermit notify
    'depermit'    => 'DtcVL<="2.3";'   => '*** %S%T%u has depermitted %O from discussion %R ***',
    'join'       => 'DSU'   => '(you have joined %R)',
    'join'       => 'DU'    => '*** %S%T%u is now a member of %R ***',
    'quit'       => 'DSU'   => '(you have quit %R)',
    'quit'       => 'DU'    => '*** %S%T%u is no longer a member of %R ***',
    'retitle'    => 'DSV'   => '(you have changed the title of %R to "%V")',
    'retitle'    => 'DV'    => '*** %S%T%u has changed the title of %R to "%V" ***',
    'sysmsg'     => 'V'     => '%v',
    'pa'         => 'V'     => '** %S%TPublic address message from %U: %V **',

    # appoint/unappoint, as of 2.6.4-cr3.
    'appoint'    => 'SMC="owner";' => "(you have accepted ownership of discussion %R)",
    'appoint'    => 'SC="owner";'  => "(you have offered %P ownership of discussion %R)",
    'appoint'    => 'MC="owner";'  => "*** %S%T%u has offered you ownership of discussion %R ***",
    'appoint'    => 'C="owner";'   => "*** %S%T%u is now the owner of discussion %R ***",
    'unappoint'  => 'MC="owner";'  => "*** %S%T%u has rescinded %p offer of ownership of discussion %R ***",
    'unappoint'  => 'SC="owner";'  => "(you have rescinded your ownership offer to %P of discussion %R)",

    'appoint'    => 'tC="speaker";' => "*** Discussion %R is now moderated ***",    
    'appoint'    => 'MC="speaker";' => "*** You have been made a speaker for discussion %R ***",
    'appoint'    => 'C="speaker";'  => "*** %P is now a speaker for discussion %R ***",
    'unappoint'  => 'tC="speaker";' => "*** Discussion %R is no longer moderated ***",
    'unappoint'  => 'MC="speaker";' => "*** You are no longer a speaker for discussion %R ***",
    'unappoint'  => 'C="speaker";'  => "*** %P is no longer a speaker for discussion %R ***",

    'appoint'    => 'MC="author";' => "*** You have been made an author for discussion %R ***",
    'appoint'    => 'C="author";'  => "*** %P is now an author for discussion %R ***",
    'unappoint'  => 'MC="author";' => "*** You are no longer an author for discussion %R ***",
    'unappoint'  => 'C="author";'  => "*** %P is no longer an author for discussion %R ***",

    'appoint'    => 'M'            => "*** You are now a %E for %R ***",
    'appoint'    => ''             => "*** %P is now a %E for %R ***",
    'unappoint'  => 'M'            => "*** You are no longer a %E for %R ***",
    'unappoint'  => ''             => "*** %P is no longer a %E for %R ***",

    'review'     => ''             => '*** %S%T%u has cleared the review for discussion %R ***',

    # need to handle game event type.
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

        while ($flags =~ /\G([AEVUDSMTtCcL])(?:([<>]?=)"([^"]+)";)?/g) {
	    # " <- This doublequote is necessary to resync Emacs font-lock-mode
            if (defined($2) && defined($3)) {
                $flags{$1} = [$2,$3];
            } else {
                $flags{$1} = undef;
            }
        }

        if (exists $flags{A}) {
            $found = $msg; last;
        }

        if (exists $flags{L}) {
            my $version = $serv->state(DATA => 1, NAME => "version");
            my $eval = "'$version' $flags{L}->[0] '$flags{L}->[1]'";
            next unless eval($eval);
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
                    (defined($flags{C}) && ($flags{C}->[1] ne $e->{'SUBEVT'})));
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

        # A hack for sysmsgs
        if ($found =~ s/\%v/$e->{VALUE}/) {
            $found =~ s/^### /### \%S\%T/;
            $found =~ s/^\*\*\* /*** \%S\%T/;
        }
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
        if ($found =~ m/\%p/) {
            my $pronoun = $serv->get_pronoun(HANDLE => $e->{SHANDLE});
            $found =~ s/\%p/$pronoun/g;
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
    
    my @a = localtime($time);
    my $str = TLily::Utils::format_time(\@a, delta => "zonedelta",
					type => "zonetype");
    return sprintf("%s, ", $str);
}

sub timestamp {
    my ($time) = @_;

    my @a = localtime($time);
    my $str = TLily::Utils::format_time(\@a, delta => "zonedelta",
					type => "zonetype");
    return sprintf("(%s) ", $str);
}
