# -*- Perl -*-
# $header$

use strict;

my %pinheads;

sub pinhead_command_handler {
    my($ui, $args) = @_;
    my $server = active_server();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
	if (scalar(keys(%pinheads)) == 0) {
	    $ui->print("(there are currently no pinheads)\n");
	} else {
	    $ui->print("(current pinheads: ",
		       join(', ', sort values(%pinheads)),
		       ")\n" );
	}
	return;
    }
    
    if (@args != 1) {
	$ui->print("(%pinhead name; type %help for help)\n");
	return;
    }

    my $name = TLily::Server::SLCP::expand_name($args[0]);
    if ((!defined $name) || ($name =~ /^-/)) {
	ui_output("(could find no match to \"$args[0]\")");
	return;
    }

    my %state = $server->state(NAME => $name);
    if (!$state{HANDLE}) {
	ui_output("(could find no match to \"$args[0]\")");
	return;
    }

    if (defined $pinheads{$state{HANDLE}}) {
	delete $pinheads{$state{HANDLE}};
	$ui->print("($name is no longer a pinhead.)\n");
    } else {
	$pinheads{$state{HANDLE}} = $name;
	$ui->print("($name is now a pinhead.)\n");
    }

    return;
}

sub round {
  return sprintf("%.0f",$_[0]);
}

sub zip_find_candidates {
  my ($message)=@_;
  my @words=();
  my $pos=0;
  for my $word (split(/(\s+)/,$message)) {
      if(length($word)>=2 && 
	 ( $word=~/[a-z]{3,}/ || $word=~/^[A-Z]?[a-z]+/ )) {
	push @words,[$pos,length($word)];
      }
    $pos+=length($word);
  }
  return @words;
}
       
sub zippify {
    my($event, $handler) = @_;
    return unless (defined $pinheads{$event->{SHANDLE}});

    my @candidates=zip_find_candidates($event->{VALUE});
    return unless @candidates;
    my $max_victims=round(@candidates/2+0.5);
    $max_victims>0 or $max_victims=1;
    my $min_victims=round(@candidates/7);
    $min_victims>0 or $min_victims=1;
    my $vict_count=$min_victims+int(rand($max_victims-$min_victims+1));
    for (my $i=0; $i<$vict_count; $i++) {
      my $victim=splice(@candidates,int(rand(@candidates)),1);
      substr($event->{VALUE},$victim->[0],$victim->[1]) =
	uc(substr($event->{VALUE},$victim->[0],$victim->[1]));
    }
    $event->{VALUE}.=" [YOW!]";
    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'before',
	    call  => \&zippify);
    event_r(type  => 'public',
	    order => 'before',
	    call  => \&zippify);
    event_r(type  => 'emote',
	    order => 'before',
	    call  => \&zippify);

    command_r('pinhead' => \&pinhead_command_handler);
    shelp_r('pinhead' => 'Identify a user as a pinhead');
    help_r('pinhead' => "
Usage: %pinhead [user]

The %pinhead command ALTERS THE TEXT of all sends from a user to EMULATE the \
style of Zippy the Pinhead by EMPHASIZING words at RANDOM.  It will append \
\"[YOW!]\" to all sends to remind you that it's turned on.

DISCO OIL bussing will CREATE a throbbing NAUGAHIDE pipeline running \
STRAIGHT to the tropics from the rug producing regions and devalue the \
DOLLAR!
");
} 


1;
