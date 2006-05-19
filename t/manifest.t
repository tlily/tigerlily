#! perl

use strict;
use warnings;
use Test::More tests => 4;

use File::Spec qw(devnull);
use ExtUtils::Manifest;

=head1 NAME

t/manifest.t - sanity check the MANIFEST file

=head1 TODO

Add the reverse test, to make sure files that are checked into svn
are in the MANIFEST: skip this if this isn't an svn sandbox.

=cut

ok(-e $ExtUtils::Manifest::MANIFEST, 'MANIFEST exists');

ok(-e $ExtUtils::Manifest::MANIFEST . '.SKIP', 'MANIFEST.SKIP exists');

$ExtUtils::Manifest::Quiet = 1;

my @missing = ExtUtils::Manifest::manicheck();
ok(!@missing, 'manicheck()')
  or diag("Files in manifest, not on disk:\n\t" . join ("\n\t", @missing), "\n");

my @extra = ExtUtils::Manifest::filecheck();
ok(!@extra, 'filecheck()')
  or diag("Files missing from MANIFEST:\n\t" . join ("\n\t", @extra), "\n");
