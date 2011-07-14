package CJ::command::kibo;
use strict;

our $TYPE     = "public emote";
our $POSITION = 1;
our $LAST     = 1;
our $RE       = qr/\b$CJ::name\b.*\?/i,

    # some array refs of sayings...
    my $sayings;    # pithy 8ball-isms.

# Unify this into generic special handling. =-)
my $unified;        # special handling for the unified discussion.
my $beener;         # special handling for the beener discussion.

sub response {
    my ($event) = @_;
    my $list = $sayings;
    if ( $event->{RECIPS} eq 'unified' ) {
        $list = [ (@$unified) x 2, @$list ];
    }
    elsif ( $event->{RECIPS} eq 'beener' ) {
        $list = [ (@$beener) x 2, @$list ];
    }
    my ($message) = sprintf( CJ::pickRandom($list), $event->{SOURCE} );
    return $message;
}

sub help {
    return "I respond to public questions addressed to me.";
    TYPE     => "public emote",
        POS  => 1,
        STOP => 1,
        ;
}

sub load {
    my $server = TLily::Server->active();
    $server->fetch(
        call => sub { my %event = @_; $sayings = $event{text} },
        type => 'memo',
        target => $CJ::disc,
        name   => 'sayings'
    );
    $server->fetch(
        call => sub { my %event = @_; $unified = $event{text} },
        type => 'memo',
        target => $CJ::disc,
        name   => '-unified'
    );
    $server->fetch(
        call => sub { my %event = @_; $beener = $event{text} },
        type => 'memo',
        target => $CJ::disc,
        name   => '-beener'
    );
}

1;
