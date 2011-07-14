package CJ::command::help;
use strict;

use Symbol 'qualify_to_ref';

our $TYPE     = "all";
our $POSITION = -2;
our $LAST     = 1;
our $RE       = qr/\bhelp(?:\s+(\w+))?\s*$/i;

#find any "help" subs present in command modules.
our %help;

sub load {
    foreach my $ns ( keys %CJ::command:: ) {
        my $help = *{ qualify_to_ref( $CJ::command::{$ns} ) }{HASH}{help};
        if ( defined($help) ) {
            ( my $command = $ns ) =~ s/:://;
            $help{$command} = $help;
        }
    }
}

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $args = $1;
    if ( $args eq q{} ) {

        return
            "Hello. I'm a bot. Try 'help' followed by one of the following for more information: "
            . join( ', ', sort keys %help )
            . '. In general, commands can appear anywhere in private sends, but must begin public sends.';
    }
    if ( exists $help{$args} ) {
        my $helper = $help{$args};
        my $type
            = ' [' . join( ',', CJ::get_types( $CJ::response{$args} ) ) . ']';
        my $help = $helper->();
        return join( ' ', ( split /\n/, $help . $type ) );
    }
    return "There is no help for '$args'";
}

sub help {
    return "You're kidding, right?";
}

1;
