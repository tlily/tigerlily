# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/Attic/icontext.pl,v 1.1 1999/04/05 21:17:53 neild Exp $ 
use strict;

sub next_input_context {
    my($ui, $command, $key) = @_;
    my($pos, $line) = $ui->get_input;
    $ui->{input}->{_context} ||= [];
    my $context = $ui->{input}->{_context};

    my $cidx = $ui->{input}->{_context_idx} || 0;

    if (length $line) {
	$context->[$cidx] = [$pos, $line];
	$cidx++;
	$context->[$cidx] ||= [0, ""];
    }
    else {
	splice(@$context, $cidx, 1);
	$cidx = 0 if ($cidx >= @$context);
    }

    $ui->set_input(@{$context->[$cidx]});
    $ui->{input}->{_context_idx} = $cidx;
}

sub load {
    TLily::UI::command_r("next-input-context" => \&next_input_context);
    TLily::UI::bind("C-x" => "next-input-context");
}
