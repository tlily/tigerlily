# -*- Perl -*-
# $Id$

use strict;

=head1 NAME

ascify.pl - Turn extended ISO 8859-1 characters into ascii approximations.

=head1 DESCRIPTION

Lily only supports plain ASCII, so multibyte characters must be turned into 
their nearest ASCII approximations to be sent.

When pasting content from a web page that uses extended characters, the tlily
UI module may choose to pass these through as special HTML-style entities,
which can then be formatted by this extension.

Currently this feature is supported by the TextWindow UI's Curses backend
only, but it can be implemented in others where it makes sense.

Note that the default is to strip all accents and diacriticals marks from
letters.  To approximate them by writing them as two characters, 
letter followed by diacritical, %set ascify_nostrip_accents 1

=over 10

=head1 COMMANDS

=item ascify

%ascify - show list of all ascification mappings
%ascify <entity name> - show one mapping
%ascify <entity name> <new mapping> - override default mapping

=cut

# may map to either a single char, or to a strip accent/no strip access pair.
my @config = (
    # Misc
    '&euro;'    => 'EUR',       'euro ()',
    '&ensp;'    => ' ',         'en space',
    '&emsp;'    => ' ',         'em space',
    '&thinsp;'  => ' ',         'thin space',
    '&zwnj;'    => '',          'zero width non-joiner',
    '&zwj;'     => '',          'zero width joiner',
    '&lrm;'     => '',          'left-to-right mark',
    '&rlm;'     => '',          'right-to-left mark',
    '&ndash;'   => '-',         'en dash',
    '&mdash;'   => '--',        'em dash',
    '&lsquo;'   => "'",         'left single quotation mark',
    '&rsquo;'   => "'",         'right single quotation mark',
    '&sbquo;'   => "'",         'single low-9 quotation mark',
    '&ldquo;'   => '"',         'left double quotation mark',
    '&rdquo;'   => '"',         'right double quotation mark',
    '&bdquo;'   => '"',         'double low-9 quotation mark',
    '&dagger;'  => "[t]",       'dagger',
    '&Dagger;'  => "[tt]",      'double dagger',
    '&permil;'  => "%%",        'per mille sign',
    '&lsaquo;'  => '<',         'single left-pointing angle quotation mark',
    '&rsaquo;'  => '>',         'single right-pointing angle quotation mark',
    '&hellip;'  => '...',       'horizontal elipsis',
    '&bull;'    => '-',         'bullet',
    
    # ISO 8859-1 Symbols
    '&nbsp;',   => ' ',         'non-breaking space',
    '&iexcl;'	=> '!',         'inverted exclamation mark (¡)',
    '&cent;'	=> ' cents',    'cent (¢)',
    '&pound;'	=> 'GBP',       'pound (£)',
#   '&curren;'	=> undef,       'currency (¤)',
    '&yen;'	=> 'JPY',       'yen (¥)',
    '&brvbar;'	=> '|',         'broken vertical bar (¦)',
    '&sect;'	=> 'S',         'section (§)',
    '&uml;'	=> ':',         'spacing diaeresis (¨)',
    '&copy;'	=> '(c)',       'copyright (©)',
#   '&ordf;'	=> undef,       'feminine ordinal indicator (ª)',
    '&laquo;'	=> '<<',        'angle quotation mark (left) («)',
    '&not;'	=> '!',         'negation (¬)',
    '&shy;'	=> '-',         'soft hyphen (­)',
    '&reg;'	=> '(r)',       'registered trademark (®)',
    '&macr;'	=> '-',         'spacing macron (¯)',
    '&deg;'	=> '*',         'degree (°)',
    '&plusmn;'	=> '+/-',       'plus-or-minus (±)',
    '&sup2;'	=> '^2',        'superscript 2 (²)',
    '&sup3;'	=> '^3',        'superscript 3 (³)',
    '&acute;'	=> "'",         'spacing acute (´)',
    '&micro;'	=> 'u',         'micro (µ)',
    '&para;'	=> '[|P]',      'paragraph (¶)',
    '&middot;'	=> '.',         'middle dot (·)',
    '&cedil;'	=> ',',         'spacing cedilla (¸)',
    '&sup1;'	=> '^1',        'superscript 1 (¹)',
#   '&ordm;'	=> undef,       'masculine ordinal indicator (º)',
    '&raquo;'	=> '>>',        'angle quotation mark (right) (»)',
    '&frac14;'	=> '1/4',       'fraction 1/4 (¼)',
    '&frac12;'	=> '1/2',       'fraction 1/2 (½)',
    '&frac34;'	=> '3/4',       'fraction 3/4 (¾)',
    '&iquest;'	=> '?',         'inverted question mark (¿)',
    '&times;'	=> 'x',         'multiplication (×)',
    '&divide;'	=> '/',         'division (÷)',

    # ISO 8859-1 Characters
    '&Agrave;'	=> ['A',"A`"],  'capital a, grave accent (À)',
    '&Aacute;'	=> ['A',"A'"],  'capital a, acute accent (Á)',
    '&Acirc;'	=> ['A','A^'],  'capital a, circumflex accent (Â)',
    '&Atilde;'	=> ['A','A~'],  'capital a, tilde (Ã)',
    '&Auml;'	=> ['A','A:'],  'capital a, umlaut mark (Ä)',
    '&Aring;'	=> ['A','A*'],  'capital a, ring (Å)',
    '&AElig;'	=> 'AE',        'capital ae (Æ)',
    '&Ccedil;'	=> ['C','C,'],  'capital c, cedilla (Ç)',
    '&Egrave;'	=> ['E',"E`"],  'capital e, grave accent (È)',
    '&Eacute;'	=> ['E',"E'"],  'capital e, acute accent (É)',
    '&Ecirc;'	=> ['E','E^'],  'capital e, circumflex accent (Ê)',
    '&Euml;'	=> ['E','E'],   'capital e, umlaut mark (Ë)',
    '&Igrave;'	=> ['I','I`'],  'capital i, grave accent (Ì)',
    '&Iacute;'	=> ['I',"I'"],  'capital i, acute accent (Í)',
    '&Icirc;'	=> ['I','I^'],  'capital i, circumflex accent (Î)',
    '&Iuml;'	=> ['I','I:'],  'capital i, umlaut mark (Ï)',
#   '&ETH;'	=> undef,       'capital eth, Icelandic (Ð)',
    '&Ntilde;'	=> ['N','N~'],  'capital n, tilde (Ñ)',
    '&Ograve;'	=> ['O','O`'],  'capital o, grave accent (Ò)',
    '&Oacute;'	=> ['O',"O'"],  'capital o, acute accent (Ó)',
    '&Ocirc;'	=> ['O','O^'],  'capital o, circumflex accent (Ô)',
    '&Otilde;'	=> ['O','O~'],  'capital o, tilde (Õ)',
    '&Ouml;'	=> ['O','O:'],  'capital o, umlaut mark (Ö)',
    '&Oslash;'	=> '0',         'capital o, slash (Ø)',
    '&Ugrave;'	=> ['U','U`'],  'capital u, grave accent (Ù)',
    '&Uacute;'	=> ['U',"U'"],  'capital u, acute accent (Ú)',
    '&Ucirc;'	=> ['U','U^'],  'capital u, circumflex accent (Û)',
    '&Uuml;'	=> ['U','U:'],  'capital u, umlaut mark (Ü)',
    '&Yacute;'	=> ['Y',"Y'"],  'capital y, acute accent (Ý)',
#   '&THORN;'	=> undef,       'capital THORN, Icelandic (Þ)',
    '&szlig;'	=> 'B',         'small sharp s, German (ß)',
    '&agrave;'	=> ['a','a`'],  'small a, grave accent (à)',
    '&aacute;'	=> ['a',"a'"],  'small a, acute accent (á)',
    '&acirc;'	=> ['a','a^'],  'small a, circumflex accent (â)',
    '&atilde;'	=> ['a','a~'],  'small a, tilde (ã)',
    '&auml;'	=> ['a','a:'],  'small a, umlaut mark (ä)',
    '&aring;'	=> ['a','a*'],  'small a, ring (å)',
    '&aelig;'	=> 'ae',        'small ae (æ)',
    '&ccedil;'	=> ['c','c,'],  'small c, cedilla (ç)',
    '&egrave;'	=> ['e','e`'],  'small e, grave accent (è)',
    '&eacute;'	=> ['e',"e'"],  'small e, acute accent (é)',
    '&ecirc;'	=> ['e','e^'],  'small e, circumflex accent (ê)',
    '&euml;'	=> ['e','e:'],  'small e, umlaut mark (ë)',
    '&igrave;'	=> ['i','i^'],  'small i, grave accent (ì)',
    '&iacute;'	=> ['i',"i'"],  'small i, acute accent (í)',
    '&icirc;'	=> ['i','i^'],  'small i, circumflex accent (î)',
    '&iuml;'	=> ['i','i:'],  'small i, umlaut mark (ï)',
#   '&eth;'	=> undef,       'small eth, Icelandic (ð)',
    '&ntilde;'	=> ['n','n~'],  'small n, tilde (ñ)',
    '&ograve;'	=> ['o','o`'],  'small o, grave accent (ò)',
    '&oacute;'	=> ['o',"o'"],  'small o, acute accent (ó)',
    '&ocirc;'	=> ['o','o^'],  'small o, circumflex accent (ô)',
    '&otilde;'	=> ['o','o~'],  'small o, tilde (õ)',
    '&ouml;'	=> ['o','o:'],  'small o, umlaut mark (ö)',
    '&oslash;'	=> ['o','0'],   'small o, slash (ø)',
    '&ugrave;'	=> ['u','u`'],  'small u, grave accent (ù)',
    '&uacute;'	=> ['u',"u'"],  'small u, acute accent (ú)',
    '&ucirc;'	=> ['u','u^'],  'small u, circumflex accent (û)',
    '&uuml;'	=> ['u','u:'],  'small u, umlaut mark (ü)',
    '&yacute;'	=> ['y',"y'"],  'small y, acute accent (ý)',
#   '&thorn;'	=> undef,       'small thorn, Icelandic (þ)',
    '&yuml;'    => ['y','y:'],   'small y, umlaut mark (ÿ)'
);

my %entity_ascii_map;
my %entity_description;
while (@config) {
    my $entity = shift @config;
    my $ascii = shift @config;
    my $description = shift @config;

    $entity_ascii_map{$entity} = $ascii;
    $entity_description{$entity} = $description;
}

sub ascify_entity {
    my($ui, $command, $key) = @_;

    if (exists($entity_ascii_map{$key})) {
	my $ascii = $entity_ascii_map{$key};
	if (ref($ascii)) {
	    if ($config{ascify_nostrip_accents}) {
		$ascii = $ascii->[1];
	    } else {
		$ascii = $ascii->[0];
	    }
	}

	foreach my $char (split '', $ascii) {
	    $ui->command('insert-self', $char);	
	}

	return 1; # do no further processing of the entity- instead, 
	          # other intercepts will process the individual characters
               	  # we ascified it to.
    }
}

sub ascify_cmd {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (! @args) {
	foreach my $entity (sort keys %entity_description) {
	    my $ascii = $entity_ascii_map{$entity} || '(not bound)';
	    if (ref($ascii)) {
		if ($config{ascify_nostrip_accents}) {
		    $ascii = $ascii->[1]; 
		} else {
		    $ascii = $ascii->[0]; 
		}
	    }

	    my $description = $entity_description{$entity};

	    $ui->print(sprintf("%-16s %-10s %s\n", $entity, $ascii, $description));
	}
	return;
    }

    # allow them to leave off the & and ; if they want.. laziness is nice.
    if ($args[0] !~ /^\&/) { $args[0] = "&" . $args[0]; }
    if ($args[0] !~ /;$/)  { $args[0] .= ";"; }

    if (@args == 1) {
	my $entity = $args[0];
	my $ascii = $entity_ascii_map{$entity};
	if (ref($ascii)) {
	    if ($config{ascify_nostrip_accents}) {
		$ascii = $ascii->[1]; 
	    } else {
		$ascii = $ascii->[0]; 
	    }
	}
	
	if (exists($entity_ascii_map{$entity})) {
	    $ui->print("(Entity '$entity' is bound to '$ascii')");
	} else {
	    $ui->print("(Entity '$entity' is not bound)");
	}

	return;
    }

    # Set it to what they desire.
    my $entity = $args[0];
    my $ascii = $args[1];

    $entity_ascii_map{$entity} = $ascii;
}

command_r('ascify', \&ascify_cmd);
shelp_r(ascify => 'Control mapping of ISO 8859-1 to ascii');
help_r(ascify => "Usage:
%ascify - show list of all ascification mappings
%ascify <entity name> - show one mapping
%ascify <entity name> <new mapping> - override default mapping

See %help extensions::ascify.pl for more details.");

shelp_r(ascify_nostrip_accents => '[boolean] Write accented characters with accent following character, instead of stripping the accents completely.', 'variables');

TLily::UI::command_r("ascify-entity"        => \&ascify_entity);

sub load {
    my $ui = TLily::UI::name();

    $ui->intercept_r(name => "ascify-entity", order => 90);
}
    
