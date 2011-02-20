#! perl

use strict;
use warnings;
use Test::More;

use ExtUtils::Manifest qw(maniread);

=head1 NAME

t/perlcritic.t - sanity check various coding standards in the source.

=head1 BUGS

Should use perltidy to require indents of 4 spaces.

=cut

BEGIN {
    eval 'use Perl::Critic';
    if ($@) {
        print "1..1\nok 1 # skip Perl::Critic not installed\n";
        exit;
    }
}

my @files;

if (!@ARGV) {

    my $manifest = maniread('MANIFEST');

    foreach my $file (sort keys(%$manifest)) {
        next unless $file =~ /\.(?:pm|pl|t)$/;
        push @files, $file;
    }
} else {
    @files = @ARGV;
}
plan tests => scalar @files;

# By default, don't complain about anything. Most of tigerlily doesn't
# need full PBP compliance.
my $jay_sherman = Perl::Critic->new(-exclude => [qr/.*/]);

# Add in the few cases we should care about.
# For a list of available policies, perldoc Perl::Critic
my @policies = qw{
    CodeLayout::ProhibitTrailingWhitespace
};

# XXX These policies were desired at one point, but don't currently pass.
my @failing_policies = qw{
    InputOutput::ProhibitBarewordFileHandles
    InputOutput::ProhibitTwoArgOpen
    NamingConventions::ProhibitAmbiguousNames
    Subroutines::ProhibitBuiltinHomonyms
    Subroutines::ProhibitExplicitReturnUndef
    Subroutines::ProhibitSubroutinePrototypes
    Subroutines::RequireFinalReturn
    TestingAndDebugging::RequireUseStrict
    TestingAndDebugging::RequireUseWarnings
    Variables::ProhibitConditionalDeclarations
};

foreach my $policy (@policies) {
  $jay_sherman->add_policy(-policy => $policy);
}

# Do this one manually - requires an option.
$jay_sherman->add_policy(
    -policy => 'CodeLayout::ProhibitHardTabs',
    -config => { allow_leading_tabs => 0 }
);

foreach my $file (@files) {
    my @violations = $jay_sherman->critique($file);
    my $output = join("\n", @violations);
    # Remove the PBP references to avoid being preachy.
    $output =~ s/See page.*//g;
    is ($output, '', $file);
}
