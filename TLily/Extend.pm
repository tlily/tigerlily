#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/Extend.pm,v 1.19 2001/01/26 03:01:48 neild Exp $ 

package TLily::Extend;
use strict;
use vars qw(%config);

use TLily::ExoSafe;
use TLily::Config qw(%config);
use TLily::Registrar;
use TLily::User  qw(&help_r &shelp_r &command_r);
use TLily::Event qw(&event_r &event_u);
use TLily::Utils qw(&edit_text &diff_text &columnize_list);

my %extdata;
my %extensions = ();
my @share=qw(%config &help_r &shelp_r &command_r &event_r &event_u 
	     &ui_name &active_server &edit_text &diff_text &columnize_list);

=head1 NAME

TLily::Extend - Tigerlily Extension Manager

=head1 SYNOPSIS

     
use TLily::Extend;

=head1 DESCRIPTION

This module manages tigerlily extensions.  Tigerlily attempts to isolate
extensions using the ExoSafe module to give each a separate namespace.  In
addition, all handlers registered by an extension are tracked by the Registrar
and can be unregistered automatically if the extension is unloaded.

=head1 FUNCTIONS

=over 10

=cut

=item init()

  TLily::Extend::init();

=cut

sub init {
    TLily::User::command_r(extension => \&extension_cmd);
    TLily::User::shelp_r  (extension => "manage tlily extensions");
    TLily::User::help_r   (extension => "
usage: %extension list
       %extension load <extension>
       %extension unload <extension>
       %extension reload <extension>
");
}

=item load()

Loads an extension into tlily.

  TLily::Extend::load($name,$ui,$verbose);

Extensions are executed in a restricted environment called an ExoSafe.
This means that each one gets its own package, so they don't step on each 
other.   For convenience, each ExoSafe is exported a number of functions so
that they don't have to be typed out fully (for example, you can type shelp_r() instead of having to type TLily::User::shelp_r()).

For a list of the exported functions and variables, see @share in Extend.pm.

=cut

sub load {
    my ($name, $ui, $verbose)=@_;
    my $filename;
    
    if ($name =~ m|/| && -f $name) {
	$filename = $name;
	# $name = basename($name);
	$name =~ s|.*[/\\]||;
	$name =~ s|\.pl$||i;
    }
    
    if (defined $extensions{$name}) {
	$ui->print("(extension \"$name\" already loaded)\n") if ($ui);
	return 1;
    }

    if (!defined($filename)) {
	my @ext_dirs = ("$ENV{HOME}/.lily/tlily/extensions",
			$main::TL_EXTDIR);
	my $dir;
	foreach $dir (@ext_dirs) {
	    if (-f "${dir}/${name}.pl" || $dir =~ m|^//INTERNAL|) {
		$filename = "${dir}/${name}.pl";
		last;
	    }
	}
    }
    
    if (!defined($filename)) {
	$ui->print("(cannot locate extension \"$name\")\n") if ($ui);
	return 0;
    }
    
    $ui->print("(loading \"$name\" from \"$filename\")\n")
      if ($ui && $verbose && defined($filename));

    my $reg  = TLily::Registrar->new($name)->push_default;
    my $safe = ExoSafe->new;
    
    $safe->share(@share);
    # This only works in perl 5.003_07+
    $safe->share_from('main', [ qw(%ENV %INC @INC $@ $] $$) ]);
    
    $safe->rdo($filename);
    unless ($@) {
	$safe->reval("load();");
	$@ = undef if ($@ && $@ =~ /Undefined subroutine \S+load /);
    }
    
    $reg->pop_default;
    
    if ($@) {
	$ui->print("* error: $@") if ($ui);
	$reg->unwind;
	return 0;
    }
    
    $extensions{$name} = { file => $filename,
			   safe => $safe,
			   reg  => $reg };
    return 1;
}


=item unload()

Unloads a loaded extension.

  TLily::Extend::unload($name,$ui,$verbose);

=cut

sub unload {
    my($name, $ui, $verbose) = @_;
    
    if (!defined $extensions{$name}) {
	$ui->print("(extension \"$name\" is not loaded)\n") if ($ui);
	return; 
    }
    
    $ui->print("(unloading \"$name\")\n") if ($ui && $verbose);
    $extensions{$name}->{reg}->push_default;
    $extensions{$name}->{safe}->reval("unload();");
    $extensions{$name}->{reg}->pop_default;
    
    $extensions{$name}->{reg}->unwind;
    
    delete $extensions{$name};
}


=item load_extensions()

Loads all extensions listed in the $config{load} array.

  TLily::Extend::load_extensions($ui);

=cut
sub load_extensions {
    my($ui) = @_;
    my $ext;
    foreach $ext (@{$config{'load'}}) {
	load($ext,$ui);
    }   
    
    extension_cmd($ui,"list");
}


=head1 HANDLERS

=item extension_cmd()

Command handler for the %extension command.  Allows the user to load, unload,
and reload extensions.

=cut

sub extension_cmd {
    my($ui, $args) = @_;
    my @argv = split /\s+/, $args;
    
    my $cmd = shift @argv || "";
    
    if ($cmd eq 'load') {
	my $ext;
	foreach $ext (@argv) {
	    load($ext,$ui,1);
	}
    } elsif ($cmd eq 'unload') {
	my $ext;
	foreach $ext (@argv) {
	    unload($ext,$ui,1);
	}
    } elsif ($cmd eq 'reload') {
	my $ext;
	foreach $ext (@argv) {
	    if ($extensions{$ext}) {
		my $f = $extensions{$ext}->{file};
		unload($ext, $ui);
		load($f, $ui, 1);
	    } else {
		load($ext, $ui, 1);
	    }
	}
    } elsif ($cmd eq 'list') {
	$ui->print("(Loaded extensions: ");
	$ui->print(join(" ", sort keys %extensions));
	$ui->print(")\n");
    } else {
	$ui->print
	  ("(unknown %extension command: see %help extension)\n");
    }
}

# Convenience functions for the extensions
sub ui_name {
    TLily::UI::name(@_);
}

sub active_server {
    TLily::Server::active(@_);
}

1;

