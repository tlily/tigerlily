# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/ui.pl,v 1.3 1999/02/27 22:02:17 josh Exp $ 
use strict;

my $style_help = "
Usage: %style style attr ...
       %cstyle style fg bg attr ...

%style and %cstyle set the attributes to print a style in monochrome and \
color modes, respectively.

Valid attribute values are:
  normal, standout, underline, reverse, blink, dim, bold, altcharset

Valid color values are:
  black, red, green, yellow, blue, magenta, cyan, white

The actual rendering of these attributes and colors is very much up to the
specific UI in use.
";

sub style_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 2) {
	$ui->print("(%style style attr ...; type %help for help)\n");
	return;
    }

    $ui->defstyle(@args);
    $ui->redraw();
    return;
}
command_r(style => \&style_command);
shelp_r(style => "Set the attributes of a text style.");
help_r(style => $style_help);


sub cstyle_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    if (@args < 4) {
	$ui->print("(%cstyle style fg bg attr ...; type %help for help)\n");
	return;
    }

    $ui->defcstyle(@args);
    $ui->redraw();
    return;
}
command_r(cstyle => \&cstyle_command);
shelp_r(cstyle => "Set the color and attributes of a text style.");
help_r(cstyle => $style_help);

TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'color_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if(! $config{mono}) {
				  $ui->defcstyle(${$ev{Key}}, @{${$ev{Value}}});
 			          $ui->redraw();
			      }
		          });


TLily::Config::callback_r(Variable => '-ALL-',
			  List => 'mono_attrs',
			  State => 'STORE',
			  Call => sub {
			      my($tr, %ev) = @_;
			      my $ui = ui_name();

			      if($config{mono}) {
				  $ui->defstyle(${$ev{Key}}, @{${$ev{Value}}});
  			          $ui->redraw();
			      }
		          });

# Set colors from what the config files read
if($config{mono}) {
    my($k,$v);
    my $ui = ui_name();
    while (($k,$v) = each %{$config{'mono_attrs'}}) {
	$ui->defstyle($k, @{$v});
    }
    $ui->redraw;
} else {
    my($k,$v);
    my $ui = ui_name();
    while (($k,$v) = each %{$config{'color_attrs'}}) {
	$ui->defcstyle($k, @{$v});
    }
    $ui->redraw;
}

