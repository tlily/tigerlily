package CJ::command::help;
use strict;

our $TYPE     = "all";
our $POSITION = -2;
our $LAST     = 1;
our $RE       = qr/\bhelp(?:\s+(\w+))?\s*$/i;

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;
    my $args = $1;
    if ( $args eq q{} ) {

        # XXX respect PRIVILEGE
        my @cmds = grep { $_ ne 'help' } keys %CJ::response;
        return
            "Hello. I'm a bot. Try 'help' followed by one of the following for more information: "
            . join( ', ', sort @cmds )
            . '. In general, commands can appear anywhere in private sends, but must begin public sends.';
    }
    if ( exists ${CJ::response}{$args} ) {
        my $helper = $CJ::response{$args}{HELP};
        my $type
            = ' [' . join( ',', CJ::get_types( $CJ::response{$args} ) ) . ']';
        my $help = ( ref $helper eq 'CODE' ) ? &$helper() : $helper;
        return join( ' ', ( split /\n/, $help . $type ) );
    }
    return "There is no help for '$args'";
}

sub help {
    return "You're kidding, right?";
}

1;
