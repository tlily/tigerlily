#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2001  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

package TLily::Config;

use TLily::ExoSafe;
use Exporter;
#require "TLily/dumpvar.pl";

@ISA = qw(Exporter);
@EXPORT = qw(%config);

my %obj;
my $nextid=1;

sub TIEHASH {
    my $self = shift;

    my $it = {
        LIST => {},
        STORE_CALLBACKS => {},
        FETCH_CALLBACKS => {},
        DELETE_CALLBACKS => {},
    };

    return bless $it, $self;
}

sub FETCH {
    my($self,$key) = @_;
    foreach $tr (@{$self->{FETCH_CALLBACKS}{$key}},
                 @{$self->{FETCH_CALLBACKS}{'-ALL-'}})
    {
        &{$tr->{Call}}($tr, Key => \$key);
    }
    return $self->{LIST}{$key};
}

sub STORE {
    my($self,$key,$val) = @_;
    my $tr;
#    print STDERR "STORE key\n";
#    main::dumpValue($key);
#    print STDERR "STORE val\n";
#    main::dumpValue($val);
    foreach $tr (@{$self->{STORE_CALLBACKS}{$key}},
                 @{$self->{STORE_CALLBACKS}{'-ALL-'}})
    {
        &{$tr->{Call}}($tr, Key => \$key, Value => \$val);
    }
#    print STDERR "STORE key after\n";
#    main::dumpValue($key);
#    print STDERR "STORE val after\n";
#    main::dumpValue($val);
    $self->{LIST}{$key} = $val;
}

sub DELETE {
    my($self,$key) = @_;
    foreach $tr (@{$self->{DELETE_CALLBACKS}{$key}},
                 @{$self->{DELETE_CALLBACKS}{'-ALL-'}})
    {
        &{$tr->{Call}}($tr, Key => \$key);
    }
    delete $self->{LIST}{$key};
}

sub CLEAR {
    my($self) = @_;
    my $k;
    foreach $k (keys %{$self->{LIST}}) {
        $self->DELETE($k);
    }
}

sub EXISTS {
    my($self,$key) = @_;
    return exists $self->{LIST}{$key};
}

sub FIRSTKEY {
    my($self) = @_;
    my $a = keys %{$self->{LIST}}; # Reset each() iterator.

    return each %{$self->{LIST}};
}

sub NEXTKEY {
    my($self,$lkey) = @_;
    return each %{$self->{LIST}};
}

sub DESTROY {
    my($self) = @_;
}

sub callback_r {
    my %args = @_;
    $args{Id} = $nextid++;
    if(!$args{List}) { $args{List} = 'config'; }
    push @{$obj{$args{List}}->{$args{State}."_CALLBACKS"}{$args{Variable}}},
        \%args;
    return $args{Id};
}

sub callback_u {
    1;
#    my $id = @_;
#    my($lst,$mode,$var);
#    foreach $lst (keys %obj) {
#    foreach $mode (qw(STORE FETCH DELETE)) {
#        foreach $var (keys %{$obj{$lst}->{$mode."_CALLBACKS"}}) {
#        print STDERR "remove $id\n";
#        main::dumpValue($obj{$lst}->{$mode."_CALLBACKS"}{$var});
#        @{$obj{$lst}->{$mode."_CALLBACKS"}{$var}} =
#            grep {$_->{Id} != $id} @{$obj{$lst}->{$mode."_CALLBACKS"}{$var}};
#        }
#    }
#    }
}

sub collapse_tr {
    my($tr, %ev) = @_;
#    print STDERR "config(load)\n";
#    main::dumpValue($config{load});
#    print STDERR "collapse ev before\n";
#    main::dumpValue(\%ev);
    ${$ev{Value}} = collapse_list(${$ev{Value}});
#    print STDERR "collapse ev after\n";
#    main::dumpValue(\%ev);
}

sub init {
    $obj{config}      = tie %config, TLily::Config;
    $obj{color_attrs} = tie %color_attrs, TLily::Config;
    $obj{mono_attrs}  = tie %mono_attrs, TLily::Config;
    $config{color_attrs} = \%color_attrs;
    $config{mono_attrs}  = \%mono_attrs;

    callback_r(Variable => 'load',
               List => 'config',
               State => 'STORE',
               Call => \&collapse_tr);
    callback_r(Variable => 'slash',
               List => 'config',
               State => 'STORE',
               Call => \&collapse_tr);

    read_init_files();
    parse_command_line();
}

sub read_init_files {
    my $ifile;

    if($main::TL_LIBDIR !~ m|^//INTERNAL| &&
       ! -f $main::TL_LIBDIR."/tlily.global") {
        print STDERR "Warning: Global configuration file ",
            $main::TL_LIBDIR."/tlily.global", "\nnot found.  ";
        print STDERR "TigerLily may not be properly installed.\n";
        sleep 2;
    }

    foreach $ifile ($main::TL_LIBDIR."/tlily.global",
            $main::TL_ETCDIR."/tlily.site",
            $ENV{HOME}."/.lily/tlily/tlily.cf")
    {
    if($ifile =~ m|^//INTERNAL/| || -f $ifile) {
#        print STDERR "Loading $ifile\n";

        my $safe=new ExoSafe;
        snarf_file($ifile, $safe);

        #local(*stab) = $safe->reval("*::");
        local(*stab) = $safe->symtab;
        my $key;
#        print STDERR "*** Examining ", $safe->root, "\n";
        foreach $key (keys %stab) {
        next if($key =~ /^_/ || $key =~ /::/ || $key eq ENV || $key eq VERSION);
#        print STDERR "KEY: $key\n";
        local *entry = $stab{$key};
        if(defined $entry) {
#            print STDERR "TYPE: SCALAR\n";
            $config{$key} = $entry;
        }
        if(@entry) {
#            print STDERR "TYPE: ARRAY\n";
            if(scalar(@entry) == 1 && !defined $entry[0]) {
                if(not exists $config{$key}) {
                    $config{$key} = [];
                }
            } else {
                if(exists($config{$key})) {
                    $config{$key} = [ @{$config{$key}}, @entry ];
                } else {
                    $config{$key} = \@entry;
                }
            }
        }
        if (%entry) {
#            print STDERR "TYPE: HASH\n";
            my($k);
            foreach $k (keys %entry) {
                $config{$key}->{$k} = $entry{$k};
            }
        }
        }
#        print STDERR "*** Done examining ", $safe->root, "\n";
#        print STDERR "*** \%config after $ifile:\n";
#        main::dumpValue(\%config);
#        print STDERR "*** Done \%config after $ifile\n";
    }
    }
}

sub snarf_file {
    my($filename, $safe) = @_;

    # Copied from Expand.pm
#    if ($Safe::VERSION >= 2) {
#    $safe->deny_only("system");
#    $safe->permit("system");
#    } else {
#    $safe->mask($safe->emptymask());
#    }

    $safe->share_from('main', [ qw(%ENV) ]);

#    print STDERR "*** Pre-Dumping ", $safe->root, "($filename)\n";
#    main::dumpvar($safe->root);
#    print STDERR "*** Done pre-dumping ", $safe->root, "($filename)\n";

    $safe->rdo($filename);
    die "config error: $@" if $@;

#    print STDERR "*** Dumping ", $safe->root, "($filename)\n";
#    main::dumpvar($safe->root);
#    print STDERR "*** Done dumping ", $safe->root, "($filename)\n";
}

sub parse_command_line {
    my ($snrub,$xyzzy);

    while(@ARGV) {
        if($ARGV[0] =~ /^-(H|help|\?)$/) {
            &Usage; exit;
        }
        if($ARGV[0] =~ /^-(h|host|s|server)$/) {
            shift @ARGV; $config{server} = shift @ARGV; next;
        }
        if($ARGV[0] =~ /^-(p|port)$/) {
            shift @ARGV; $config{port} = shift @ARGV; next;
        }
        if($ARGV[0] =~ /^-(m|mono)$/) {
            shift @ARGV; $config{mono} = 1; next;
        }
#    print STDERR "$ARGV[0]\n";
        if($ARGV[0] =~ /^-(\w+)=(\S+)$/) {
            my($var,$val) = ($1,$2);
            $config{$var} = $val;
            shift @ARGV; next;
        }
        if($ARGV[0] =~ /^-(\w+)$/) {
            my($var) = $1;
            $config{$var} = 1;
            shift @ARGV; next;
        }
        else {
            warn "Unknown option: $ARGV[0], skipping.\n";
            shift @ARGV; next;
        }
    }

    if ($config{snrub}) {
        print "Now is the time for all good women to foo their bars at their nation.  Random text is indeed random, and foo bar baz to you and me.  Bizboz, barf, fooble the toys.  Narf.  Feeb.  Frizt the cat.  There is a chair.  Behind the chair is a desk.  Atop the desk is a computer.  Before the computer is a Kosh.  Below the Kosh is a chair.\nPerl is a computer language used by computer geeks, hackers, users, administrators, and other people of all stripes.  It was written by Larry Wall, and has been hacked on by many, many others.  http://www.rpi.edu/~neild/pictures/hot-sex-gif.I-dare-you-to-work-out-how-to-wrap-this\n";
        exit(42);
    }

    if ($config{xyzzy}) {
        print "\nconfig options:\n";

        foreach (keys %config) { print "$_: $config{$_}\n"; }
        exit(0);
    }

}

sub collapse_list {
    my($lref) = @_;
    my($ext,%list);
#    print STDERR "collapse lref\n";
#    main::dumpValue($lref);
    foreach $ext (@{$lref}) {
    next if (! defined($ext));
    if($ext =~ /^-(.*)$/) {
        delete $list{$1};
    } else {
        $list{$ext} = 1;
    }
#    print STDERR "*** interim list ($ext)***\n";
#    print STDERR join(", ",keys(%list)), "\n";
#    print STDERR "*** Done interim list ***\n";
   }
    [keys %list];
}

# Tells the caller whether the named /command can
# be intercepted.
sub ask {
    my($cmd) = @_;
    return (grep($_ eq $cmd, @{$config{slash}}));
}

sub Usage {
    print STDERR qq(
Usage: $0 [-m[ono]] [-zonedelta=<delta>] [-[s]erver servername] [-[p]ort number] [-pager=0|1] [-<configvar>[=<configvalue>]\n
);
}

=head1 NAME

TLily::Config - Configuration Handling

=head1 SYNOPSIS

    use TLily::Config;

    TLily::Config::init();

    $id = TLily::Config::callback_r(State => STORE,
                    Variable => mono,
                                    List => 'config'
                    Call => \&set_colors);

    if(TLily::Config::ask('info')) {
        &do_something();
    }

    if($config{zonedelta} != 0) {
        &do_something_else();
    }

=head1 DESCRIPTION

The Config module is responsible for reading and holding all the user
preferences of the tigerlily session.

=head2 Configuration Files

Configiration files are perl code.  After evaluation, all variables set
in a configuration file are added as elements of the %config hash.

=over 10

=item Global

The global configuration file is where all the defaults for all features are
stored.  This should only be edited when new features requiring a new config
option are needed, or when the default settings for a feature are changed.

Default Location: /usr/local/lib/tlily/tlily.global

=item Site

The site configuration file is where the local sysadmin should put settings
which should override/augment the global defaults for all the users at their
site.

Default Location: /usr/local/etc/tlily.site

=item User

The user configuration file is where each user can put settings which should
override/augment the global and site configuration.

Default Location: \$HOME/.lily/tlily/tlily.cf

=item Command Line

The last place which can override config options is the command line.  See
F<The Command Line> below for more information.

=back

=head2 The Command Line

Convenience options like [CB]<-p> for [CB]<-port> and [CB]<-s> for
[CB]<-server> are special-cased in parse_command_line().  When adding a new
config option, if -foo should set $config{foo}, do not add any code to
parse_command_line(); it will be handled by the catch-all case which
turns [CB]<-foo> into $config{foo} = 1 and [CB]<-foo=bar> into
$config{foo} = bar.

=head1 BUGS

You can not currently remove a config callback.

=cut


1;
