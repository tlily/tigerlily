package CJ::command::ping;
use strict;

use Data::Dumper;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bping\b/i;

sub response {
    my $a = CJ::cleanHTML( Dumper( \%CJ::served ) );
    $a =~ s/\$VAR1 =/ number of commands and messages processed: /;
    return 'pong. uptime: ' . CJ::humanTime( time() - $CJ::uptime ) . "; $a";
}

sub help {
    return "Yes, I'm alive. And have some stats while you're at it.";
}

1;
