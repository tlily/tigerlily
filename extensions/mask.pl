# -*- Perl -*-

use strict;

# Author: Will "Coke" Coleda (will@coleda.com)

#
# mask certain users as groups.
#

shelp_r('mask', "Mask user a as group b");
shelp_r('mask_full', "If true, fully %mask users.", "variables");
help_r('mask', "Takes advantage of groups with a single user in them, e.g.:

/group new coke Will

Sends from Will are now rewritten, ala:

 -> (10:02) From Will (coke) [Mr. Bartender], to tigerlily:
 -  mask.pl has been checked in.

This allows you to easily track users who change their psuedos, or create
a group that describes a particular user. For example:

 -> (10:02) From damien (japanese expert) [\@work], to tigerlily:
 -  Nifty.

If the config variable 'mask_full' is true, then the send above will instead
appear as:

 -> (10:02) From japanese expert [\@work], to tigerlily:
 -  Nifty.
");

sub load {
    # XXX If you're ambitious, add more event types.
    foreach my $type (qw/private public emote blurb/) {
        event_r(type  => $type,
                order => 'before',
                call  => \&masker);
     }
     exists ($config{mask_full}) or $config{mask_full} = 0;
}

sub masker {
  my($event, $handler) = @_;

  my $server = $event->{server};

  my %mask;
  foreach my $name (keys %{$server->{NAME}}) {
    if (defined($server->{NAME}->{$name}->{MEMBERS})) {
      my @members = (split(',',$server->{NAME}->{$name}->{MEMBERS}));
      next unless @members == 1;
      $mask{$members[0]} = $server->{NAME}->{$name}->{NAME};
    }
  }

  # XXX Just mucking with sender for now.
  # If you're ambitious, do this for recipients as well.

  if (exists($mask{$event->{SHANDLE}})) {
    my $old_source = $event->{SOURCE};
    my $repl;
    if ($config{mask_full}) {
      $repl = $mask{$event->{SHANDLE}};
    } else {
      $repl = $event->{SOURCE} . " (" . $mask{$event->{SHANDLE}} .")";
    }
    $event->{SOURCE} = $repl;
    if ($event->{type} eq 'blurb') {
       $event->{text} =~ s/$old_source/$repl/;
    }
  }

  return;
}

#TRUE! They return TRUE!
1;
