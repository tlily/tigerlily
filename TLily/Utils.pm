# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Utils.pm,v 1.2 1999/10/02 02:45:10 mjr Exp $
package TLily::Utils;

use strict;
use Exporter;
use TLily::Config;

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);

@EXPORT_OK = qw(&edit_text &diff_text &columnize_list);

sub columnize_list() {
    my ($ui, $list, $limit) = @_;

    my $outlist = [];
    my $ui_cols = 79;
    my $clen = 0;
    foreach (@_) { $clen = length $_ if (length $_ > $clen); }
    $clen += 2;

    my $cols = int($ui_cols / $clen);
    my $rows = int(@_ / $cols);
    $rows++ if (@_ % $cols);

    my $out_rows = ($limit < $rows)?$limit:$rows;
    for (my $i = 0; ($i < $out_rows); $i++) {
        push @{$outlist},
          sprintf("%-${clen}s" x $cols, map{$_[$i+$rows*$_]} 0..$cols);
    }

    if ($out_rows < $rows) {
        push @{$outlist},
          "(" . (@{$list} - ($out_rows * $cols)) . " more entries follow)\n";
    }

    return $outlist;
}

sub edit_text {
    my($ui, $text) = @_;

    local(*FH);
    my $tmpfile = "/tmp/tlily.$$";
    my $mtime = 0;

    unlink($tmpfile);
    if (@{$text}) {
        open(FH, ">$tmpfile") or die "$tmpfile: $!";
        foreach (@{$text}) { chomp; print FH "$_\n"; }
        $mtime = (stat FH)[10];
        close FH;
    }

    $ui->suspend;
    TLily::Event::keepalive();
    system($config{editor}, $tmpfile);
    TLily::Event::keepalive(5);
    $ui->resume;

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
        $ui->print("(edit buffer file not found)\n");
        return;
    }  

    if ((stat FH)[10] == $mtime) {
        close FH;
        unlink($tmpfile);
        $ui->print("(file unchanged)\n");
        return;
    }  

    @{$text} = <FH>;
    chomp(@{$text});
    close FH;
    unlink($tmpfile);

    return 1;

}

sub diff_text {
  my ( $a, $b ) = @_;
  local(*FH);
  my $diff = [];

  my $tmpfile_a = "/tmp/tlily-diff-a.$$";
  my $tmpfile_b = "/tmp/tlily-diff-b.$$";
  open FH, ">$tmpfile_a";
  foreach (@{$a}) { print FH "$_\n" };
  close FH;

  open FH, ">$tmpfile_b";
  foreach (@{$b}) { print FH "$_\n" };
  close FH;

  open FH, "diff $tmpfile_a $tmpfile_b |";
  @{$diff} = <FH>;
  close FH;

  unlink $tmpfile_a;
  unlink $tmpfile_b;

  return $diff;

}

1;
