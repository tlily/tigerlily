# -*- Perl -*-
# $Id$

use strict;

#
# nicely format group info. -- this is somewhat obsolete with 
#  gad's recent server changes.
#

#
# TODO : unattached group members show up as object IDs
# Doesn't work in the Tk UI
#

command_r('group', \&group_cmd);
shelp_r('group', "Pretty print group info, add more group features.");
help_r( 'group',<<"END_HELP");
%group find <partial> - show all the groups this item is in.
%group move <item> <from> <to> - delete the item from the from group
       and add it to the to group.
END_HELP

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
  return;
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
          if ($member =~ /$match/i) {
           $hits{$name}{$member} = 1;
          }
        }
      }
    }

    print_results($ui,"no matches found", %hits);
  } elsif ($subcmd eq "move") {
    my ($item,$from,$to) = @args;
    TLily::Server->active()->cmd_process("/group $to add $item");
    TLily::Server->active()->cmd_process("/group $from del $item");
  } else {
    print_results($ui,"see %help group");
  }
  return;
} 
#TRUE! They return TRUE!
1;
