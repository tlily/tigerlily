# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/mask.pl,v 1.1 2003/07/11 00:23:39 coke Exp $

use strict;

# Author: Will "Coke" Coleda (will@coleda.com)

#
# mask certain users as groups.
#

command_r('mask', \&mask_cmd);
shelp_r('mask', "mask user a as group b");
help_r('mask', "mask user a as group b");

sub load {
    # XXX If you're ambitious, add more event types.
    foreach my $type (qw/private public emote/) {
        event_r(type  => $type,
                order => 'before',
                call  => \&masker);
     }
}

sub masker {
  my($event, $handler) = @_;

  my $server = $event->{server};

  my %mask;
  foreach my $name (keys %{$server->{NAME}}) {
    if (defined($server->{NAME}->{$name}->{MEMBERS})) {
      my @members = (split(',',$server->{NAME}->{$name}->{MEMBERS}));
      next unless @members == 1;
      $mask{$members[0]} = $name;
    }
  }

  # XXX Just mucking with sender for now.
  # If you're ambitious, do this for recipients as well.

  if (exists($mask{$event->{SHANDLE}})) {
    $event->{SOURCE} = $event->{SOURCE} . " (" . $mask{$event->{SHANDLE}} .")";
  }
  return;
}

#TRUE! They return TRUE!
1;
