# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/set.pl,v 1.4 1999/06/23 14:27:12 neild Exp $

use strict;

sub dumpit {
    my($ui,$l,%H) = @_;
    $l = 0 if ! $l;

    my($k,$v);
    while(($k,$v) = each %H) {
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
    my($ui,$args) = @_;
    (my $name = $args) =~ /[\w\-_]/;
    dumpit($ui, 0, ($name =>$config{$name}));
    return 0;
}

# %unset handler
sub unset_handler($) {
    my($ui,$args) = @_;
    (my $name = $args) =~ /[\w\-_]/;
    delete $config{$name};
    return 0;
}

# %set handler
sub set_handler($) {
    my($ui,$args) = @_;

    $args =~ s/ /=/ if $args !~ m/=/;
    if($args eq '') {
	$ui->print("Config Variables:\n");
	dumpit($ui,0,%config);
	return 0;
    }

    if($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*([^\(\)\s]+)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	if($key) {
	    if(!defined($config{$var}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq '')) {
		$config{$var}{$key} = $val;
	    	dumpit($ui, 0, $var => {$key => $config{$var}{$key}});
	    } else { $ui->print("(Invalid type for variable)\n"); }
	}
	else {
	    if(ref($config{$var}) eq '') {
		$config{$var} = $val;
	    	dumpit($ui, 0, $var => $config{$var});
	    } else { $ui->print("(Invalid type for variable)\n"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*\((\S+)\)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	my @L = split(/\s*,\s*/, $val);
	if($key) {
	    if(!defined($config{$var}) || !defined($config{$var}{$key}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq 'ARRAY')) {
		$config{$var}{$key} = \@L;
	    	dumpit($ui, 0, $var => {$key => $config{$var}{$key}});
	    } else { $ui->print("(Invalid type for variable)\n"); }
	}
	else {
	    if(!defined($config{$var})) {
		$config{$var} = [ @L ];
	    	dumpit($ui, 0, $var => $config{$var});
	    } elsif(!defined($config{$var}) || ref($config{$var}) eq 'ARRAY') {
		$config{$var} = [ @{$config{$var}}, @L ];
	    	dumpit($ui, 0, $var => $config{$var});
	    } else { $ui->print("(Invalid type for variable)\n"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*$/) {
	my($var,$key,$val) = ($1,$2);
	if($key) {
	    dumpit($ui, 0, $var => {$key => $config{$var}{$key}});
	}
	else {
	    dumpit($ui, 0, $var => $config{$var});
	}
    }
    else {
	$ui->print("(Syntax error: see %help set for usage)\n");
    }
    return 0;
}

command_r('show', \&show_handler);
shelp_r('show', "Show the value of a configuration variable");

command_r('unset', \&unset_handler);
shelp_r('unset', "UNset a configuration variable");

command_r('set', \&set_handler);
shelp_r('set', "Set a configuration variable");
help_r('set', qq(usage:
    %set name value
        Sets the scalar config variable [name] to [value].
    %set name (value,value,value)
        Appends the given list to the config variable [name].
    %set name{key} value
        Sets the hash key [key] in the config variable [name] to [value].
    %set name{key} (value,value,value)
        Sets the hash key [key] in the config variable [name] to the given list.
  Examples:
    %set mono 1
        Turns on monochrome mode.  (Also has the side effect of setting the
        colors on your screen to your monochrome preferences.)
    %set slash (also,-oops)
        Adds also and -oops to your \@slash list.  Has the side-effect of
        allowing /also to be intercepted, and disabling /oops from being
        intercepted.
    %set color_attrs{pubmsg} (normal,bg:red,fg:green,bold)
        Sets your color pref. for public messages to black on white & bold.
        (Also has the side effect of changing the color of public messages
        on your screen to those colors)
));

1;
