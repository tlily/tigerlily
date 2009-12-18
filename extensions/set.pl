# -*- Perl -*-
# $Id$

use strict;

sub dumpit {
    my($ui,$l,%H) = @_;
    $l = 0 if ! $l;

    my($k,$v);
    foreach $k (sort keys %H) {
	$v = $H{$k};
	if(ref($v) eq '' || ref($v) eq 'SCALAR') {
	    $ui->print("\t"x$l."$k = $v\n");
	}
	if(ref($v) eq 'SCALAR') {
	    $ui->print("\t"x$l."$k = $$v\n");
	}
	elsif(ref($v) eq 'ARRAY') {
	    $ui->print("\t"x$l."$k = ". (join(", ", @$v)) . "\n");
	}
	elsif(ref($v) eq 'HASH') {
	    $ui->print("\t"x$l."$k = HASH\n");
	    dumpit($ui,$l+1,%$v);
	}
    }
}

# %show handler
sub show_handler($) {
  my($ui,$args,$startup) = @_;
  return setter($ui,$args,$startup,'show');
}

# %unset handler
sub unset_handler($) {
  my($ui,$args,$startup) = @_;
  return setter($ui,$args,$startup,'unset');
}

# %set handler
sub set_handler($) {
  my($ui,$args,$startup) = @_;
  return setter($ui,$args,$startup,'set');
}

# setter does the actual work behind %set, %unset, and %show
sub setter {
  my ($ui,$args,$startup,$mode)=@_;
  if($args=~/^\s*(?:([\w-_]+)(?:\{([^{}]+)\})?\s*(?:[ =]\s*(.*?))?)?$/) {
    my ($var,$key,$val)=($1,$2,$3);

    # Only %set takes more than just a variable name, so generate a
    # syntax error if a value is provided for %unset or %show.  Also,
    # %unset can't be called without a variable name, so also give an
    # error if one isn't provided.
    if ((($mode ne 'set') && defined($val)) ||
	(($mode eq 'unset') && !defined($var))) {
      $ui->print("(Syntax error: see \%help $mode for usage)\n");
      return 0;
    }

    if (defined($var)) {  # A variable name was provided

      # Determine if a hash element was selected and if so, validate the key
      my $ishash=defined($key);
      if ($ishash && $key!~/^[\w_]*$/) {
	$ui->print("(Syntax error: invalid characters in hash key)\n");
	return 0;
      }

      # If the user didn't specify a value, print the current value
      if (defined($val)) { # We're setting a variable

	# XXX The value string should really allow more versitle
	#     syntax to permit, for example, leading and trailing
	#     spaces in values, literal commas in list elements, and
	#     special character interpolation.

	# Interpret the value string
	my $islist=0;
	if ($val=~s/^\((.*)\)$/$1/s) { # User is specifying a list
	  # Split the list around the commas and strip leading and trailing
	  # spaces
	  $val=[map {s/^\s*//; s/\s*$//; $_} split(/,/,$val)];
	  $islist=1;
	} # else, User is specifying a scalar value or is unsetting
	
	# Check that the data type of the new value is consistent with the
	# established data type of the config variable
	if (defined($config{$var})) {
	  # Check that if the user says the variable is a hash, it is, or
	  # if the user says it's not, it's not.  Or something.
	  # Then, see if the existing value is or is not a list.
	  # (Here's where it all gets a bit tangled...)
	  if ($ishash) {
	    if (ref($config{$var}) ne 'HASH') {
	      $ui->print("(Type mismatch: Config variable is not a hash.  ",
			 "See \%help $mode)\n");
	      return 0;
	    }
	    if (defined($config{$var}) && defined($config{$var}->{$key})) {
	      if ((ref($config{$var}->{$key}) eq 'ARRAY')!=$islist) {
		$ui->print("(Type mismatch: Config variable's value is ",
			   ($islist?"":"not "),
			   "a list.  See \%help $mode)\n");
		return 0;
		# (You following all this?)
	      }
	    }
	  } else {
	    if (ref($config{$var}) eq 'HASH') {
	      $ui->print("(Type mismatch: Config variable is a hash.  ",
			 "See \%help $mode)\n");
	      return 0;
	    }
	    if ((ref($config{$var}) eq 'ARRAY')!=$islist) {
	      $ui->print("(Type mismatch: Config variable's value is ",
			 ($islist?"":"not "),
			 "a list.  See \%help $mode)\n");
	      return 0;
	    }
	  }
	}

	# Okay, it's finally time to actually set the variable
	if ($ishash) {
	  $config{$var}->{$key}=$val;
	} else {
	  $config{$var}=$val;
	}

	# The important work is now done.  If we exit here, we're good
	# to go.  If we don't leave here, the next chunk of code will
	# print the current (new) value.  We decide whether to return
	# or not based on whether we're running interactively or from
	# a script and, if the former, based on a user preference.
	return(0) if ($startup || !$config{set_echo});

      } elsif ($mode eq 'unset') { # We're unsetting a variable

	my $reason;
	if (defined($config{$var})) {
	  if ($ishash) { # Deleting a hash member
	    if (ref($config{$var}) eq 'HASH') {
	      delete($config{$var}->{$key});
	      $reason="$var\{$key} deleted";
	    } else {
	      $ui->print("(Type mismatch: Config variable is not a hash.  ",
			 "See \%help $mode)");
	      return 0;
	    }
	  } else { # Deleting a variable	      
	    delete($config{$var});
	    $reason="$var deleted";
	  }
	} else {
	  $reason="Variable $var does not exist";
	}

	# We only print the result when running interactively and only
	# when the user has set $config{set_echo} to true
	$ui->print($reason,"\n") if (!$startup && $config{set_echo});
	return 0;

      }

      # Print the current value of a variable
      if (defined($config{$var})) {
	if (ref($config{$var}) eq 'HASH') {  # Variable contains a hash
	  if (defined($key)) {  # Printing a single hash value
	    if (defined($config{$var}->{$key})) {
	      dumpit($ui, 0, $var => {$key => $config{$var}->{$key}});
	    } else {
	      $ui->print("$var\{$key} not defined.\n");
	    }
	  } else {  # Printing all the hash's values
	    dumpit($ui, 0, $var => $config{$var});
	  }
	} else {  # Variable contains a scalar or list
	  dumpit($ui, 0, $var => $config{$var});
	}
      } else {
	$ui->print("$var not defined.\n");
      }
      return 0;
	
    } else { # No variable was specified, print them all
      $ui->print("Config Variables:\n");
      dumpit($ui,0,%config);
      return 0;
    }
  }
  $ui->print("(Syntax error: see \%help $mode for usage)\n");
  return 0;
}
shelp_r("set_echo" => "Boolean keeping %set quiet or not", "variables");

command_r('show', \&show_handler);
shelp_r('show', "Show the value of a configuration variable");
help_r('show', qq(usage:
    %show
        Lists all config variables and their values.
    %show name
        Lists the value of the config variable named [name].
    %show name{key}
        Lists the value of the hash element identified by [key] in the config
        variable named [name].
));

command_r('unset', \&unset_handler);
shelp_r('unset', "UNset a configuration variable");
help_r('unset', qq(usage:
    %unset name
        Unsets the config variable named [name].
    %unset name{key}
        Removes the key [key] from the hash config variable [name].
));

command_r('set', \&set_handler);
shelp_r('set', "Set a configuration variable");
help_r('set', qq(usage:
    %set name value
        Sets the scalar config variable named [name] to [value].
    %set name (value,value,value)
        Sets the list config variable named [name] to the given list.
    %set name{key} value
        Sets the hash key [key] in the config variable [name] to [value].
    %set name{key} (value,value,value)
        Sets the hash key [key] in the config variable [name] to the given
        list.
Examples:
    %set mono 1
        Turns on monochrome mode.  (Also has the side effect of setting the
        colors on your screen to your monochrome preferences.)
    %set slash (also,-oops)
        Sets your \@slash list to also and -oops.  Has the side-effect of
        allowing /also to be intercepted, and disabling /oops from being
        intercepted.
    %set color_attrs{pubmsg} (normal,bg:red,fg:green,bold)
        Sets your color pref. for public messages to black on white & bold.
        (Also has the side effect of changing the color of public messages
        on your screen to those colors)
));

1;
