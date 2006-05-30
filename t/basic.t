#! perl

use strict;
use warnings;

use Test::More tests => 1;

=head1 NAME

t/basic.t - simple sanity checks

=cut

eval 'require 5.6.0;';
ok(!$@, "Tigerlily requires perl 5.6.x");

