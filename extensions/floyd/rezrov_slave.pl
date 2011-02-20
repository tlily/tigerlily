#!/usr/local/bin/perl -w
#
# $Id$
#
# This file is derived from the rezrov test.pl script.  The original
# copyright message follows:
#
# rezrov: a pure perl z-code interpreter; test script
#
# Copyright (c) 1998, 1999 Michael Edmonson.  All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#

# standard modules:
use strict;
use 5.005;
$|=1;

# local modules:
use Games::Rezrov::StoryFile;
use Games::Rezrov::ZInterpreter;
use Games::Rezrov::ZOptions;
use Games::Rezrov::ZConst;
use ZIO_Slave;

my %FLAGS;

#
#  Figure out name of storyfile
#
my $storyfile = $ARGV[0] || "HITCHHIK.DAT";

die sprintf 'File "%s" does not exist.' . "\n", $storyfile
  unless (-f $storyfile);

#
#  Initialize selected i/o module
#
my $zio;

$zio = new ZIO_Slave(%FLAGS);

my $story;

my $cleanup = sub {
  $zio->set_game_title(" ") if $story->game_title();
  #    $zio->fatal_error("Caught signal @_.");
  $zio->cleanup();
  exit 1;
};

$SIG{"INT"} = $cleanup;
$SIG{"PIPE"} = $cleanup;

Games::Rezrov::ZOptions::GUESS_TITLE(0) unless $zio->can_change_title();

#
#  Initialize story file
#
$story = new Games::Rezrov::StoryFile($storyfile, $zio);
Games::Rezrov::StoryFile::font_3_disabled(1) if $FLAGS{"no-graphics"};
my $z_version = Games::Rezrov::StoryFile::load(1);


$zio->set_version(($z_version <= 3 ? 1 : 0));

Games::Rezrov::StoryFile::setup();

#
#  Start interpreter
#
my $zi = new Games::Rezrov::ZInterpreter($zio);

exit(0);
