# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/win32speak.pl,v 1.1 2003/02/28 05:15:30 josh Exp $

use strict;

# Josh's experiment in win32 silliness.
#
# based on the example at
#  http://www.winscriptingsolutions.com/Articles/Index.cfm?ArticleID=20796
#
# To use:
#
# %extension load win32speak
# %on <foo> %attr speak 1
# 
# should write some docs, eh?

use Win32::OLE qw( EVENTS );
my $DirectSS = new Win32::OLE( "{EEE78591-FE22-11D0-8BEF-0060081841DE}" );
Win32::OLE->WithEvents( $DirectSS, \&ole_event_handler,
		       "{EEE78597-FE22-11D0-8BEF-0060081841DE}" );
my $tlily_ole_handler = undef;

sub ole_event_handler {
    my ($Obj, $Event, @Args) = @_;
    if ($Event == 4) {
       	if (defined($tlily_ole_handler)) {
	    
	    # we're done talking, so remove the ole hook.
	    # if I felt like being clever, I could re-inject the OLE events
	    # into tlily's event model, and keep the ole hook in place all
	    # the time.  Might be amusing.  Maybe some other time.
	    TLily::Event::idle_u($tlily_ole_handler);
            undef $tlily_ole_handler;
	}	
    }
}

sub sayit {
    my($event, $handler) = @_;

    my $Me =  $event->{server}->user_name();
    
    # don't say anything if we sent the message somewhere.
    return if ($event->{SOURCE} eq $Me && $event->{RECIPS} ne $Me);
    
    # don't say anything unless the "speak" attribute has been set (with %on)
    return unless $event->{speak};
        
    my $message = "From $event->{SOURCE} to $event->{RECIPS}: $event->{VALUE}";
    
    if ($event->{type} eq "emote") {
        $message = "(to $event->{RECIPS}), $event->{SOURCE} $event->{VALUE}";
    }

    # Find a good voice to use.  Note that win2k appears to only come with 
    # one voice (male) anyway, by default.
    #
    # You can get more from http://www.bytecool.com/voices.htm.  I believe only
    # the SAPI4 ones apply to the control we are using.
    
    my $pronoun = $event->{server}->get_pronoun(HANDLE => $event->{SHANDLE});
    my $gender  = ( $pronoun =~ /her/i ? 1 : 2 );
    my $ranklist = "Style=Casual;Gender=$gender";
    my $engine = $DirectSS->Find($ranklist);

#    ui_name()->print("(Using voice '" . $DirectSS->ModeName($engine) . 
#                     "' (voice $engine of " . $DirectSS->CountEngines() . " available))\n");
    
    $DirectSS->Select($engine);
    $DirectSS->Speak($message);

    # we need to ensure that win32::OLE's message loop continues to function
    # until it's done speaking.  Register an idle handler, and then we'll
    # unregister it when the OLE event comes in that tells us it's done 
    # talking.
    
    $tlily_ole_handler = TLily::Event::idle_r(call => sub { 
        Win32::OLE->SpinMessageLoop();
    });
    
    return;
}

sub load {
    event_r(type  => 'private',
	    order => 'after',
	    call  => \&sayit);
    event_r(type  => 'public',
	    order => 'after',
	    call  => \&sayit);
    event_r(type  => 'emote',
	    order => 'after',
	    call  => \&sayit);

}

1;

