# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/on.pl,v 1.1 1999/10/06 17:05:36 josh Exp $

use strict;
use Text::ParseWords qw(quotewords);

# bugs:
#
# %on should list the registered on handlers
# handling of the final field (what to do) is wonky.  RIght now, you pretty 
#    much want to put it in quotes.  Ick.


my $usage = "Usage: %on <event> [from <source>] [to <dest>] [value <value>] <what to do>";

command_r(on => \&on_cmd);
shelp_r(on => "execute a command when a specific event occurs");
help_r('on', "
$usage

Example:

%on unidle from appleseed \"appleseed;[autonag] Gimme my scsi card!\"
");



sub on_cmd {
    my($ui, $args) = @_;
    my %mask;

    my @args = quotewords('\s+',0,$args);

    if (@args < 2) {
	$ui->print("$usage\n");
	return;
    }

    my $event_type = shift @args;
    my $server = active_server();

    while ($args[0] =~ /^(from|to|value)$/i) {
	my $masktype = uc(shift @args);
	my $maskval  = shift @args;

	if ($masktype =~ /^(FROM|TO)$/) {
	    my $name   = $server->expand_name($maskval);
	    my $handle = $server->{"NAME"}{lc($name)}{"HANDLE"};
	    if ($handle !~ /^\#\d+/) {
		$ui->print("($maskval not found)\n");
		return;
	    }
	    $maskval = $handle;
	}

	$masktype = "SHANDLE" if ($masktype eq "FROM"); 
	$masktype = "RHANDLE" if ($masktype eq "TO");
	$mask{$masktype} = $maskval;
    }

    my $str;

    $str = "(on " . $event_type . " events";
    $str .= " from " .$server->{"HANDLE"}{$mask{"SHANDLE"}}{"NAME"} if $mask{"SHANDLE"};
    $str .= " to " .$server->{"HANDLE"}{$mask{"RHANDLE"}}{"NAME"} if $mask{"RHANDLE"};
    $str .= " with a value of \"" . $mask{"VALUE"} . "\"" if $mask{"VALUE"};
    $str .= ", I will run \"@args\")\n";

    $ui->print($str);

    my $handler = event_r(type => $event_type,
			  call => sub {
			      my ($e,$h) = @_;
			      my $match = 1;
			      foreach (keys %mask) {
				  if ($mask{$_} ne $e->{$_}) {
				      $match = 0;
				  }
			      }
			      
			      if ($match) {
				  TLily::Event::send({type => 'user_input',
						      ui   => $e->{ui},
						      text => "@args\n"});
			      }			      

			      return(0);
			  });
}



1;
