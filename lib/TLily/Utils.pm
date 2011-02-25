# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2005  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.

package TLily::Utils;

use strict;
use Exporter;
use TLily::Config;

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);

@EXPORT_OK = qw(&max &min &edit_text &diff_text &columnize_list &save_deadfile &get_deadfile &initials_match &parse_interval);

# These are handy in a couple of places.
sub max { return ($_[0] > $_[1]) ? $_[0] : $_[1] }
sub min { return ($_[0] < $_[1]) ? $_[0] : $_[1] }

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

    my $tmpfile = "$::TL_TMPDIR/tlily.$$";
    my $mtime = 0;

    unlink($tmpfile);
    open my $fh, '>', $tmpfile  or die "Can't write $tmpfile: $!";
    if (@{$text}) {
        foreach (@{$text}) {
            chomp;
            if ($^O =~ /cygwin/) {
            print $fh "$_\r\n";
        } else {
            print $fh "$_\n";
        }
    }
        $mtime = (stat $fh)[10];
    }
    close $fh;

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

    unless (open $fh, '<', $tmpfile) {
        $ui->print("(edit buffer file not found)\n") unless $quiet;
        return;
    }

    if ($^O =~ /cygwin/) {
    # blah!
    } elsif ((stat $fh)[10] == $mtime) {
        close $fh;
        unlink($tmpfile);
        $ui->print("(file unchanged)\n") unless $quiet;
        return;
    }

    @{$text} = <$fh>;
    if ($^O =~ /cygwin/) {
        local $/ = "\r\n";
        chomp(@{$text});
    } else {
    chomp(@{$text});
    }
    close $fh;
    unlink($tmpfile);

    return 1;

}

sub diff_text {
  my ( $a, $b ) = @_;
  my $fh;
  my $diff = [];

  # TODO: error-check these open() statements.   SDN 02/25/2011

  my $tmpfile_a = "$::TL_TMPDIR/tlily-diff-a.$$";
  my $tmpfile_b = "$::TL_TMPDIR/tlily-diff-b.$$";
  open $fh, '>', $tmpfile_a;
  foreach (@{$a}) { print $fh "$_\n" };
  close $fh;

  open $fh, '>', $tmpfile_b;
  foreach (@{$b}) { print $fh "$_\n" };
  close $fh;

  open $fh, '-|', "diff $tmpfile_a $tmpfile_b";
  @{$diff} = <$fh>;
  close $fh;

  unlink $tmpfile_a;
  unlink $tmpfile_b;

  return $diff;

}

sub save_deadfile {
    my($type, $server, $name, $text) = @_;

    my $escaped_name = $server->name() . "::$name";
    $escaped_name =~ s|/|,|g;

    my $deaddir = $ENV{HOME}."/.lily/tlily";
    if (! -d $deaddir) {
        # use the default explicitly for older perls. -Coke
        mkdir $deaddir, 0777 or return;
    }
    my $deadfile = $deaddir . "/dead.$type.$escaped_name";

    unlink($deadfile);

    open my $df, '>', $deadfile  or return;

    foreach my $l (@{$text}) {
        print $df $l, "\n";
    }
    close $df;

    return 1;
}

sub get_deadfile {
    my($type, $server, $name) = @_;

    my $escaped_name = $server->name() . "::$name";
    $escaped_name =~ s|/|,|g;
    my $deadfile = $ENV{HOME}."/.lily/tlily/dead.$type.$escaped_name";

    open my $df, '<', $deadfile  or return;

    my $text;
    @{$text} = <$df>;
    close $df;
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

# does the full name given match the initials given?
# examples: does "NeuroVic" match "nv" ?

sub initials_match {
    my $partial = shift;
    my $full    = shift;

    # what are considered the initials of a full name? initial character,
    # and then any letters that are capitalized, or appear after a nonalpha
    # character.

    my @chars = $full =~ m{(^.|[A-Z]|(?<=[^A-Za-z\d])[A-Za-z])}g;
    my $guess = join('',@chars);

    return lc $guess eq lc $partial;
}

=head2 parse_interval

Given a simple string like "5m", return # of seconds.

=cut

sub parse_interval {
    my($s) = @_;

    if($s =~ m/^(\d+)s?$/) {
        return $1;
    }
    elsif($s =~ m/^(\d+)m$/) {
        return $1 * 60;
    }
    elsif($s =~ m/^(\d+)h$/) {
        return $1 * 3600;
    }
    elsif($s =~ m/^(\d+)d$/) {
        return $1 * 86400 ;
    }
    else {
        return;
    }
}

1;
