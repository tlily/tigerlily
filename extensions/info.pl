# -*- Perl -*-
# $Id$

use strict;

sub info_cmd {
    my($ui, $args) = @_;
    my ($cmd,$disc) = split /\s+/, $args;
    my $server = active_server();

    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "info",
		       target => $disc,
		       text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(@_);
	};

	$server->fetch(ui     => $ui,
		       type   => "info",
		       target => $disc,
		       call   => $sub);
    }
    elsif ($cmd eq 'edit') {
        # Attempt to recall deadfile
        my $text = get_deadfile("help", $server, "$disc");
        if (!defined($text)) {
            $ui->print("(Unable to recall dead info for \"$disc\": $!)\n");
        } else {
	    edit_text($ui, $text) or return;
            $server->store(ui     => $ui,
                           type   => "info",
                           target => $disc,
                           text   => $text);
        }
    }
    else {
	$server->sendln("/info $args");
    }
}

sub helper_cmd {
    my $ui = shift;
    my ($cmd,@args) = split /\s+/, "@_";
    my $help_str = shift @args;
    my $help_spec = [];

    # Attempt to split out the help spec string.
    goto help_cmd_usage
      unless ($help_str =~ /^(?:(.+)::)?([^:]+)(?::(.+))?$/);

    @{$help_spec} = ($1, $2, $3);

    # Attempt to translate the servername given to a server object, or
    # the current active server if no name is given.
    my $server = active_server();
    $server = TLily::Server::find($help_spec->[0]) if ($help_spec->[0]);
    unless (defined($server)) {
        $ui->print("No such server " . $help_spec->[0] . "\n");
        return 0;
    }
    $help_spec->[0] = $server;


    if ($cmd eq 'set') {
	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "help",
		       target => $help_spec->[1],
		       name   => $help_spec->[2],
		       text   => \@text);
    }
    elsif ($cmd eq 'diff' || $cmd eq 'copy') {
        my $help2_str = shift @args;
        my $help2_spec = [];

        # Attempt to split out the help spec string.
        goto help_cmd_usage
          unless ($help2_str =~ /^(?:(.+)::)?([^:]+)(?::(.+))?$/);

        @{$help2_spec} = ($1, $2, $3);

        # Attempt to translate the servername given to a server object, or
        # the current active server if no name is given.
        my $server = active_server();
        $server = TLily::Server::find($help2_spec->[0]) if ($help2_spec->[0]);
        unless (defined($server)) {
            $ui->print("No such server " . $help2_spec->[0] . "\n");
            return 0;
        }
        $help2_spec->[0] = $server;

        # Make sure the two help specs aren't identical.
        if ($help_spec->[0] eq $help2_spec->[0] &&
            $help_spec->[1] eq $help2_spec->[1] &&
            $help_spec->[2] eq $help2_spec->[2]) {
            $ui->print("(source and destination are the same)\n");
            return 0;
        }
        help_diff($cmd, $ui, $help_spec, $help2_spec) if ($cmd eq 'diff');
        help_copy($cmd, $ui, $help_spec, $help2_spec) if ($cmd eq 'copy');
    }
    elsif ($cmd eq 'reedit') {
        # Attempt to recall deadfile
        my $text = get_deadfile("help", $server, join(':', @{$help_spec}[1..2]));
        if (!defined($text)) {
            $ui->print("(Unable to recall dead help for \", join(':', @{$help_spec}[1..2]), \": $!)\n");
        } else {
	    edit_text($ui, $text) or return;
	    $server->store(ui     => $ui,
		           type   => "help",
		           target => $help_spec->[1],
		           name   => $help_spec->[2],
		           text   => $text);
        }
    }
    elsif ($cmd eq 'edit') {
	my $sub = sub {
	    my(%args) = @_;
        $args{text} = [ grep {! /^\/#/} @{$args{text}} ]; # strip comments
        $args{text} = [ grep {! /^?sethelp/} @{$args{text}} ]; # strip ?sethelp

	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(%args);
	};

	$server->fetch(ui     => $ui,
		       type   => "help",
		       target => $help_spec->[1],
		       name   => $help_spec->[2],
		       call   => $sub);
    }
    elsif ($cmd eq 'list') {
        if (!defined($help_spec->[1])) {
            $server->sendln("?lsindex")
        } elsif (!defined($help_spec->[2])) {
            $server->sendln("?ls $help_spec->[1]");
        } else {
            $server->sendln("?gethelp $help_spec->[1] $help_spec->[2]");
        }
    }
    elsif ($cmd eq 'clear' && defined($help_spec->[1])) {
        $server->sendln("?rmhelp $help_spec->[1] $help_spec->[2]");
    }
    else {
help_cmd_usage:
        $ui->print("Usage: %helper list [server::]index[:topic]\n");
        $ui->print("       %helper [re]edit [server::]index:topic\n");
        $ui->print("       %helper diff|copy [server::]index:topic [server::]index:topic\n");

    }

}

sub help_copy {
    my ($cmd, $ui, $help1, $help2) = @_;

    my $server1 = $help1->[0];
    my $server2 = $help2->[0];

    my $sub = sub {
        my(%args) = @_;

        if ($args{text}[0] =~ /^\(There is no such help index as/) {
            # Encountered an error.
            $args{ui}->print($args{server} . ": " . $args{text}[0] . "\n");
            return;
        }

        $server2->store(%args,
                        target => $help2->[1],
                        name   => $help2->[2]);
    };

    $ui->print("(Copying help ", scalar $help1->[0]->name, "::", $help1->[1], ":", $help1->[2], " to ", scalar $help2->[0]->name, "::", $help2->[1], ":", $help2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "help",
                    target => $help1->[1],
                    name   => $help1->[2],
                    call   => $sub);

}

sub help_diff {
    my ($cmd, $ui, $help1, $help2) = @_;

    my $server1 = $help1->[0];
    my $server2 = $help2->[0];

    # A callback that will be called by both fetch()'s.  Once it has both
    # helps, it will diff them.  This is a closure so we can preserve the
    # @data array between calls.
    my $subcon = sub {
        my @data = ();
        return sub {
            my(%args) = @_;

            if ($args{text}[0] =~ /^\(There is no such help index as/) {
                # Encountered an error.
                $args{ui}->print($args{server} . ": " . $args{text}[0] . "\n");
                return;
            }

            # Put the text into a buffer.
            if ($args{server} eq $server1 &&
                $args{target} eq $help1->[1] &&
                $args{name}   eq $help1->[2]) {
                $data[0] = $args{text};
            } else {
                $data[1] = $args{text};
            }

            # if we have both helps, do the diff.
            if (defined($data[0]) && defined($data[1])) {
                my $diff = diff_text(@data);

                $ui->print("(no differences found)\n") unless (@{$diff});
                foreach (@{$diff}) { $ui->print($_) };
            }
        }
    };

    my $sub = &$subcon;
    $ui->print("(Diffing help ", scalar $help1->[0]->name, "::", $help1->[1], ":", $help1->[2], " against ", scalar $help2->[0]->name, "::", $help2->[1], ":", $help2->[2], ")\n");
    $server1->fetch(ui     => $ui,
                    type   => "help",
                    target => $help1->[1],
                    name   => $help1->[2],
                    call   => $sub);

    $server2->fetch(ui     => $ui,
                    type   => "help",
                    target => $help2->[1],
                    name   => $help2->[2],
                    call   => $sub);

}


sub memo_cmd {
    my($ui, $args) = @_;
    my($cmd,@args) = split /\s+/, $args;
    my $server = active_server();

    my($target, $name);
    if (@args == 1) {
	($name) = @args;
    } else {
	($target, $name) = @args;
    }

    if (!defined ($cmd)) {
	$server->sendln("/memo");
	return;
    }

    if ($cmd eq 'set') {
	if ($name =~ /^\d+$/) {
	    $ui->print("(memo name is a number)\n");
	    return;
	}

	my @text;
	edit_text($ui, \@text) or return;
	$server->store(ui     => $ui,
		       type   => "memo",
		       target => $target,
		       name   => $name,
		       text   => \@text);
    }
    elsif ($cmd eq 'edit') {
	if ($name =~ /^\d+$/) {
	    $ui->print("(you can only edit memos by name)\n");
	    return;
	}

	my $sub = sub {
	    my(%args) = @_;
	    edit_text($args{ui}, $args{text}) or return;
	    $server->store(@_);
	};

	$server->fetch(ui     => $ui,
		       type   => "memo",
		       target => $target,
		       name   => $name,
		       call   => $sub);
    }
    elsif ($cmd eq 'reedit') {
        # Attempt to recall deadfile
        my $text = get_deadfile("help", $server, "$target:$name");
        if (!defined($text)) {
            $ui->print("(Unable to recall dead memo \"$target:$name\": $!)\n");
        } else {
            edit_text($ui, $text) or return;
            $server->store(ui     => $ui,
                           type   => "memo",
                           target => $target,
                           name   => $name,
                           text   => $text);
        }
    }
    else {
	$server->sendln("/memo $args");
    }
}

sub export_cmd {
    my($ui, $args) = @_;
    my @args = split /\s+/, $args;

    my $usage = "(%export [memo] file target; type %help for help)\n";

    # Ugh.  There HAS to be something cleaner than what follows.

    my($type, $file, $target, $name);

    if (@args > 0 && $args[0] eq "memo") {
	$type = "memo";
	shift @args;
    } else {
	$type = "info";
    }

    if (@args < 1) {
	$ui->print($usage); return;
    }
    $file = shift @args;

    if ($type eq "memo") {
	if (@args == 1) {
	    ($name) = @args;
	} elsif (@args == 2) {
	    ($target, $name) = @args;
	} else {
	    $ui->print($usage); return;
	}
    }
    else {
	if (@args == 1) {
	    ($target) = @args;
	} elsif (@args > 0) {
	    $ui->print($usage); return;
	}
    }

    local *FH;
    my $rc = open(FH, '<', $file);
    unless ($rc) {
	$ui->print("(\"$file\": $!)\n");
	return;
    }
    my @text=<FH>;
    chomp(@text);
    close(FH);

    my $server = active_server();
    $server->store(ui     => $ui,
		   type   => $type,
		   target => $target,
		   name   => $name,
		   text   => \@text);
}

command_r('info'   => \&info_cmd);
command_r('helper' => \&helper_cmd);
command_r('memo'   => \&memo_cmd);
command_r('export' => \&export_cmd);
	       
shelp_r("info", "Improved /info functions");
help_r("info", "
%info set  [\<discussion\>]
   - Loads your editor and allows you to set your /info
%info edit [\<discussion\>|\<user\>]
   - Allows you to edit or view (in your editor) your /info, or that of a
     discussion or user.  (a handy way to save out someone's /info to a
     file or to edit a /info)
%info clear [\<discussion\>]
   - Allows you to clear a /info.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");

shelp_r("export", "Export a file to /info");
help_r("export", "
%export \<filename\> [\<discussion\>]
   - Allows you to set a /info to the contents of a file.
%export memo \<filename\> [\<discussion\>] \<memoname\>
   - Allows you to set a memo to the contents of a file.  If a discussion
     name is supplied, will set the memo on that discusion, otherwise, it
     will export to your personal memo pad.
");

shelp_r("memo", "Improved /memo functions");
help_r("memo", "
%memo [\<disc\>|\<user\>] name
   - View a memo \"name\" on your memo pad, or that of a discussion or another
     user.
%memo set [\<disc\>] name
   - Allows you to set a memo \"name\" on your memo pad, or a discussion's
     memo pad.
%memo edit [\<disc\>|\<user\>] name
   - Edit or view (in your editor) one of your memos, or that of a discussion
     or another user (you can only view those of users, of course).
%memo clear [\<disc\>] name
   - Erase a memo.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");


shelp_r("helper", "lily help management functions");
help_r("helper", "
%helper set index:topic[:subtopic]
   - Loads your editor and allows you to write help text for the given topic
     in the given index. 

%helper edit index:topic[:subtopic]
   - Allows you to edit help text for the given topic in the given index. 

%helper reedit index:topic[:subtopic]
   - Recalls a dead help text from a previously failed edit.

%helper clear index:topic[:subtopic]
   - Clears the help text for the given topic in the given index. 

%helper list [index[:topic][:subtopic]]
   - Prints the index list if given no arguments.  Prints the contents of a
     given index, or if and index and topic is given, will print the current
     help text for it.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");

1;
