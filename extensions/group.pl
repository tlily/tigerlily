# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/group.pl,v 1.1 2002/05/09 18:57:53 coke Exp $

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

sub group_cmd {
  local $config{expand_group} = 1;

  my $server = TLily::Server::active();
  my $ui = TLily::UI::name("main");

  my @groups;
  foreach my $name (keys %{$server->{NAME}}) {
    if (defined($server->{NAME}->{$name}->{MEMBERS})) {
      #use Data::Dumper; $ui->print(Dumper($name));
      push @groups, $name;
    }
  }

  if (@groups) {
	$ui->print("Group      Members\n");	
	$ui->print("-----      -------\n");	
  }
  my $colwidth = 11;
  foreach my $name (sort {lc($a) cmp lc($b)}  @groups) {
    $ui->print($name . " " x ($colwidth-length($name)));
    $ui->indent(" " x $colwidth);
    my $expand = join (", ",sort {lc($a) cmp lc($b)} split(',',$server->expand_name($name)));
    $ui->print($expand);
    $ui->indent();
    $ui->print("\n");
  }
}


#TRUE! They return TRUE!
1;
