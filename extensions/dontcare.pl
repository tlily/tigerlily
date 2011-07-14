use strict;

# Author: Almohada (C. Carkner)
# Drop a user's send over a line limit to "...but you don't care."

=head1 NAME

dontcare.pl - Drop a user's send over a line limit to "...but you don't care."

=head1 DESCRIPTION

When loaded, this will chop a user's sends down to "...but you don't care."

=head1 COMMANDS

=over 10

=item %silence

Silences a user.  See "%help silence" for details.

=cut

my %silenced;
my $lines;

sub cmd_handler {
    my($ui, $args) = @_;
    my $server = active_server();
    return unless $server;
    my @args = split /\s+/, $args;

    if (@args == 0) {
      if (scalar(keys(%silenced)) == 0) {
        $ui->print("(no users are being silenced)\n");
      } else {
        $ui->print("(silenced users: ",
                     join(', ', sort values(%silenced)),
                   ")\n");
      }
      return;
    }

    if (@args < 1) {
      $ui->print("(%silence name [lines]; type %help for help)\n");
      return;
    }

    my $tmp = $config{expand_group};

    $config{expand_group} = 1;
    $lines = $args[1];
    my $name = TLily::Server::SLCP::expand_name($args[0]);
    if((!defined $name) || ($name =~ /^-/)) {
        $ui->print("(could find not match to \"$args[0]\")\n");
        return;
    }

    $config{expand_group} = $tmp;
    my @names;
    if(!(@names = split(/,/,$name))) {
        $names[0] = $name;
    }

    foreach my $name (@names) {
        my %state = $server->state(NAME => $name);

        if(!$state{HANDLE}) {
          $ui->print("(could find no match to \"$args[0]\")\n");
          return;
        }

        if(defined $silenced{$state{HANDLE}}) {
          delete $silenced{$state{HANDLE}};
          $ui->print("($name is no longer silenced.)\n");
        } elsif (defined $lines) {
          $silenced{$state{HANDLE}} = $name;
          $ui->print("($name is now silenced.)\n");
        } else {
          $ui->print("($name was not silenced to begin with.)\n");
          return;
        }

    }

    return;
}

sub silencer {
   my($event, $handler) = @_;
   return unless (defined $silenced{$event->{SHANDLE}});

   # Dirty dirty hack.  I'm so ashamed.
   my $lncnt = length($event->{VALUE})/72;

   if($lncnt >= $lines) {
     $event->{VALUE} =~ s/^(.*?[\\\?\\\!\\\.]+).*/$1/g;
     $event->{VALUE} .= " ...but you don't care.";
   }
   return;
}

sub load {
   event_r(type  => 'private',
           order => 'before',
           call  => \&silencer);
   event_r(type  => 'public',
           order => 'before',
           call  => \&silencer);
   event_r(type  => 'emote',
           order => 'before',
           call  => \&silencer);

   command_r('silence' => \&cmd_handler);
   shelp_r('silence' => 'Shut someone up');
   help_r('silence' => "
Usage: %silence [user] [lines]

%silence changes all sends from <user> longer then <lines> lines to
an unimportant phrase.
");
}

1;



