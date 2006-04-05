#! perl

use strict;
use warnings;
use Test::More tests => 3;

use ExtUtils::Manifest;

=head1 NAME

t/manifest.t - sanity check the MANIFEST file

=cut

ok(-e $ExtUtils::Manifest::MANIFEST, 'MANIFEST exists');

ok(-e $ExtUtils::Manifest::MANIFEST . '.SKIP', 'MANIFEST.SKIP exists');

SKIP:
{
    diag "this may take a while...";

    $ExtUtils::Manifest::Quiet = 1;

    my @missing = ExtUtils::Manifest::manicheck();
    ok(!@missing, 'manicheck()')
        or diag("Missing files:\n\t" . join ("\n\t", @missing), "\n");
};
