# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Utils.pm,v 1.12 2003/02/28 02:24:23 josh Exp $
package TLily::Utils;

use strict;
use Exporter;
use TLily::Config;

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);

@EXPORT_OK = qw(&max &min &edit_text &diff_text &columnize_list &save_deadfile &get_deadfile);

# These are handy in a couple of places.
sub max($$) { ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min($$) { ($_[0] < $_[1]) ? $_[0] : $_[1] }

sub columnize_list {
    my ($ui, $list, $limit) = @_;

    my $outlist = [];
    my $ui_cols = 79;
    my $clen = 0;

    # Need to implement some feedback here to adjust the column width
    # more appropriately.
    foreach (@{$list}) { $clen = max($clen, length $_); }
    $clen += 2;

    my $cols = int($ui_cols / $clen);
    my $rows = int(@{$list} / $cols);
    $rows++ if (@{$list} % $cols);

    my $out_rows = (defined($limit) && $limit < $rows)?$limit:$rows;
    for (my $i = 0; ($i < $out_rows); $i++) {
        push @{$outlist},
          sprintf("%-${clen}s" x $cols, map {$list->[$i+$rows*$_]} 0..$cols);
    }

    if ($out_rows < $rows) {
        push @{$outlist},
          "(" . (@{$list} - ($out_rows * $cols)) . " more entries follow)\n";
    }

    return $outlist;
}

sub edit_text {
    my($ui, $text, $quiet) = @_;

    local(*FH);
    my $tmpfile = "$::TL_TMPDIR/tlily.$$";
    my $mtime = 0;

    unlink($tmpfile);
    open(FH, ">$tmpfile") or die "$tmpfile: $!";
    if (@{$text}) {
        foreach (@{$text}) { 
	    chomp; 
            if ($^O =~ /cygwin/) {	    
	        print FH "$_\r\n";
	    } else {
	        print FH "$_\n";	    
	    }
	}
        $mtime = (stat FH)[10];
    }
    close FH;

    $ui->suspend;
    TLily::Event::keepalive();
    
    if ($^O =~ /cygwin/) {
         my $tmpfile2 = "C:$tmpfile";
        $tmpfile2 =~ s/\//\\/g;
        system($config{editor}, $tmpfile2);
        TLily::Event::keepalive(60);
    } else {
        system($config{editor}, $tmpfile);
        TLily::Event::keepalive(5);
    }

    $ui->resume;

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
        $ui->print("(edit buffer file not found)\n") unless $quiet;
        return;
    }  
     
    if ($^O =~ /cygwin/) {
	# blah!
    } elsif ((stat FH)[10] == $mtime) {
        close FH;
        unlink($tmpfile);
        $ui->print("(file unchanged)\n") unless $quiet;
        return;
    }  
    
    @{$text} = <FH>;
    if ($^O =~ /cygwin/) {
        local($/ = "\r\n");
    	chomp(@{$text});
    } else {
	chomp(@{$text});
    }
    close FH;
    unlink($tmpfile);

    return 1;

}

sub diff_text {
  my ( $a, $b ) = @_;
  local(*FH);
  my $diff = [];

  my $tmpfile_a = "$::TL_TMPDIR/tlily-diff-a.$$";
  my $tmpfile_b = "$::TL_TMPDIR/tlily-diff-b.$$";
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

sub save_deadfile {
    my($type, $server, $name, $text) = @_;

    my $escaped_name = $server->name() . "::$name";
    $escaped_name =~ s|/|,|g;
    my $deadfile = $ENV{HOME}."/.lily/tlily/dead.$type.$escaped_name";
    unlink($deadfile);

    local *DF;
    open(DF, ">$deadfile") || return undef;

    foreach my $l (@{$text}) {
        print DF $l, "\n";
    }
    close DF;

    return 1;
}

sub get_deadfile {
    my($type, $server, $name) = @_;

    my $escaped_name = $server->name() . "::$name";
    $escaped_name =~ s|/|,|g;
    my $deadfile = $ENV{HOME}."/.lily/tlily/dead.$type.$escaped_name";

    local *DF;
    open(DF, "$deadfile") || return undef;

    my $text;
    @{$text} = <DF>;
    close DF;
    unlink($deadfile);

    return $text;
}

sub format_time {
  my ($time, %args) = @_;

  my $delta = $args{delta};
  my $type = $args{type};
  my $seconds = $args{seconds};

  if ($delta && $config{$delta}) { 
    my($t) = ($time->[2] * 60) + $time->[1] + $config{$delta};
    $t += (60 * 24) if ($t < 0);
    $t -= (60 * 24) if ($t >= (60 * 24));
    $time->[2] = int($t / 60);
    $time->[1] = $t % 60;
  }

  my ($ampm, $format, $secs);
  if ($type && $config{$type} eq '12') {
    if ($time->[2] >= 12) {
      $ampm = 'p';
      $time->[2] -= 12 if $time->[2] > 12;
    }
    elsif ($time->[2] < 12) {
      $time->[2] = 12 if $time->[2] == 0;
      $ampm = 'a';
    }
    $format = "%d:%02d%s%s";
  } else {
    $ampm = '';
    $format = "%02d:%02d%s%s";
  }

  if ($seconds && $config{$seconds}) {
    $secs = sprintf(":%02d", $time->[0]);
  } else {
    $secs = '';
  }

  return sprintf($format, $time->[2], $time->[1], $secs, $ampm);
}

1;
