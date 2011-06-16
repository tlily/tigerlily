package CJ::command::eliza;
use strict;

use Chatbot::Eliza;

our $TYPE     = "all";
our $POSITION = 2;
our $LAST     = 1;
our $RE       = qr/.*/;

# we'll use Eliza to handle any commands we don't understand, so set her up.
our $eliza = new Chatbot::Eliza { name => $CJ::name, prompts_on => 0 };

sub response {
    my ($event) = @_;
    return $eliza->transform( $event->{VALUE} );
}

sub help {
    return <<"END_HELP"
I've been doing some research into psychotherapy,
I'd be glad to help you work through your agression.
END_HELP
}

1;
