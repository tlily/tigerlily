use strict;
use warnings;

=head1 NAME

blurbless.pl - Be a blurbless git

=head1 DESCRIPTION

Put this extension in your extension autoload list (See "%help variables
load") if you want to enter lily without a blurb, and you're too lazy to
press return at the blurb prompt.  Be sure to set enter_blurbless to true.

=head1 CONFIGURATION

=over 10

=item enter_blurbless

If true, and the extension is in your autoload list, when connecting to
a lily server, tlily will skip the blurb prompt, entering you without a
blurb.

=cut

# ' This comment with the single quote is here merely to let cperl work again.

shelp_r('enter_blurbless' => 'Whether or not to enter blurbless', 'variables');
help_r('variables enter_blurbless' => q{
If set to true, and blurbless.pl is in your extension autoload list (See
"%help variables load"), when connecting to a lily server, tlily will
skip the blurb prompt, entering you without a blurb.
});

my $saw_blurb_prompt_text;

event_r(type => 'server_connected',
    order => 'during',
        call => \&connected_handler);

sub connected_handler {
    if ($config{enter_blurbless}) {
        event_r(type => 'text',
                order => 'before',
                call => \&text_handler);

        event_r(type => 'prompt',
                order => 'before',
                call => \&prompt_handler);
    }

    return 0;
}

sub text_handler {
    my($event, $handler) = @_;

    if ($event->{text} =~ /^Please enter a blurb, or hit <enter> for none$/) {
        $saw_blurb_prompt_text = 1;
        event_u($handler);
        return 1;
    }

    return 0;
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

    return 0;
}

1;
