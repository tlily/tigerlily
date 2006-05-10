#! perl

use strict;
use warnings;
use Test::More;

use ExtUtils::Manifest qw(maniread);

=head1 NAME

t/perlcritic.t - sanity check various coding standards in the source.

=cut

BEGIN {
    eval 'use Perl::Critic';
    if ($@) {
        print "1..1\nok 1 # skip Perl::Critic not installed\n";
        exit;
    }
}

my $manifest    = maniread('MANIFEST');

my @files;

foreach my $file (keys(%$manifest)) {
    next unless $file =~ /\.(?:pm|pl|t)$/;
    push @files, $file;
}

plan tests => scalar @files;

# By default, don't complain about anything. Most of tigerlily doesn't
# need full PBP compliance.
my $jay_sherman = Perl::Critic->new(-exclude => [qr/.*/]);

# Add in the few cases we should care about.
# For a list of available policies, perldoc Perl::Critic
$jay_sherman->add_policy(-policy => 'TestingAndDebugging::RequireUseStrict');
$jay_sherman->add_policy(-policy => 'InputOutput::ProhibitTwoArgOpen');
$jay_sherman->add_policy(-policy => 'CodeLayout::ProhibitHardTabs');

foreach my $file (@files) {
    my @violations = $jay_sherman->critique($file);
    my $output = join("\n", @violations);
    # Remove the PBP references to avoid being preachy.
    $output =~ s/See page.*//g;
    is ($output, '', $file);
}
