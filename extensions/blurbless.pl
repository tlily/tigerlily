# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/blurbless.pl,v 1.1 2000/02/15 00:06:58 tale Exp $

use strict;

my $saw_blurb_prompt_text;

if ($config{enter_blurbless}) {
    event_r(type => 'text',
            order => 'before',
            call => \&text_handler);

    event_r(type => 'prompt',
            order => 'before',
            call => \&prompt_handler);
}

sub text_handler {
    my($event, $handler) = @_;

    if ($event->{text} =~ /^Please enter a blurb, or hit <enter> for none$/) {
        $saw_blurb_prompt_text = 1;
        event_u($handler);
        return 1;
    }

    return;
}

sub prompt_handler {
    my($event, $handler) = @_;

    if ($event->{text} =~ /^--> $/ && $saw_blurb_prompt_text) {
        ui_name()->print("(entering without a blurb)\n");
        $event->{server}->send("\n");
        $saw_blurb_prompt_text = 0;
        event_u($handler);
        return 1;
    }
}
