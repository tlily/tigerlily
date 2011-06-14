package CJ::command::ascii;
use strict;

our $TYPE     = "all";
our $POSITION = 0;
our $LAST     = 1;
our $RE       = qr/\bascii\b/i;

my @ascii
    = qw/NUL SOH STX ETX EOT ENQ ACK BEL BS HT LF VT FF CR SO SI DLE DC1 DC2 DC3 DC4 NAK SYN ETB CAN EM SUB ESC FS GS RS US SPACE/;
my %ascii;

for my $cnt ( 0 .. $#ascii ) {
    $ascii{ $ascii[$cnt] } = $cnt;
}
$ascii{DEL} = 0x7f;

sub _format_ascii {
    my $val = @_[0];

    my $format = '%s => %d (dec); 0x%x (hex); 0%o (oct)';

    if ( $val < 0 || $val > 255 ) {
        return 'Ascii is 7 bit, silly!';
    }
    my $chr = "'" . chr($val) . "'";

    my $control;
    if ( $val >= 1 && $val <= 26 ) {
        $control = '; control-' . chr( $val + ord('A') - 1 );
    }

    if ( $val < $#ascii ) {
        $chr = $ascii[$val];
    }

    if ( $val == 0x7f ) {
        $chr = 'DEL';
    }

    return sprintf( $format, $chr, $val, $val, $val ) . $control;
}

sub response {
    my ($event) = @_;
    my $args = $event->{VALUE};
    if ( !( $args =~ s/.*ascii\s+(.*)/$1/i ) ) {
        return 'ERROR: Expected ascii RE not matched!';
    }
    if ( $args =~ m/^'(.)'$/ ) {
        return _format_ascii( ord($1) );
    }
    elsif ( $args =~ m/^0[Xx][0-9A-Fa-f]+$/ ) {
        return _format_ascii( oct($args) );
    }
    elsif ( $args =~ m/^0[0-7]+$/ ) {
        return _format_ascii( oct($args) );
    }
    elsif ( $args =~ m/^[1-9]\d*$/ ) {
        return _format_ascii($args);
    }
    elsif ( $args =~ m/^\\[Cc]([A-Z])$/ ) {
        return _format_ascii( ord($1) - ord('A') + 1 );
    }
    elsif ( $args =~ m/^\\[Cc]([a-z])$/ ) {
        return _format_ascii( ord($1) - ord('a') + 1 );
    }
    elsif ( $args =~ m/^[Cc]-([a-z])$/ ) {
        return _format_ascii( ord($1) - ord('a') + 1 );
    }
    elsif ( $args =~ m/^[Cc]-([A-Z])$/ ) {
        return _format_ascii( ord($1) - ord('A') + 1 );
    }
    elsif ( exists $ascii{ uc $args } ) {
        return _format_ascii( $ascii{ uc $args } );
    }
    else {
        return "Sorry, $args doesn't make any sense to me.";
    }
}

sub help {
    return <<'END_HELP',
Usage: ascii <val>, where val can be a char ('a'), hex (0x1), octal (01),
decimal (1) an emacs (C-A) or perl (\cA) control sequence, or an ASCII
control name (SOH)
END_HELP
}
1;
