# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/program.pl,v 1.6 1999/09/20 02:02:53 mjr Exp $

$perms = undef;

use Data::Dumper;

sub edit_text {
    my($ui, $text) = @_;

    local(*FH);
    my $tmpfile = "/tmp/tlily.$$";
    my $mtime = 0;

    unlink($tmpfile);
    if (@{$text}) {
        open(FH, ">$tmpfile") or die "$tmpfile: $!";
        foreach (@{$text}) { chomp; print FH "$_\n"; }
        $mtime = (stat FH)[10];
        close FH;
    }

    $ui->suspend;
    TLily::Event::keepalive();
    system($config{editor}, $tmpfile);
    TLily::Event::keepalive(5);
    $ui->resume;

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
        $ui->print("(edit buffer file not found)\n");
        return;
    }  

    if ((stat FH)[10] == $mtime) {
        close FH;
        unlink($tmpfile);
        $ui->print("(file unchanged)\n");
        return;
    }  

    @{$text} = <FH>;
    chomp(@{$text});
    close FH;
    unlink($tmpfile);

    return 1;
}

sub verb_set(%) {
  my %args=@_;
  my $verb_spec=$args{'verb_spec'};
  my $edit=$args{'edit'};
  my $ui = $args{'ui'};

  my $tmpfile = "/tmp/tlily.$$";

  if ($edit) {
    edit_text($ui, $args{'data'}) or return;
  }

  # If the server detected an error, try to save the verb to a dead file.
  my $id = event_r(type => 'text', order => 'after',
          call => sub {
              my($event,$handler) = @_;
              if ($event->{text} =~ /^Verb (not )?programmed\./) {
                event_u($handler);
                my $deadfile = $ENV{HOME}."/.lily/tlily/dead.verb.$verb_spec";
                unlink($deadfile);
                if ($1) {
                  local *DF;
                  my $rc = open(DF, ">$deadfile");
                  if (!$rc) {
                      $ui->print("(Unable to save verb: $!)\n");
                      return 0;
                  }

                  foreach my $l (@{$args{'data'}}) {
                      print DF $l, "\n";
                  }
                  $ui->print("(Saved verb to dead.verb.$verb_spec)\n");
                }
                unlink($tmpfile);
              }
              return 0;
          }
        );
  $server->sendln("\@program $verb_spec");
  foreach (@{$args{'data'}}) { chomp; $server->sendln($_) }
  $server->sendln(".");
}

sub verb_list {
  my $ui = shift;
  my $obj = shift;
  my $verb = shift;

  unless (defined($obj)) {
    $ui->print("Usage: %verb list (object):(verb)\n");
    return 0;
  }

  if (defined($verb)) {
    $server->sendln("\@list $obj:$verb");
  } else {
    cmd_process("\@show $obj", sub {
        my($event) = @_;
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          my $objRef = parse_show_obj(@lines);
          if (scalar(@{$objRef->{verbdefs}}) > 0) {
            $ui->print(join("\n", @{columnize_list(@{$objRef->{verbdefs}})},""));
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

sub verb_show {
  my $cmd = shift;
  my $ui = shift;
  my $obj = shift;
  my $verb = shift;

  unless (defined($obj)) {
    $ui->print("Usage: %verb show object[:verb]\n");
    return 0;
  }

  my @lines = ();
  if (defined($verb)) {
    $server->sendln("\@show $obj:$verb");
  } else {
    cmd_process("\@show $obj", sub {
        my($event) = @_;
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          my $objRef = parse_show_obj(@lines);
          if (scalar(@{$objRef->{verbdefs}}) > 0) {
            $ui->print(join("\n", @{columnize_list(@{$objRef->{verbdefs}})},""));
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
  my $cmd = shift;
  my $ui = shift;
  my $obj = shift;

  unless (defined($obj)) {
    $ui->print("Usage: %obj show {object|'master'}\n");
    return 0;
  }

  my @lines = ();

  if ($obj eq 'master') {
    cmd_process("\@show #0", sub {
        my($event) = @_;
        # User doesn't want to see output of @show
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          # We've received all the output from @show. Now call parse_show_obj()
          # to parse the output for @show into something more easily usable.
          my $objRef = parse_show_obj(@lines);
          my @masterObjs = ();

          foreach my $prop (keys %{$objRef->{props}}) {
            push(@masterObjs, "\$$prop") if ($objRef->{props}{$prop} =~ /^#\d+$/);
          }
          $ui->print(join("\n", @{columnize_list(@masterObjs)},""));
        } elsif ( $event->{type} ne 'begincmd' ) {
          my $l = $event->{text};
          if ( $l =~ /^Can\'t find anything named \'$obj\'\./ ) {
            $ui->print("(WARNING: Could not find System Object (#0) - the world is ending.)");
            return 0;
          }
          push @lines, $l;
        }
        return 0;
    });
  } else {
    cmd_process("\@show $obj", sub {
        my($event) = @_;
        # User doesn't want to see output of @show
        $event->{NOTIFY} = 0;
        if ($event->{type} eq 'endcmd') {
          # We've received all the output from @show. Now call parse_show_obj()
          # to parse the output for @show into something more easily usable.
          my $objRef = parse_show_obj(@lines);

          $ui->print("Object: " . $objRef->{objid} .
              (($objRef->{name} ne "")?(" (" . $objRef->{name} . ")\n"):"\n"));
          $ui->print("Parent: " . $objRef->{parentid} .
              (($objRef->{parent} ne "")?(" (" . $objRef->{name} . ")\n"):"\n"));
          $ui->print("Owner: " . $objRef->{ownerid} .
              (($objRef->{owner} ne "")?(" (" . $objRef->{name} . ")\n"):"\n"));
          $ui->print("Flags: " . $objRef->{flags} . "\n");
          $ui->print("Location: " . $objRef->{location} . "\n");
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


sub prop_show {
  my $cmd = shift;
  my $ui = shift;
  my $obj = shift;
  my $prop = shift;

  unless (defined($obj)) {
    $ui->print("Usage: %prop show[all] object[.prop]\n");
    return 0;
  }

  my @lines = ();

  # If $prop is defined, we were given a specific property to look at.  Do so.
  if (defined($prop)) {
    $ui->print("(\@show $obj.$prop)\n");
    $server->sendln("\@show $obj.$prop");
  } else {
    # We need to list the properties on the object.  We will fire off
    # a @show cmd, and process the output to get the info we need.
    cmd_process("\@show $obj", sub {
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
            $ui->print(join("\n", @{columnize_list(@propList)},""));
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

sub columnize_list() {
  my $list = [];
  my $ui_cols = 79;
  my $clen = 0;
  foreach (@_) { $clen = length $_ if (length $_ > $clen); }
  $clen += 2;

  my $cols = int($ui_cols / $clen);
  my $rows = int(@_ / $cols);
  $rows++ if (@_ % $cols);

  my $i;
  for ($i = 0; $i < $rows; $i++) {
    push @{$list},
      sprintf("%-${clen}s" x $cols, map{$_[$i+$rows*$_]} 0..$cols);
  }

  return $list;
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
  my $obj_spec = shift @args;

  # Do a minimal check of the prop spec here.
  unless ($obj_spec =~ /([^\.\:]+)/) {
    $ui->print("Usage: %obj cmd object\n");
    return 0;
  }
  my $obj = $1;

  if ($cmd eq 'show') {
    obj_show($cmd, $ui, $obj);
  } else {
    $ui->print("(unknown %obj command)\n");
  }
}

sub prop_cmd {
  my $ui = shift;
  my ($cmd,@args) = split /\s+/, "@_";
  my $prop_spec = shift @args;

  # Do a minimal check of the prop spec here.
  unless ($prop_spec =~ /([^\.]+)(?:\.(.+))?/) {
    $ui->print("Usage: %prop cmd (object).(verb)\n");
    return 0;
  }
  my $obj = $1;
  my $prop = $2;

  if ($cmd =~ /^show(?:all)?$/) {
    prop_show($cmd, $ui, $obj, $prop);
  } else {
    $ui->print("(unknown %prop command)\n");
  }
}

sub verb_cmd {
  my $ui = shift;
  my ($cmd,@args) = split /\s+/, "@_";
  my $verb_spec = shift @args;

  local $server = server_name();

  # Do a minimal check of the verb spec here.
  unless ($verb_spec =~ /([^:]+)(?::(.+))?/) {
    $ui->print("Usage: %verb cmd (object):(verb)\n");
    return 0;
  }
  my $obj = $1;
  my $verb = $2;

  if ($cmd eq 'show') {
    verb_show($cmd, $ui, $obj, $verb);
  } elsif ($cmd eq 'list') {
    verb_list($ui, $obj, $verb);
  } elsif ($cmd eq 'reedit') {
    my $deadfile = $ENV{HOME}."/.lily/tlily/dead.verb.$verb_spec";
    local *DF;
    my $rc = open(DF, "$deadfile");
    if (!$rc) {
      $ui->print("(Unable to recall verb: $!)\n");
    } else {
      my $lines = [];
      @{$lines} = <DF>;
      close DF;

      verb_set(verb_spec=>$verb_spec,
               data=>$lines,
               edit=>1,
               ui=>$ui);
    }
  } elsif ($cmd eq 'edit') {
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
          @{$args{text}} = ("/* This verb $verb_spec has not yet been written. */");
        }

        verb_set(verb_spec=>$verb_spec,
                 data=>$args{text},
                 edit=>1,
                 ui=>$args{ui});
    };

    $server->fetch(ui     => $ui,
                   type   => "verb",
                   target => $verb_spec,
                   call   => $sub);

  } else {
    $ui->print("(unknown %verb command)\n");
  }
}

# This is a bit nasty.
# We want to figure out whether the user loading this module has
# programmer privs on the server.
# We will be sending an oob command "#$# options +usertype" to get
# the server to tell us what permissions we have.  Unfortunately,
# if you have no special permissions, the server doesn't give you
# an explicit NACK.  Fortunately, it _does_ send an %options line
# immediately afterwards, so also register a handler to look for
# that, and if we encounter that without encountering the %user_type
# line, we know we don't have any privs, and we unload the extension.

$server = server_name();
$ui = ui_name();

$id = event_r(type => 'text', order => 'before',
              call => sub {
                  my($event,$handler) = @_;
                  if ($event->{text} =~ /%user_type ([pah]+)/) {
                    $event->{NOTIFY} = 0;
                    $perms = $1;
                    event_u($handler);
                  }
                  return 1;
              }
      );

event_r(type => 'options',
        call => sub {
            my($event,$handler) = @_;
            event_u($handler);
            event_u($id);
            if (grep(/usertype/, @{$event->{options}})) {
              if (!defined($perms) || $perms !~ /p/) {
                $ui->print("You do not have programmer permissions on this server.\n");
                TLily::Extend::unload("program",$ui,0);
              }
            }
            return 1;
        }
);

$server->sendln("\#\$\# options +usertype");

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
