# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/program.pl,v 1.17.2.1 2000/01/05 10:03:54 mjr Exp $

sub verb_showlist {
    my ($cmd, $ui, $verb_spec) = @_;
    my ($server, $obj, $verb) = @{$verb_spec};

    unless (defined($obj)) {
        $ui->print("Usage: %verb $cmd [server::]object[:verb]\n");
        return 0;
    }

    if (defined($verb)) {
        $server->sendln("\@list $obj:$verb") if ($cmd eq 'list');
        $server->sendln("\@show $obj:$verb") if ($cmd eq 'show');
    } else {
        my @lines = ();
        $server->cmd_process("\@show $obj", sub {
            my($event) = @_;
            $event->{NOTIFY} = 0;
            if ($event->{type} eq 'endcmd') {
                my $objRef = parse_show_obj(@lines);
                if (scalar(@{$objRef->{verbdefs}}) > 0) {
                    $ui->print(join("\n", @{columnize_list($ui, $objRef->{verbdefs})}, ""));
                } else {
                    $ui->print("(No verbs defined on $obj)\n");
                }
            } elsif ( $event->{type} ne 'begincmd' ) {
                my $l = $event->{text};
                if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
                    $event->{NOTIFY} = 1;
                    return 1;
                }
                push @lines, $l;
            }
            return 0;
        });
    }
}

sub obj_show {
  my ($cmd, $ui, $obj_spec) = @_;
  my $master = 0;
  my ($server, $obj) = @{$obj_spec};

  unless (defined($obj)) {
    $ui->print("Usage: %obj show [server::]{object|'master'}\n");
    return 0;
  }

  my @lines = ();

  if ($obj eq 'master') {
    $obj = '#0';
    $master = 1;
  }

  $server->cmd_process("\@show $obj", sub {
      my($event) = @_;
      # User doesn't want to see output of @show
      $event->{NOTIFY} = 0;
      if ($event->{type} eq 'endcmd') {
        # We've received all the output from @show. Now call parse_show_obj()
        # to parse the output for @show into something more easily usable.
        my $objRef = parse_show_obj(@lines);
        if ($master) {
          my @masterObjs = ();

          foreach my $prop (keys %{$objRef->{props}}) {
            push(@masterObjs, "\$$prop") if ($objRef->{props}{$prop} =~ /^#\d+$/);
          }
          $ui->print(join("\n", @{columnize_list($ui, [sort @masterObjs])},""));
        } else {
          $ui->print("Object: " . $objRef->{objid} .
              (($objRef->{name} ne "")?(" (" . $objRef->{name} . ")\n"):"\n"));
          $ui->print("Parent: " . $objRef->{parentid} .
              (($objRef->{parent} ne "")?(" (" . $objRef->{parent} . ")\n"):"\n"));
          $ui->print("Owner: " . $objRef->{ownerid} .
              (($objRef->{owner} ne "")?(" (" . $objRef->{owner} . ")\n"):"\n"));
          $ui->print("Flags: " . $objRef->{flags} . "\n");
          $ui->print("Location: " . $objRef->{location} . "\n");
        }
      } elsif ( $event->{type} ne 'begincmd' ) {
        my $l = $event->{text};
        if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
          $event->{NOTIFY} = 1;
          return 1;
        }
        push @lines, $l;
      }
      return 0;
  });
}

sub prop_show {
  my ($cmd, $ui, $prop_spec) = @_;

  my ($server, $obj, $prop) = @{$prop_spec};

  unless (defined($obj)) {
    $ui->print("Usage: %prop show[all] [server::]object[.prop]\n");
    return 0;
  }

  my @lines = ();

  # If $prop is defined, we were given a specific property to look at.  Do so.
  if (defined($prop)) {
    $server->sendln("\@show $obj.$prop");
  } else {
    # We need to list the properties on the object.  We will fire off
    # a @show cmd, and process the output to get the info we need.
    $server->cmd_process("\@show $obj", sub {
        my($event) = @_;
        # User doesn't want to see output of @show
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          # We've received all the output from @show. Now call parse_show_obj()
          # to parse the output for @show into something more easily usable.
          my $objRef = parse_show_obj(@lines);

          # OK - now to make a list of properties.  We have two lists to
          # choose from: properties directly defined on the object, or
          # all properties (including inherited ones).
          my @propList = ();
          if ($cmd eq 'show') {
            @propList = sort(@{$objRef->{propdefs}});
          } elsif ($cmd eq 'showall') {
            # User wants inherited properties too.
            @propList = sort(keys %{$objRef->{props}});
          }
          if (scalar(@propList) > 0) {
            $ui->print(join("\n", @{columnize_list($ui, \@propList)},""));
          } else {
            $ui->print("(No properties on $obj)\n");
          }
        } elsif ( $event->{type} ne 'begincmd' ) {
          my $l = $event->{text};
          if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
            $event->{NOTIFY} = 1;
            return 1;
          }
          push @lines, $l;
        }
        return 0;
    });
  }
}

sub parse_show_obj(@) {
  my $obj = {};

  foreach $l (@_) {
    chomp $l;
    if ( $l =~ /^Object ID:\s*(#\d+)/ ) {
      $obj->{objid} = $1;
    } elsif ( $l =~ /^Name:\s*(.*)/ ) {
      $obj->{name} = $1;
    } elsif ( $l =~ /^Parent:\s*([^\(]*)\s+\((#\d+)\)/ ) {
      $obj->{parent} = $1;
      $obj->{parentid} = $2;
    } elsif ( $l =~ /^Location:\s*(.*)/ ) {
      $obj->{location} = $1;
    } elsif ( $l =~ /^Owner:\s*([^\(]*)\s+\((#\d+)\)/ ) {
      $obj->{owner} = $1;
      $obj->{ownerid} = $2;
    } elsif ( $l =~ /^Flags:\s*(.*)/ ) {
      $obj->{flags} = $1;
    } elsif ( $l =~ /^Verb definitions:/ ) {
      $mode = "verbdef";
    } elsif ( $l =~ /^Property definitions:/ ) {
      $mode = "propdef";
    } elsif ( $l =~ /^Properties:/ ) {
      $mode = "prop";
    } elsif ( $l =~ /^\s+/g ) {
      if ($mode eq "verbdef") {
        $l =~ /\G(.+)$/g;
        push @{$obj->{verbdefs}}, $1;
      } elsif ($mode eq "propdef") {
        $l =~ /\G(.+)$/g;
        push @{$obj->{propdefs}}, $1;
      } elsif ($mode eq "prop") {
        $l =~ /\G([^:]+):\s+(.*)$/g;
        $obj->{props}{$1} = $2;
      }
    }
  }
  return $obj;
}

sub obj_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my $obj_str = shift @args;
    my $obj_spec = [];

    # Attempt to split out the obj spec string.
    unless ($obj_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+|master)$/i) {
      $ui->print("Usage: %obj cmd [server::]{object|'master'}\n");
      return 0;
    }
    @{$obj_spec} = ($1, $2);

    # Attempt to translate the servername given to a server object, or
    # the current active server if no name is given.
    my $server = TLily::Server::active();
    $server = TLily::Server::find($obj_spec->[0]) if ($obj_spec->[0]);
    unless (defined($server)) {
        $ui->print("No such server \"" . $obj_spec->[0] . "\"\n");
        return 0;
    }
    $obj_spec->[0] = $server;

    if ($cmd eq 'show') {
        obj_show($cmd, $ui, $obj_spec);
    } else {
        $ui->print("(unknown %obj command)\n");
    }
}

sub prop_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my ($prop_str, $prop_val) = shift @args;

    # Attempt to split out the obj spec string.
    if ($prop_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^.]+)(?:\.(.+))?$/) {
        @{$prop_spec} = ($1, $2, $3);

        # Attempt to translate the servername given to a server object, or
        # the current active server if no name is given.
        my $server = TLily::Server::active();
        $server = TLily::Server::find($prop_spec->[0]) if ($prop_spec->[0]);
        unless (defined($server)) {
            $ui->print("No such server \"" . $prop_spec->[0] . "\"\n");
            return 0;
        }
        $prop_spec->[0] = $server;

        if ($cmd =~ /^show(?:all)?$/) {
            prop_show($cmd, $ui, $prop_spec);
        } elsif ($cmd =~ /^set$/) {
            if (defined($prop_spec->[2]) && defined($prop_val)) {
                $server->sendln("\@eval " . join(".", @{$prop_spec}[1..2])
                                . " = $prop_val");
            } else {
                $ui->print("Usage: %prop set object.prop moo-value\n");
            }
        } else {
            $ui->print("(unknown %prop command)\n");
        }
    } else {
        $ui->print("Usage: %prop set [server::]object.prop moo-value\n") if ($cmd eq 'set');
        $ui->print("Usage: %prop show[all] [server::]object.prop\n") if ($cmd ne 'set');
    }
    return 0;
}

sub verb_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my $verb_str = shift @args;
    my $verb_spec = [];

    # Attempt to split out the verb spec string.
    goto verb_cmd_usage
      unless ($verb_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+)(?::(.+))?$/);

    @{$verb_spec} = ($1, $2, $3);

    # Attempt to translate the servername given to a server object, or
    # the current active server if no name is given.
    my $server = TLily::Server::active();
    $server = TLily::Server::find($verb_spec->[0]) if ($verb_spec->[0]);
    unless (defined($server)) {
        $ui->print("No such server " . $verb_spec->[0] . "\n");
        return 0;
    }
    $verb_spec->[0] = $server;

    if ($cmd eq 'show' || $cmd eq 'list') {
        verb_showlist($cmd, $ui, $verb_spec);
    } elsif ($cmd eq 'diff' || $cmd eq 'copy') {
        my $verb2_str = shift @args;
        my $verb2_spec = [];
        my $server = TLily::Server::active();

        # Attempt to split out the verb spec string.
        goto verb_cmd_usage
          unless ($verb2_str =~ /^(?:(.+)::)?(\#\-?\d+|\$[^:]+)(?::(.+))?$/);
      
        # Attempt to translate the servername given to a server object, or
        # the current active server if no name is given.
        @{$verb2_spec} = ($1, $2, $3);
        $server = TLily::Server::find($verb2_spec->[0]) if ($verb2_spec->[0]);
        unless (defined($server)) {
            $ui->print("No such server " . $verb2_spec->[0] . "\n");
            return 0;
        }
        $verb2_spec->[0] = $server;

        # Make sure the two verb specs aren't identical.
        if ($verb_spec->[0] eq $verb2_spec->[0] &&
            $verb_spec->[1] eq $verb2_spec->[1] &&
            $verb_spec->[2] eq $verb2_spec->[2]) {
            $ui->print("(source and destination verbs are the same verb)\n");
            return 0;
        }
        verb_diff($cmd, $ui, $verb_spec, $verb2_spec) if ($cmd eq 'diff');
        verb_copy($cmd, $ui, $verb_spec, $verb2_spec) if ($cmd eq 'copy');
    } elsif ($cmd eq 'reedit') {
        my $verbstr = join(":", @{$verb_spec}[1..2]);

        # Attempt to recall deadfile
        my $text = get_deadfile("help", $server, "$verbstr");
        if (!defined($text)) {
            $ui->print("(Unable to recall dead verb \"$verbstr\": $!)\n");
        } else {
            # Got the file, fire up the editor.
            map { s|^\s*"(.*)";\s*$|/\*$1\*/|; $_; } @$text;
            edit_text($ui, $text) or return;
            map { s|^\s*/\*(.*)\*/\s*$|"$1";|; $_; } @$text;

            # Done editing, save.
            $server->store(ui     => $ui,
                           type   => "verb",
                           target => $verb_spec->[1],
                           name   => $verb_spec->[2],
                           text   => $text);
        }
    } elsif ($cmd eq 'edit') {
        # Set up the callback that will check for errors and fire up the
        # editor if we managed to get the verb.
        my $sub = sub {
            my(%args) = @_;

            if (($args{text}[0] =~ /^That object does not define that verb\.$/) ||
              ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
                # Encountered an error.
                $args{ui}->print($args{text}[0] . "\n");
                return;
            } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
                # Verb exists, but there's no code for it yet.
                # We'll provide a comment saying so as the verb code.
                @{$args{text}} =
                    ("/* This verb $verb_str has not yet been written. */");
            }

            map { s|^\s*"(.*)";\s*$|/\*$1\*/|; } @{$args{'text'}};
            edit_text($ui, $args{'text'}) or return;
            map { s|^\s*/\*(.*)\*/\s*$|"$1";|; } @{$args{'text'}};
            $server->store(%args);
        };

        # Now try to fetch the verb.
        $server->fetch(ui     => $ui,
                       type   => "verb",
                       target => $verb_spec->[1],
                       name   => $verb_spec->[2],
                       call   => $sub);

    } else {
verb_cmd_usage:
        $ui->print("Usage: %verb show|list [server::]object[:verb]\n");
        $ui->print("       %verb [re]edit [server::]object:verb\n");
        $ui->print("       %verb copy|diff [server::]object:verb [server::]object:verb\n");
    }
    return 0;
}


sub verb_copy {
    my ($cmd, $ui, $verb1, $verb2) = @_;

    my $server1 = $verb1->[0];
    my $server2 = $verb2->[0];

    my $sub = sub {
        my(%args) = @_;

        if (($args{text}[0] =~ /^That object does not define that verb\.$/)
             || ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
            # Encountered an error.
            $args{ui}->print($args{server}->name . ": " . $args{text}[0] . "\n");
            return;
        } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
            # Verb exists, but there's no code for it yet.
            # We'll provide a comment saying so as the verb code.
            @{$args{text}} = ();
        }

        $server2->store(%args, 
                        target => $verb2->[1],
                        name   => $verb2->[2]);
    };

    $ui->print("(Copying verb ", scalar $verb1->[0]->name, "::", $verb1->[1], ":", $verb1->[2], " to ", scalar $verb2->[0]->name, "::", $verb2->[1], ":", $verb2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb1->[1],
                    name   => $verb1->[2],
                    call   => $sub);

}

sub verb_diff {
    my ($cmd, $ui, $verb1, $verb2) = @_;

    my $server1 = $verb1->[0];
    my $server2 = $verb2->[0];

    # A callback that will be called by both fetch()'s.  Once it has both
    # verbs, it will diff them.  This is a closure so we can preserve the
    # @data array between calls.
    my $subcon = sub {
        my @data = ();
        return sub {
            my(%args) = @_;

            if (($args{text}[0] =~ /^That object does not define that verb\.$/)
              || ($args{text}[0] =~ /^Invalid object \'.*\'\.$/)) {
                # Encountered an error.
                $args{ui}->print($args{server} . ": " . $args{text}[0] . "\n");
                return;
            } elsif ($args{text}[0] =~/^That verb has not been programmed\.$/) {
                # Verb exists, but there's no code for it yet.
                # We'll blank out the error message.
                @{$args{text}} = "";
            }

            # Put the text into a buffer.
            if ($args{server} eq $server1 &&
                $args{target} eq $verb1->[1] &&
                $args{name}   eq $verb2->[2]) {
                $data[0] = $args{text};
            } else {
                $data[1] = $args{text};
            }

            # if we have both verbs, do the diff.
            if (defined($data[0]) && defined($data[1])) {
                my $diff = diff_text(@data);

                $ui->print("(no differences found)\n") unless (@{$diff});
                foreach (@{$diff}) { $ui->print($_) };
            }
        }
    };

    my $sub = &$subcon;
   
    $ui->print("(Diffing verb ", scalar $verb1->[0]->name, "::", $verb1->[1], ":", $verb1->[2], " against ", scalar $verb2->[0]->name, "::", $verb2->[1], ":", $verb2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb1->[1],
                    name   => $verb1->[2],
                    call   => $sub);

    $server2->fetch(ui     => $ui,
                    type   => "verb",
                    target => $verb2->[1],
                    name   => $verb2->[2],
                    call   => $sub);

}

command_r('verb', \&verb_cmd);
command_r('prop', \&prop_cmd);
command_r('obj', \&obj_cmd);

shelp_r("verb", "MOO verb manipulation functions");
shelp_r("prop", "MOO property manipulation functions");
shelp_r("obj", "MOO object manipulation functions");

help_r("verb", "
%verb show <obj>           - Lists the verbs defined on an object.
%verb show <obj>:<verb>    - Shows a verb's properties.
%verb list <obj>           - Lists the verbs defined on a object.
%verb list <obj>:<verb>    - Lists the code of a verb.
%verb edit <obj>:<verb>    - Edit a verb.
%verb reedit <obj>:<verb>  - Recalls a \"dead\" verb from a failed edit.

");

help_r("prop", "
%prop show <obj>            - Lists the properties defined on a object.
%prop show <obj>:<prop>     - Shows a property.
%prop showall <obj>         - Lists the properties defined on a object,
                              including inherited properties.
%prop showall <obj>:<prop>  - Shows the property.

");

help_r("obj", "
%obj show <obj>     - Shows the base info on the given object.
%obj show master    - Lists the master objects.

");

1;
