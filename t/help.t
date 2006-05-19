#! perl

use strict;
use warnings;
use Test::More;

use ExtUtils::Manifest qw(maniread);

=head1 NAME

t/help.t - verify each extension has help.

=head1 BUGS

Simplistic test.

=cut

my $manifest = maniread('MANIFEST');

my @docs;

foreach my $file (keys(%$manifest)) {
    push @docs, $file if $file=~ m{^extensions/}
}

plan tests => scalar @docs;

foreach my $file (@docs) {
  open my $fh, '<', $file;

  my $ok = 0;

  while (my $line = <$fh>) {
     if ($line =~ m/help_r\s*\(/) {
         $ok = 1;
         last;
     }
  }

  ok($ok, $file);
  close($fh);
}
