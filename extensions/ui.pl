# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/ui.pl,v 1.8 1999/03/16 19:44:02 neild Exp $ 
use strict;


#
# Keybindings.
#

my $bind_help = "
Usage: %bind [locally] key [command]

%bind binds a key to a command.  The actual set of commands you can bind \
a key to is unfortunately poorly specified at this time.  If the \"locally\" \
argument is specified (or a substring thereof), the binding will apply only \
to the current UI; otherwise, it will be a global binding.

If the command argument is not specified, the key will be bound to print
itself.

(see also %keyname)
";

my $keyname_help = "
Usage: %keyname

Prints the name (suitable for use in %bind) of the next key pressed.

(see also %bind)
";

sub bind_command {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;
    my $local;

    if ($args[0] && index("locally", $args[0]) == 0) {
	shift @args;
	$local = 1;
    }

    if (@args == 1) {
	push @args, "insert-self";
    }
    elsif (@args != 2) {
	$ui->print("(%bind [locally] key command; type %help for help)\n");
	return;
    }

    $ui->print("(binding \"$args[0]\" to \"$args[1]\")\n");
    if ($local) {
	$ui->bind(@args);
    } else {
	TLily::UI::bind(@args);
    }

    return;
}
command_r('bind' => \&bind_command);
shelp_r('bind' => "Bind a key to a command.");
help_r('bind' => $bind_help);


sub name_self {
    my($ui, $command, $key) = @_;
    $ui->intercept_u($command);
    $ui->print("(you pressed \"$key\")\n");
    return 1;
}
TLily::UI::command_r("name-self" => \&name_self);


sub keyname_command {
    my($ui, $args) = @_;

    if ($args) {
	$ui->print("(%keyname; type %help for help)\n");
	return;
    }

    if (!$ui->intercept_r("name-self")) {
	$ui->print("(sorry; a keyboard intercept is already in place)\n");
	return;
    }

    $ui->print("Press any key.\n");
    return;
}
command_r(keyname => \&keyname_command);
shelp_r(keyname => "Print the name of the next key pressed.");
help_r(keyname => $keyname_help);


#
# Windows.
#

sub ui_command {
    my($ui, $args) = @_;
    my $newui = TLily::UI::Curses->new(name => 'sub');
    $newui->print("foo\n");
}
command_r(ui => \&ui_command);


#
# Paging.
#

my $page_help = "
Usage: %page [on | off]

%page enables and disables output paging.
";

sub page_command {
    my($ui, $args) = @_;

    if ($args eq "") {
	if ($ui->page()) {
		$ui->print("(paging is currently enabled)\n");
	} else {
		$ui->print("(paging is currently disabled)\n");
	}
    } elsif ($args eq "on") {
	$ui->page(1);
	$ui->print("(paging is now enabled)\n");
    } elsif ($args eq "off") {
	$ui->page(0);
	$ui->print("(paging is now disabled)\n");
    } else {
	$ui->print("(%page on|off; type %help for help)\n");
    }

    return;
}
command_r(page => \&page_command);
shelp_r(page => "Turn output paging on and off.");
help_r(page => $page_help);

#
# Styles.
#

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


sub load {
    # Set colors from what the config files read
    my($k,$v);
    my $ui = ui_name();
    while (($k,$v) = each %{$config{'mono_attrs'}}) {
	$ui->defstyle($k, @{$v});
    }

    while (($k,$v) = each %{$config{'color_attrs'}}) {
	$ui->defcstyle($k, @{$v});
    }
    $ui->redraw;
}

