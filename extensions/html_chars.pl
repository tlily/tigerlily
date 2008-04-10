# -*- Perl -*-
# $Id$

# Change HTML entity characters to their ascii equivalents, where
# possible.

use strict;
use warnings;

=head1 NAME

html_chars.pl - Change HTML entity characters to their ascii equivalents

=head1 DESCRIPTION

When loaded, this extension will change common HTML escapes to their
ASCII equivalent.  See the following table.

=head1 CONVERSIONS

    &hellip;  =>  ...
    &bull;    =>  *
    &lsquo;   =>  '
    &ldquo;   =>  "
    &ndash;   =>  -
    &mdash;   =>  --
    &nbsp;    =>  space
    &amp;     =>  &
    &copy;    =>  (C)
    &cent;    =>  c
    &trade;   =>  TM
    &reg;     =>  (R)
    &deg;     =>  o

Decimal and hexadecimal codes for the above entities are also
converted (e.g., &#8220 is treated as &ldquo;).

=head1 AUTHOR

Sue D. Nymme, 10 April 2008

=cut

help_r( 'html_chars', << 'END_HELP');
This extension converts common HTML escapes to their ASCII equivalent.
For example, it converts &#8220; to ".
END_HELP

# In the following table, hex codes are denoted by a leading lowercase x.
my @equiv = (
             [ ('hellip', 'x2026', 'x85')    => q{...} ],
             [ ('bull',   'x2022', 'x95')    => q{*}   ],
             [ ('lsquo',  'x2018', 'rsquo', 'x2019', 'prime', 'x2032', 'x91', 'x92')        => q{'}  ],
             [ ('ldquo',  'x201C', 'rsquo', 'x201D', 'Prime', 'x2033', 'x93', 'x94', 'quot') => q{"} ],
             [ ('ndash',  'x2013', 'x96')    => q{-}   ],
             [ ('mdash',  'x2014', 'x97')    => q{--}  ],
             [ ('nbsp',   'xA0')             => q{ }   ],
             [ ('amp',    'x26')             => q{&}   ],
             [ ('copy',   'xA9')             => q{(C)} ],
             [ ('cent',   'xA2')             => q{c}   ],
             [ ('trade',  'x99', 'x2122')    => q{TM}  ],
             [ ('reg',    'xAE')             => q{(R)} ],
             [ ('deg',    'xB0')             => q{o}   ],
            );

# Transform the above table into a lookup-table and regular-expression:
my %trans;    # Translation (look-up table)
my @re_alt;   # Regexp alternation
foreach my $ent (@equiv)
{
    my $result = pop @$ent;
    foreach my $sym (@$ent)
    {
        if ($sym =~ /\A x ([0-9A-Z]+) \z/x)
        {
            my $hex = $1;
            my $dec = hex $hex;

            while (length $hex <= 4)
            {
                $trans{uc "#x$hex"} = $result;
                push @re_alt, "#(?i:x$hex)";
                $hex = "0$hex";
            }

            while (length $dec <= 4)
            {
                $trans{"#$dec"} = $result;
                push @re_alt, "#$dec";
                $dec = "0$dec";
            }
        }
        else
        {
            $trans{$sym} = $result;
            push @re_alt, $sym;
        }
    }
}
my $re_alt = join '|' => @re_alt;
my $re = qr/&($re_alt);/;



# Tranlate the event's text.
sub hc_handler
{
    my($event, $handler) = @_;
    $event->{VALUE} =~ s/$re/$trans{$1} || $trans{uc $1}/ge;
    return 0;
}

# Translate input text.
sub hc_send_handler
{
    my ($ui, $command, $key) = @_;
    $key = '' if !defined $key;

    if (defined $key && $key eq 'nl')
    {
        my $input = $ui->{input};

        # Mustn't expand the send destination
        my ($dest, $text);
        if ($input->{text} =~ /\A ([^ ;]+;) (.*) /xsm)
        {
            ($dest, $text) = ($1, $2);
        }
        else
        {
            ($dest, $text) = ('', $input->{text});
        }

        $text =~ s/$re/$trans{$1} || $trans{uc $1}/ge;
        $input->{text} = $dest . $text;

        $input->update_style();
        $input->rationalize();
        $input->redraw();
    }
    return;
}

event_r(
        type  => 'public',
        call  => \&hc_post_handler,
        order => 'before',
       );

event_r(
        type  => 'private',
        call  => \&hc_post_handler,
        order => 'before',
       );

sub load
{
    my $ui = TLily::UI::name();
    unload();

    $ui->command_r(hc_send_handler => \&hc_send_handler);
    my $rv = $ui->intercept_r(name => "hc_send_handler", order => 1000);
}
sub unload
{
    my $ui = TLily::UI::name();
    $ui->command_u('hc_send_handler');
    $ui->intercept_u(name => "hc_send_handler");
}
