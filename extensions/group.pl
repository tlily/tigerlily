# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/group.pl,v 1.2 2002/05/09 19:47:56 coke Exp $

use strict;

# Author: Will "Coke" Coleda (will@coleda.com)

#
# nicely format group info.
#

#
# TODO : unattached group members show up as object IDs
# Doesn't work in the Tk UI
#

command_r('group', \&group_cmd);
shelp_r('group', "Pretty print group info.");
help_r( 'group',"%group: like /group but prettier.");

sub print_results {
  my ($ui,$msg,%groups) = @_;

  if (keys %groups) {
    $ui->print("Group      Members\n");
    $ui->print("-----      -------\n");

    my $colwidth = 11;
    foreach my $name (sort {lc($a) cmp lc($b)} keys %groups) {
      $ui->print($name . " " x ($colwidth-length($name)));
      $ui->indent(" " x $colwidth);
      my $expand = join (", ",sort {lc($a) cmp lc($b)} keys %{$groups{$name}} );
      $ui->print($expand);
      $ui->indent();
      $ui->print("\n");
    }
  } else {
    $ui->print("($msg)\n");
  }
}

sub group_cmd {
  my ($ui) = shift;
  my ($subcmd,@args)= split(' ',"@_");

  local $config{expand_group} = 1;

  my $server = TLily::Server::active();

  $subcmd ||= "";

  my %groups;
  foreach my $name (keys %{$server->{NAME}}) {
    if (defined($server->{NAME}->{$name}->{MEMBERS})) {
      foreach my $member (split(',',$server->expand_name($name))) {
        $groups{$name}->{lc($member)} = 1;
      }
    }
  }
  
  if ($subcmd eq "") {
    print_results($ui,"you have no groups defined",%groups);
  } elsif ($subcmd eq "find") {
      if (! @args) {
        $ui->print("You must want to find something.\n");
        return;
      }
    my %hits;
    foreach my $name (keys %groups) {
      foreach my $member (keys %{${groups}{$name}}) {
        foreach my $match (@args) {
          lc($match);
          if ($member =~ /$match/) {
           $hits{$name}{$member} = 1;
          }
        }
      }
    }

    print_results($ui,"no matches found", %hits);
  }
}

#TRUE! They return TRUE!
1;
