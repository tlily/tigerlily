# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/program.pl,v 1.1 1999/09/19 06:17:28 mjr Exp $

use File::Copy 'cp';
use Data::Dumper;

$perms = undef;

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
                if ($1) {
                  my $deadfile = $ENV{HOME}."/.lily/tlily/dead.verb";
                  local *DF;
                  my $rc = open(DF, ">$deadfile");
                  if (!$rc) {
                      $ui->print("(Unable to save verb: $!)\n");
                      return 0;
                  }

                  foreach my $l (@{$args{'data'}}) {
                      print DF $l, "\n";
                  }
                  $ui->print("(Saved verb to dead.verb)\n");
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

  if (scalar(@_) != 1) {
    $ui->print("Usage: %verb list (object):(verb)\n");
    return 0;
  }

  my $verb_spec = shift;

  # Do a minimal check of the verb spec here.
  unless ($verb_spec =~ /[^:]+:.+/) {
    $ui->print("Usage: %verb list (object):(verb)\n");
    return 0;
  }

  $server->sendln("\@list $verb_spec");
}

sub verb_cmd {
  my $ui = shift;
  my ($cmd,@args) = split /\s+/, "@_";
  my $verb_spec = shift @args;

  local $server = server_name();

  # Do a minimal check of the verb spec here.
  unless ($verb_spec =~ /[^:]+:.+/) {
    $ui->print("Usage: %verb $cmd (object):(verb)\n");
    return 0;
  }

  if ($cmd eq 'list') {
    verb_list($ui, $verb_spec, @args);
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
    $ui->print("(perms = $perms)\n");
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

shelp_r("verb", "MOO verb manipulation functions");
help_r("verb", "
%verb list <verb_spec>    - Lists a verb.
%verb edit <verb_spec>    - Edit a verb.

");


1;
