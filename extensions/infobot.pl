use TLily::Bot custom;

# untar a copy of http://www.infobot.org/src/infobot-0.45.3.tar.gz 
# under your extensions directory for this to work.
my $INFOBOT_BASEDIR = "$::TL_EXTDIR/infobot-0.45.3";

# try to make the paths canonical.
use Cwd;
if ($INFOBOT_BASEDIR !~ /^\//) {
   $INFOBOT_BASEDIR = getcwd() . "/$INFOBOT_BASEDIR";
}

if (! -f "$INFOBOT_BASEDIR/infobot") {
    die "Infobot installation was not found at $INFOBOT_BASEDIR\n";    
}

use vars qw(%param $filesep);
use strict;

# since we are single threaded and infobot won't pass around tlily events 
# internally, use a file global to store the server object so we send our
# replies to the proper place.
my $last_server;

# keep track of whether the last send was an emote, so we can tack on a '"'
my $is_emote = 0;

infobot_init();

event_r(type => 'private',
	call => sub {
	    my($event, $handler) = @_;	
	    my $message = $event->{VALUE};
	    my $sender  = $event->{SOURCE};
	    $sender  =~ s/\s/_/g;
	    
	    $param{'nick'} = $event->{server}->user_name();
	    $last_server = $event->{server};
	    
	    TLily::Event::keepalive(0);
	    
	    channel("");	    
	    my $result = process($sender, "private", $message);
	    &status("[$sender] $message");
	    status("   => [$result]") if ($result);
	    
	    TLily::Event::keepalive(5);
	    
	    return 0;
	});

event_r(type => 'emote',	
	call => sub {
	    my($event, $handler) = @_;	
	    my $message = $event->{VALUE};
	    my $sender  = $event->{SOURCE};
	    $sender  =~ s/\s/_/g;
	    
	    $is_emote = 1;

	    if ($message =~ /^ . o O \((.*)\)$/) {
		$message = $1;
	    } elsif ($message =~ /^ (asks|says), \"(.*)\"$/) {		
		$message = $2;
	    } else {
	        $message = "$sender$message";	
            }
	    
	    $param{'nick'} = $event->{server}->user_name();
	    $last_server = $event->{server};
	    	  		
	    my $recips = $event->{RECIPS};
	    $recips =~ s/\s/_/g;
		
	    TLily::Event::keepalive(0);
		
	    channel($recips);
	    my $result = process($sender, "public", $message);
	    status("<$sender/$recips> $message");
	    status("   => [$result]") if ($result);

	    TLily::Event::keepalive(5);

	    return 0;
	});

event_r(type => 'public',
	call => sub {
	    my($event, $handler) = @_;	
	    my $message = $event->{VALUE};
	    my $sender  = $event->{SOURCE};
	    $sender  =~ s/\s/_/g;
	    
	    $is_emote = 0;
	    
	    $param{'nick'} = $event->{server}->user_name();
	    $last_server = $event->{server};
	    	   
	    my $recips = $event->{RECIPS};
	    $recips =~ s/\s/_/g;
	    
	    TLily::Event::keepalive(0);
	    
	    channel($recips);
	    my $result = process($sender, "public", $message);
	    status("<$sender/$recips> $message");
	    status("   => [$result]") if ($result);

	    TLily::Event::keepalive(5);
	    
	    return 0;
	});


sub infobot_init {
    $filesep = "/";
    $param{'basedir'}  = $INFOBOT_BASEDIR;
    $param{'confdir'}  = "$param{basedir}/conf";
    $param{'miscdir'}  = "$param{basedir}/conf";    
    $param{'srcdir'}   = "$param{basedir}/src";
    $param{'extradir'} = "$param{basedir}/extras";
    chdir($param{'basedir'});    
    
    push @INC, $param{'srcdir'};
    
    opendir DIR, $param{'srcdir'}
	or die "can't open source directory $param{srcdir}: $!";

    my $file;
    while ($file = readdir DIR) {
	next unless $file =~ /^[A-Z].*\.pl$/;
	next if ($file =~ /irc|ctcp/i);
	
	require "$param{srcdir}/$file";
    }
    closedir DIR;
    
    # I assure you you do not want to know why I am doing this.
    # (ok, infobot has a home-grown exporter thing and it won't work in an
    #  exosafe as-is)  Note that it IS doing exports and imports from
    # main:: as well, but those won't work.  These should replace those.
    my $this_package = (caller(0))[0];
    Util::import_export('Infobot::DBM', $this_package,
			qw(clear   clearAll closeDBM    closeDBMAll
			   forget  get      getDBMKeys	insertFile
			   openDBM openDBMx postDec	postInc
			   set     showdb   syncDBM     whatdbs));

    Util::import_export($this_package, 'Infobot::DBM',
			qw($filesep %param status));
    
    # patch up some settings which get lost in the import-export mess
    $param{DBMModule}	= 'AnyDBM_File';

    # and put some things into main:: which the "extras" expect.
    # (oy)
    Util::import_export($this_package, 'main', qw(status getparam update));
    
    
    opendir DIR, $param{'extradir'}
	or die "can't open extras directory $param{extradir}: $!";

    while ($file = readdir DIR) {
	next unless $file =~ /\.pl$/;
	require "$param{extradir}/$file";
    }
    closedir DIR;

    # call infobot's function to initialize everything 
    &setup();
}    

# infobot will call these functions (normally they live in the IrcExtras.pl
# file, but we suppressed loading of them above)
my $talkchannel = undef;
sub channel {
    if (scalar(@_) > 0) {
	$talkchannel = $_[0];
	$talkchannel =~ s/ /_/g;	
    }   
    $talkchannel;
}

sub say {
    my ($message) = @_;    
    my $to = channel();

    if ($message =~ /^\cAACTION (.*)/) {
        if ($is_emote) {
 	    status("sending $to;$1");
 	    $last_server->sendln("$to;$1");	   
        } else {
	    status("sending $to;$param{nick} $1");
	    $last_server->sendln("$to;$param{nick} $1");	   	   
        }
	return;
    }
    
    if ($is_emote) {
	status("sending $to;\"$message");
        $last_server->sendln("$to;\"$message");
    } else {
 	status("sending $to;$message");
        $last_server->sendln("$to;$message");	
    }
}

sub msg {
    my ($to, $message) = @_;

    status("sending $to;$message");    
    $last_server->sendln("$to;$message");
}

1;
