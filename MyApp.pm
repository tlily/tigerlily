package MyApp;

use Foundation;
use Foundation::Functions;
use AppKit;
use AppKit::Functions;

use TLily::UI::Cocoa;

@ISA = qw(Exporter);

sub new {
    # Typical Perl constructor
    # See 'perltoot' for details
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
        'wc' => new TLily::UI::Cocoa(@_),
    };
    bless ($self, $class);



    return $self;
}

sub applicationWillFinishLaunching {
    my ($self, $notification) = @_;

    return 1;
}



1;

# The MyWindowController you'd normally expect to find here is actually the UI object:
# TLily::UI::Cocoa
