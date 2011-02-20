# -*- Perl -*-
# $Id$

use strict;

sub do_source {
    my ($ui,@args) = @_;

    my @args = split(' ',$args[0]);
    if (scalar(@args) == 1) {

        my $fname=$args[0];
        my $i;
        local(*FH);

        return if $fname eq "";

        my $rc = open (FH, '<',  $fname);
        unless ($rc) {
            $ui->print("($fname not found)\n");
            return;
        }

        $ui->print("(sourcing $fname)\n");

        my @data = <FH>;
            close FH;
            process_source(@data);
        return;
    } elsif ($args[0] eq "memo") {
        my $server = TLily::Server->active();
        my %args;
               $args{type} = "memo";
        $args{ui} = $ui;
        $args{name} = $args[-1];
        $args{call} = sub { my %event=@_; process_source(@{$event{text}});};
        if (scalar(@args) == 3 ) {
            $args{target} = $args[1];
        } elsif (scalar(@args) != 2) {
            goto FAIL;
        }
        $server->fetch(%args);
        return;
    }
    FAIL:
    $ui->print("(Bad usage. Try %help source)\n");
    return;
}

sub process_source {
    my(@data) = @_;
    my $size = @data;
    my $ui = TLily::UI->name("main");
    $ui->print("($size lines)\n");

    my $l;
    foreach $l (@data) {
        next if $l =~ /^#/;
        chomp $l;
        TLily::Event::send({type => 'user_input',
                            ui   => $ui,
                            text => $l});
    }
    return;
}

command_r('source' => \&do_source);
shelp_r("source", "Evaluate a file as if entered by the user");
help_r("source", "
%source [file] - Play the file to the client as if it was typed by the user.
%source memo [disc] tagname - Ditto, for memos.
");

1;
