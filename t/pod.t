#! perl

use strict;
use warnings;
use Test::More;

use ExtUtils::Manifest qw(maniread);

=head1 NAME

t/pod.t - sanity check any pod in the distribution. Enforce pod in modules/extensions

=head1 BUGS

The test to verify POD exists is extremely basic, and doesn't care what kind
of POD is present.

=cut

BEGIN {
    eval 'use Pod::Find';
    if ($@) {
        print "1..1\nok 1 # skip Pod::Find not installed\n";
        exit;
    }
    eval 'use Test::Pod';
    if ($@) {
        print "1..1\nok 1 # skip Test::Pod not installed\n";
        exit;
    }
}

my $manifest     = maniread('MANIFEST');

my (@docs, @missing);

foreach my $file (keys(%$manifest)) {
    # skip missing files
    next unless -e $file;
    # skip binary files
    next if -B $file;
    if (Pod::Find::contains_pod($file, 0)) {
      push @docs, $file;
    }
    else {
      if ($file =~ m/.p[ml]$/i) {
        push @missing, $file;
      }
    }
}

plan tests => scalar @docs + 1;
Test::Pod::pod_file_ok( $_ ) foreach @docs;

ok(!@missing, "All .pm and .pl files in the distro should have pod")
  or diag ("Files missing required POD:\n\t" . join ("\n\t", @missing), "\n");
