# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 2003-2006  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::FoiledAgain::Curses;

use vars qw(@ISA $sigwinch $COLS $LINES);

use TLily::FoiledAgain;
@ISA = qw(TLily::FoiledAgain);

my ($STTY_LNEXT, $WANT_COLOR, $USING_COLOR);

use strict;
use Carp;

use Curses;

=head1 NAME

TLily::FoiledAgain::Curses - Curses implementation of the FoiledAgain interface

=cut

# The keycodemap hash maps Curses keycodes to English names.
my %keycodemap =
  (
   &KEY_DOWN        => 'down',
   &KEY_UP          => 'up',
   &KEY_LEFT        => 'left',
   &KEY_RIGHT       => 'right',
   &KEY_PPAGE       => 'pageup',
   &KEY_NPAGE       => 'pagedown',
   &KEY_BACKSPACE   => 'bs',
   &KEY_IC          => 'ins',
   &KEY_DC          => 'del',
   &KEY_HOME        => 'home',
   &KEY_END         => 'end',
   "\n"             => 'nl'
  );

# The stylemap and cstylemap hashes map style names to Curses attributes.
my %stylemap   = (default => A_NORMAL);
my %cstylemap  = (default => A_NORMAL);


# The cnamemap hash maps English color names to Curses colors.
my %cnamemap   =
  (
   '-'              => -1,
   mask             => -1,
   black            => COLOR_BLACK,
   red              => COLOR_RED,
   green            => COLOR_GREEN,
   yellow           => COLOR_YELLOW,
   blue             => COLOR_BLUE,
   magenta          => COLOR_MAGENTA,
   cyan             => COLOR_CYAN,
   white            => COLOR_WHITE,
  );

# The snamemap hash maps English style names to Curses styles.
my %snamemap   =
  (
   '-'             => A_NORMAL,
   'normal'        => A_NORMAL,
   'standout'      => A_STANDOUT,
   'underline'     => A_UNDERLINE,
   'reverse'       => A_REVERSE,
   'blink'         => A_BLINK,
   'dim'           => A_DIM,
   'bold'          => A_BOLD,
   'altcharset'    => A_ALTCHARSET,
  );

# The cpairmap hash maps color pairs in the format "fg bg" to color pair
# IDs.  (fg and bg are Curses color IDs.)
my %cpairmap   = ("-1 -1" => 0);

# The entity map matches unicode characters to HTML-style
# entities for non-ASCII characters that might be pasted in from some
# other program.
my %entitymap = (
    # Misc
    128 => '&euro;',   # euro ()
    130 => '&sbquo;',  # single low-9 quotation mark
    132 => '&bdquo;',  # double low-9 quotation mark
    133 => '&hellip;', # horizontal elipsis
    134 => '&dagger;', # dagger
    135 => '&Dagger;', # double dagger
    137 => '&permil;', # per mille sign
    139 => '&lsaquo;', # single left-pointing angle quotation mark
    145 => '&lsquo;',  # left single quotation mark
    146 => '&rsquo;',  # right single quotation mark
    147 => '&ldquo;',  # left double quotation mark
    148 => '&rdquo;',  # right double quotation mark
    149 => '&bull;',   # bullet
    150 => '&ndash;',   # en dash
    151 => '&mdash;',   # em dash
    155 => '&rsaquo;',  # single right-pointing angle quotation mark
    8192 => '&ensp;',   # en quad
    8194 => '&ensp;',   # en space
    8195 => '&emsp;',   # em space
    8201 => '&thinsp;', # thin space
    8204 => '&zwnj;',   # zero width non-joiner
    8205 => '&zwj;',    # zero width joiner
    8206 => '&lrm;',    # left-to-right mark
    8207 => '&rlm;',    # right-to-left mark
    8211 => '&ndash;',  # en dash
    8212 => '&mdash;',  # em dash
    8216 => '&lsquo;',  # left single quotation mark
    8217 => '&rsquo;',  # right single quotation mark
    8218 => '&sbquo;',  # single low-9 quotation mark
    8220 => '&ldquo;',  # left double quotation mark
    8221 => '&rdquo;',  # right double quotation mark
    8222 => '&bdquo;',  # double low-9 quotation mark
    8224 => '&dagger;', # dagger
    8225 => '&Dagger;', # double dagger
    8226 => '&bull;',   # bullet
    8230 => '&hellip;', # horizontal elipsis
    8240 => '&permil;', # per mille sign
    8249 => '&lsaquo;', # single left-pointing angle quotation mark
    8250 => '&rsaquo;', # single right-pointing angle quotation mark
    8364 => '&euro;',   # euro sign
    65279 => '&zwj;',   # zero width no-break space

    # ISO 8859-1 Symbols
    160 => '&nbsp;',   # non-breaking space
    161 => '&iexcl;',  # inverted exclamation mark (¡)
    162 => '&cent;',   # cent (¢)
    163 => '&pound;',  # pound (£)
    164 => '&curren;', # currency (¤)
    165 => '&yen;',    # yen (¥)
    166 => '&brvbar;', # broken vertical bar (¦)
    167 => '&sect;',   # section (§)
    168 => '&uml;',    # spacing diaeresis (¨)
    169 => '&copy;',   # copyright (©)
    170 => '&ordf;',   # feminine ordinal indicator (ª)
    171 => '&laquo;',  # angle quotation mark (left) («)
    172 => '&not;',    # negation (¬)
    173 => '&shy;',    # soft hyphen (­)
    174 => '&reg;',    # registered trademark (®)
    175 => '&macr;',   # spacing macron (¯)
    176 => '&deg;',    # degree (°)
    177 => '&plusmn;', # plus-or-minus (±)
    178 => '&sup2;',   # superscript 2 (²)
    179 => '&sup3;',   # superscript 3 (³)
    180 => '&acute;',  # spacing acute (´)
    181 => '&micro;',  # micro (µ)
    182 => '&para;',   # paragraph (¶)
    183 => '&middot;', # middle dot (·)
    184 => '&cedil;',  # spacing cedilla (¸)
    185 => '&sup1;',   # superscript 1 (¹)
    186 => '&ordm;',   # masculine ordinal indicator (º)
    187 => '&raquo;',  # angle quotation mark (right) (»)
    188 => '&frac14;', # fraction 1/4 (¼)
    189 => '&frac12;', # fraction 1/2 (½)
    190 => '&frac34;', # fraction 3/4 (¾)
    191 => '&iquest;', # inverted question mark (¿)
    215 => '&times;',  # multiplication (×)
    247 => '&divide;', # division (÷)

    # ISO 8859-1 Characters
    192 => '&Agrave;', # capital a, grave accent (À)
    193 => '&Aacute;', # capital a, acute accent (Á)
    194 => '&Acirc;',  # capital a, circumflex accent (Â)
    195 => '&Atilde;', # capital a, tilde (Ã)
    196 => '&Auml;',   # capital a, umlaut mark (Ä)
    197 => '&Aring;',  # capital a, ring (Å)
    198 => '&AElig;',  # capital ae (Æ)
    199 => '&Ccedil;', # capital c, cedilla (Ç)
    200 => '&Egrave;', # capital e, grave accent (È)
    201 => '&Eacute;', # capital e, acute accent (É)
    202 => '&Ecirc;',  # capital e, circumflex accent (Ê)
    203 => '&Euml;',   # capital e, umlaut mark (Ë)
    204 => '&Igrave;', # capital i, grave accent (Ì)
    205 => '&Iacute;', # capital i, acute accent (Í)
    206 => '&Icirc;',  # capital i, circumflex accent (Î)
    207 => '&Iuml;',   # capital i, umlaut mark (Ï)
    208 => '&ETH;',    # capital eth, Icelandic (Ð)
    209 => '&Ntilde;', # capital n, tilde (Ñ)
    210 => '&Ograve;', # capital o, grave accent (Ò)
    211 => '&Oacute;', # capital o, acute accent (Ó)
    212 => '&Ocirc;',  # capital o, circumflex accent (Ô)
    213 => '&Otilde;', # capital o, tilde (Õ)
    214 => '&Ouml;',   # capital o, umlaut mark (Ö)
    216 => '&Oslash;', # capital o, slash (Ø)
    217 => '&Ugrave;', # capital u, grave accent (Ù)
    218 => '&Uacute;', # capital u, acute accent (Ú)
    219 => '&Ucirc;',  # capital u, circumflex accent (Û)
    220 => '&Uuml;',   # capital u, umlaut mark (Ü)
    221 => '&Yacute;', # capital y, acute accent (Ý)
    222 => '&THORN;',  # capital THORN, Icelandic (Þ)
    223 => '&szlig;',  # small sharp s, German (ß)
    224 => '&agrave;', # small a, grave accent (à)
    225 => '&aacute;', # small a, acute accent (á)
    226 => '&acirc;',  # small a, circumflex accent (â)
    227 => '&atilde;', # small a, tilde (ã)
    228 => '&auml;',   # small a, umlaut mark (ä)
    229 => '&aring;',  # small a, ring (å)
    230 => '&aelig;',  # small ae (æ)
    231 => '&ccedil;', # small c, cedilla (ç)
    232 => '&egrave;', # small e, grave accent (è)
    233 => '&eacute;', # small e, acute accent (é)
    234 => '&ecirc;',  # small e, circumflex accent (ê)
    235 => '&euml;',   # small e, umlaut mark (ë)
    236 => '&igrave;', # small i, grave accent (ì)
    237 => '&iacute;', # small i, acute accent (í)
    238 => '&icirc;',  # small i, circumflex accent (î)
    239 => '&iuml;',   # small i, umlaut mark (ï)
    240 => '&eth;',    # small eth, Icelandic (ð)
    241 => '&ntilde;', # small n, tilde (ñ)
    242 => '&ograve;', # small o, grave accent (ò)
    243 => '&oacute;', # small o, acute accent (ó)
    244 => '&ocirc;',  # small o, circumflex accent (ô)
    245 => '&otilde;', # small o, tilde (õ)
    246 => '&ouml;',   # small o, umlaut mark (ö)
    248 => '&oslash;', # small o, slash (ø)
    249 => '&ugrave;', # small u, grave accent (ù)
    250 => '&uacute;', # small u, acute accent (ú)
    251 => '&ucirc;',  # small u, circumflex accent (û)
    252 => '&uuml;',   # small u, umlaut mark (ü)
    253 => '&yacute;', # small y, acute accent (ý)
    254 => '&thorn;',  # small thorn, Icelandic (þ)
    255 => '&yuml;'    # small y, umlaut mark (ÿ)
);

    sub start {
    # Work around a bug in certain curses implementations where raw() does
    # not appear to clear the "lnext" setting.
    ($STTY_LNEXT) = (`stty -a 2> /dev/null` =~ /lnext = (\S+);/);
    $STTY_LNEXT =~ s/<undef>/undef/g;
    system("stty lnext undef") if ($STTY_LNEXT);

    initscr;

    $USING_COLOR = 0;
    if ($WANT_COLOR && has_colors()) {
        my $rc = start_color();
        $USING_COLOR = ($rc == OK);
        if ($USING_COLOR) {
            eval { use_default_colors(); };
        }
    }

    noecho();
    raw();
    idlok(1);

    # How odd.  Jordan doesn't have idcok().
    eval { idcok(1); };

    typeahead(-1);
    keypad(1);

    $SIG{WINCH} = sub { $sigwinch = 1; };

    while (my($pair, $id) = each %cpairmap) {
        my($fg, $bg) = split / /, $pair, 2;
        init_pair($id, $fg, $bg);
    }
}

sub stop {
    endwin;
    #refresh;
    system("stty lnext $STTY_LNEXT") if ($STTY_LNEXT);
}

sub refresh {
    endwin();
    doupdate();
}


#
# Use Term::Size to determine the terminal size after a SIGWINCH, but don't
# actually require that it be installed.
#

my $termsize_installed;
my $have_ioctl_ph;
BEGIN {
    eval { require Term::Size; import Term::Size; };
    if ($@) {
        $termsize_installed = 0;
    } else {
        $termsize_installed = 1;
    }

    eval { require qw(sys/ioctl.ph); };
    if ($@) {
        $have_ioctl_ph = 0;
    } else {
        $have_ioctl_ph = 1;
    }

    if (!$termsize_installed && !$have_ioctl_ph) {
        warn("*** WARNING: Unable to load Term::Size or ioctl.ph ***\n");
        warn("*** resizes will probably not work ***\n");
        sleep(2);
    }
}

sub has_resized {
    my $resized;

    while ($sigwinch) {
        $resized = 1;
        $sigwinch = 0;
        if ($termsize_installed) {
            ($ENV{'COLUMNS'}, $ENV{'LINES'}) = Term::Size::chars();
        } elsif ($have_ioctl_ph) {
            ioctl(STDIN, &TIOCGWINSZ, my $winsize);
            return 0 if (!defined($winsize));
            my ($row, $col, $xpixel, $ypixel) = unpack('S4', $winsize);
            return 0 if (!defined($row));
            ($ENV{'COLUMNS'}, $ENV{'LINES'}) = ($col, $row);
        }
        stop();
        refresh;
        start();
    }

    return $resized;
}

sub suspend { endwin; }
sub resume  { doupdate; }

sub screen_width  { $COLS; }
sub screen_height { $LINES; }
sub update_screen { doupdate; }
sub bell { beep; }

sub new {
    my($proto, $lines, $cols, $begin_y, $begin_x) = @_;
    my $class = ref($proto) || $proto;

    my $self = {};
    bless($self, $class);

    $self->{W} = newwin($lines, $cols, $begin_y, $begin_x);
    $self->{W}->keypad(1);
    $self->{W}->scrollok(0);
    $self->{W}->nodelay(1);

    $self->{stylemap} = ($USING_COLOR ? \%cstylemap : \%stylemap);

    return $self;
}


sub position_cursor {
    my ($self, $line, $col) = @_;

    $self->{W}->move($line, $col);
    $self->{W}->noutrefresh();
}

my $meta = 0;
sub read_char {
    my($self) = @_;

    my $ctrl;

    my $c = $self->{W}->getch();
    return if ($c eq "-1" || !defined $c);

    #print STDERR "c: '$c' (", ord($c), ")\n";
    return $c if $self->{quoted_insert};

    if (ord($c) == 27) {
        $meta = 1;
        return $self->read_char();
    }

    # Handle 2-byte UTF8
    if (ord($c) >= 194 && ord($c) <= 223) {
        my $c2 = $self->{W}->getch();
        return if ($c2 eq "-1" || !defined $c2);

        # convert utf8 representation ($c, $c2) to unicode number.
        my $num =  (((ord($c) & 31) << 6) | (ord($c2) & 63));

        if (exists($entitymap{$num})) {
            $c = $entitymap{$num};
        } else {
            $c = "&#$num;";
        }
    }

    # Handle 3-byte UTF8
    if (ord($c) >= 224 && ord($c) <= 239) {
        my $c2 = $self->{W}->getch();
        return if ($c2 eq "-1" || !defined $c2);

        my $c3 = $self->{W}->getch();
        return if ($c3 eq "-1" || !defined $c3);

        # convert utf8 representation ($c, $c2, $c3) to unicode number.
        my $num = (((ord($c) & 15) << 12) | ((ord($c2) & 63) << 6) | (ord($c3) & 63));

        if (exists($entitymap{$num})) {
            $c = $entitymap{$num};
        } else {
            $c = "&#$num;";
        }
    }

    if ((ord($c) >= 128) && (ord($c) < 256)) {
        $c = chr(ord($c)-128);
        $meta = 1;
    } elsif (ord($c) == 127) {
        $c = '?';
        $ctrl = 1;
    }

    if (defined $keycodemap{$c}) {
        $c = $keycodemap{$c};
    } elsif (ord($c) <= 31) {
        $c = lc(chr(ord($c) + 64));
        $ctrl = 1;
    }

    my $r = ($ctrl ? "C-" : "") . ($meta ? "M-" : "") . $c;
    $ctrl = $meta = 0;

    #print STDERR "r=$r\n";
    return $r;
}


sub destroy {
    my ($self) = @_;

    $self->{W}->delwin() if ($self->{W});
    $self->{W} = undef;
}


sub clear {
    my ($self) = @_;

    $self->{W}->erase();
}


sub clear_background {
    my ($self, $style) = @_;

    $self->{W}->bkgdset
        (ord(' ') | $self->get_style_attr($style));
}

sub set_style {
    my($self, $style) = @_;

    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    $self->{W}->attrset($self->{stylemap}->{$style});
}


sub clear_line {
    my ($self, $y) = @_;

    $self->{W}->clrtoeol($y, 0);
}


sub move_point {
    my ($self, $y, $x) = @_;

    $self->{W}->move($y, $x);
}


sub addstr_at_point {
    my ($self, $string) = @_;

    $self->{W}->addstr($string);
}


sub addstr {
    my ($self, $y, $x, $string) = @_;

    $self->{W}->addstr($y, $x, $string);
}

sub insch {
    my ($self, $y, $x, $character) = @_;

    $self->{W}->insstr($y, $x, $character);
}

sub delch_at_point {
    my ($self, $y, $x) = @_;

    $self->{W}->delch();
}

sub scroll {
    my ($self, $numlines) = @_;

    $self->{W}->scrollok(1);
    $self->{W}->scrl($numlines);
    $self->{W}->scrollok(0);
}

sub commit {
    my ($self) = @_;

    $self->{W}->noutrefresh();
}

sub want_color {
    ($WANT_COLOR) = @_;
}

sub reset_styles {
    %stylemap  = (default => A_NORMAL);
    %cstylemap = (default => A_NORMAL);
}

sub defstyle {
    my($style, @attrs) = @_;
    $stylemap{$style} = parsestyle(@attrs);
}


sub defcstyle {
    my($style, $fg, $bg, @attrs) = @_;
    $cstylemap{$style} = parsestyle(@attrs) | color_pair($fg, $bg);
}

##############################################################################
# Private Functions
sub get_style_attr {
    my($self, $style) = @_;
    my $attr;
    $style = "default" if (!defined $self->{stylemap}->{$style});
    return $self->{stylemap}->{$style};
}


sub parsestyle {
    my $style = 0;
    foreach (@_) { $style |= $snamemap{$_} if $snamemap{$_} };
    return $style;
}


sub colorid {
        my($col) = @_;

        if (defined($cnamemap{$col})) {
                return $cnamemap{$col}
        } elsif ($col =~ /^gr[ae]y(\d+)$/) {
                $col = $1 + 232;
                return undef if ($col > 255);
                return $col;
        } elsif ($col =~ /^(\d+),(\d+),(\d+)$/) {
                $col = (16 + $1 * 36 + $2 * 6 + $3);
                return undef if ($col < 16 || $col > 231);
                return $col;
        } else {
                return undef;
        }
}


sub color_pair {
    my($fg, $bg) = @_;
    my $pair;

    return 0 unless (defined $fg && defined $bg);

    $fg = colorid($fg);
    $fg = COLOR_WHITE unless defined($fg);
    $bg = colorid($bg);
    $bg = COLOR_BLACK unless defined($bg);

    if (defined $cpairmap{"$fg $bg"}) {
        $pair = $cpairmap{"$fg $bg"};
    } else {
        $pair = scalar(keys %cpairmap);
        my $rc = init_pair($pair, $fg, $bg);
        return COLOR_PAIR(0) if ($rc == ERR);
        $cpairmap{"$fg $bg"} = $pair;
    }

    return COLOR_PAIR($pair);
}


1;
