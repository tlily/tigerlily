# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/on.pl,v 1.6 2000/03/24 21:23:43 kazrak Exp $

use strict;
use Text::ParseWords qw(quotewords);

# bugs:
#
# \n in the what to do section isn't working.
#
# handling of the final field (what to do) is wonky.  RIght now, you pretty 
#    much want to put it in quotes.  Ick.


my $usage = "%on [<event> [from <source>] [to <dest>] [value|like <value>] <what to do>]";

command_r(on => \&on_cmd);
shelp_r(on => "execute a command when a specific event occurs");
help_r('on', qq[
%on
%on list
%on clear <id>
$usage

(where <event> is any standard SLCP event, such as "public", "private", or 
"emote".  <value> is the VALUE parameter to that SLCP event, which is the
message body in the "public", "private", and "emote" events.)

%on supports the following special characters in "what to do":

\$1 .. \$9  variable matches in the regexp, if "like" is used.
\$sender   for "public", "private", or "emote" events, the sender of the
          message.
\$value    the value of the original event

Alternatively, you may use "%attr <attribute> <value>" in "what to do"
to set attributes on the event being matched.  Of particular interest
are the "header_fmt", "sender_fmt", "dest_fmt", "body_fmt", and
"slcp_fmt" attributes, which control how sends are displayed.  (Note
that these attributes take styles as arguments -- see %help style for
more information.)

Examples:

  %on unidle from appleseed "appleseed;[autonag] Gimme my scsi card!"
  %on emote to beener like "fluffs almo" "beener;auto-spurts feathers"
  %on emote to beener like "ping (.*)" "$1;ping!"
  %on public to news %attr dest_fmt significant
  %on attach from SignificantOther %attr slcp_fmt significant
]);


my @on_handlers;

sub on_cmd {
    my($ui, $args) = @_;
    my %mask;

    $args =~ s/\\/\\\\/g;

    if ($args !~ /\S/) {
	if (@on_handlers) {
	    $ui->printf("%5.5s %-70.70s\n", "Id", "Description");
	    $ui->printf("%5.5s %-70.70s\n", "-" x 5, "-" x 70);
	    foreach (@on_handlers) {
		$ui->printf("%5.5s %-70.70s\n", $_->[0], $_->[1]);
	    }
	} else {
	    $ui->print("(no %on handlers are currently registered)\n");
	}
	return;
    }

    if ($args =~ /^\s*clear\s*(\d+)/) {
	if (grep { $_->[0] == $1 } @on_handlers) {
	    event_u($1);
	    $ui->print("(%on handler id $1 removed)\n");
	} else {
	    $ui->print("(%on handler id $1 not found)\n");
	}
	
	@on_handlers = grep { $_->[0] != $1 } @on_handlers;
	return;
    }


    my @args = quotewords('\s+',0,$args);

    if (@args < 2) {
	$ui->print("Usage: $usage\n");
	return;
    }

    my $event_type = shift @args;
    my $server = active_server();

    while ($args[0] =~ /^(from|to|value|like)$/i) {
	my $masktype = uc(shift @args);
	my $maskval  = shift @args;

	if ($masktype =~ /^(FROM|TO)$/) {
	    my $name   = $server->expand_name($maskval);
	    $name =~ s/^-//;
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
    if ($mask{"LIKE"}) {
	$str .= " with a value like \"" . $mask{"LIKE"} . "\"";
    } elsif ($mask{"VALUE"}) {
	$str .= " with a value of \"" . $mask{"VALUE"} . "\"";
    }
    $str .= ", I will run \"@args\")\n";

    $ui->print($str);

    my $attr;
    if ($args[0] eq '%attr') {
	shift @args;
	$attr = shift @args;
    }

    my $handler = event_r(type => $event_type,
			  call => sub {
			      my ($e,$h) = @_;
			      my $match = 1;
			      my ($m1,$m2,$m3,$m4,$m5,$m6,$m7,$m8,$m9);

			      foreach (keys %mask) {
				  if (/LIKE/) {
				      if ($e->{"VALUE"} !~ /$mask{$_}/i) {
					  $match = 0;
				      } else {
					  ($m1,$m2,$m3,$m4,$m5,$m6,$m7,$m8,$m9)
					    = ($1,$2,$3,$4,$5,$6,$7,$8,$9);
				      }
				  } elsif (/RHANDLE/) {
				      $match = 0;
				      # RHANDLE is an arrayref.  Ugh.
				      foreach (@{$e->{$_}}) {
					  $match=1 if ($mask{"RHANDLE"} eq $_);
				      }				      
				  } elsif ($mask{$_} ne $e->{$_}) {
				      $match = 0;
				  }

				  last if $match == 0;
			      }

			      if ($match) {
				  my $cmd = "@args";
				  my ($sender, $value);

				  $cmd =~ s/\$sender/$e->{SOURCE}/g;
				  $cmd =~ s/\$value/$e->{VALUE}/g;
				  $cmd =~ s/\$1/$m1/g;
				  $cmd =~ s/\$2/$m2/g;
				  $cmd =~ s/\$3/$m3/g;
				  $cmd =~ s/\$4/$m4/g;
				  $cmd =~ s/\$5/$m5/g;
				  $cmd =~ s/\$6/$m6/g;
				  $cmd =~ s/\$7/$m7/g;
				  $cmd =~ s/\$8/$m8/g;
				  $cmd =~ s/\$9/$m9/g;

				  if (defined $attr) {
				      $e->{$attr} = $cmd;
				  } else {
				      # ignore events from me.
				      if ($e->{"SHANDLE"} eq $e->{server}->user_handle) {
					  return;				  
				      }
			      
				      foreach (split /\\n/, $cmd) {
					  TLily::Event::send({type => 'user_input',
							      ui   => $e->{ui},
							      text => "$_\n"});
				      }
				  }
			      }

			      return(0);
			  });
    push @on_handlers, [ $handler, $args ];
}

sub unload {
    my $ui = ui_name();
    while (@on_handlers) {
	on_cmd($ui, "clear $on_handlers[0]->[0]");
    }
}

1;
