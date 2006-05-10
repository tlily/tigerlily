#! perl

use strict;
use warnings;
use Test::More;

use ExtUtils::Manifest qw(maniread);

=head1 NAME

t/pod.t - sanity check any pod in the distribution.

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

my @docs;

foreach my $file (keys(%$manifest)) {
    # skip missing files 
    next unless -e $file;
    # skip binary files
    next if -B $file;
    push @docs, $file if Pod::Find::contains_pod($file, 0);
}

plan tests => scalar @docs;
Test::Pod::pod_file_ok( $_ ) foreach @docs;

