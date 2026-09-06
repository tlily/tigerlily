package CJ::command::anagram;
use strict;

our $TYPE     = "all";
our $POSITION = -1;
our $LAST     = 1;
our $RE       = qr/
  (?:
  \b anagram \s+ (.*) \s+ with    \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ with    \s+ (.*) |
  \b anagram \s+ (.*) \s+ without \s+ (.*) |
  \b anagram \s+ (.*)
  )
  \s* $
/ix;

# wordsmith.org no longer answers, and a local wordlist is a better answer than
# any remote one: instant, deterministic, and it cannot go down. The tradeoff is
# that this finds single word anagrams, plus two word ones where a "with"
# clause fixes half of it -- where wordsmith searched multi word freely.
#
# No wordlist is shipped. Most systems already have one; Debian and Ubuntu need
# "apt install wamerican".

our @wordlist_paths = qw(
    /usr/share/dict/words
    /usr/dict/words
    /usr/share/dict/american-english
);

# Set this in your config to use a particular wordlist.
our $wordlist;

# Signature (sorted letters) => [words], built once on first use.
my %index;
my $indexed = 0;

=head2 find_wordlist()

The wordlist to use, or undef if there is none to be found.

=cut

sub find_wordlist {
    return $wordlist if ( $wordlist && -f $wordlist );
    foreach my $path (@wordlist_paths) {
        return $path if -f $path;
    }
    return undef;
}

=head2 signature($word)

A word's letters in sorted order. Two words are anagrams when these match.

=cut

sub signature {
    my ($word) = @_;
    $word = lc $word;
    $word =~ s/[^a-z]//g;
    return join '', sort split //, $word;
}

=head2 build_index()

Group the wordlist by signature, so a lookup is a single hash hit. Done once;
returns false if there is no wordlist.

=cut

sub build_index {
    return 1 if $indexed;

    my $path = find_wordlist();
    return 0 unless $path;

    open my $fh, '<', $path or return 0;
    while ( my $word = <$fh> ) {
        chomp $word;
        $word = lc $word;
        next unless ( length($word) >= 2 && $word =~ /^[a-z]+$/ );
        my $sig = signature($word);
        push @{ $index{$sig} }, $word
            unless grep { $_ eq $word } @{ $index{$sig} || [] };
    }
    close $fh;

    $indexed = 1;
    return 1;
}

=head2 subtract($letters, $taken)

Remove one set of letters from another, or undef if they do not fit.

=cut

sub subtract {
    my ( $letters, $taken ) = @_;

    my @remaining = split //, $letters;
    foreach my $c ( split //, $taken ) {
        my $at = -1;
        for my $i ( 0 .. $#remaining ) {
            if ( $remaining[$i] eq $c ) { $at = $i; last; }
        }
        return undef if $at < 0;
        splice @remaining, $at, 1;
    }
    return join '', sort @remaining;
}

=head2 solve($term, $include, $exclude)

Every anagram of $term found in the wordlist. With $include, that word is held
fixed and the rest of the letters are anagrammed around it. $exclude drops any
result containing it.

=cut

sub solve {
    my ( $term, $include, $exclude ) = @_;

    return () unless build_index();

    my $letters = signature($term);
    return () unless length $letters;

    my @found;
    if ($include) {
        my $rest = subtract( $letters, signature($include) );
        return () unless defined $rest;
        @found = map {"\L$include\E $_"} @{ $index{$rest} || [] };
    }
    else {
        @found = grep { $_ ne lc $term } @{ $index{$letters} || [] };
    }

    if ($exclude) {
        my $unwanted = lc $exclude;
        @found = grep { index( $_, $unwanted ) < 0 } @found;
    }

    return sort @found;
}

sub response {
    my ($event) = @_;
    $event->{VALUE} =~ $RE;

    my ( $term, $include, $exclude );

    if ($1) {
        ( $term, $include, $exclude ) = ( $1, $2, $3 );
    }
    elsif ($4) {
        ( $term, $exclude, $include ) = ( $4, $5, $6 );
    }
    elsif ($7) {
        ( $term, $include ) = ( $7, $8 );
    }
    elsif ($9) {
        ( $term, $exclude ) = ( $9, $10 );
    }
    else {
        ($term) = ($11);
    }

    if ( !find_wordlist() ) {
        CJ::dispatch( $event,
                  "I have no wordlist to work from. "
                . "Install one (Debian: apt install wamerican) or set "
                . '$CJ::command::anagram::wordlist.' );
        return;
    }

    my @found = solve( $term, $include, $exclude );
    if (@found) {
        CJ::dispatch( $event, CJ::pickRandom( [@found] ) );
    }
    else {
        CJ::dispatch( $event, "That's unanagrammaticatable!" );
    }
    return;
}

sub help {
    return <<'END_HELP';
Given a word, return an anagram of it. Usage: anagram <word>. You can
optionally tack on "with <word>" or "without <word>" to tweak the response.
Or both. No more than one of each kind of modifier, though.
END_HELP
}

1;
