use strict;
use warnings;

my %map = (
       "a" => "4",
       "b" => "8",
       "d" => "/>",
       "e" => "3",
       "h" => "|-|",
       "i" => "1",
       "k" => "|<",
       "l" => "l",
       "m" => "|\\/|",
       "n" => "|\|",
       "o" => "0",
       "s" => "5",
       "u" => "|_|",
       "v" => "\\/",
       "w" => "\\//",
      );

sub leet_mode {
    my($ui, $command, $key) = @_;

    my($pos, $line) = $ui->get_input;
    return unless (substr($line, 0, $pos) =~ /[;:=]/);

    my $k = $map{lc($key)};
    if (defined $k) {
        for my $k (split //, $k) {
            $ui->command("insert-self", $k);
        }
        return 1;
    }
    return;
}

sub toggle_leet_mode {
    my($ui, $command) = @_;
    #$ui->intercept_u("leet-mode") || $ui->intercept_r("leet-mode");
    if ($ui->intercept_u("leet-mode")) {
        $ui->set(leet => undef);
    } else {
        if ($ui->intercept_r(name => "leet-mode", order => 950)) {
                $ui->define(leet => 'left');
                $ui->set(leet => "L33T");
            } else {
                $ui->style("input_error");
                $ui->print("(cannot start leet-mode in current mode)");
                $ui->style("normal");
            }
    }
    return;
}

TLily::UI::command_r("leet-mode"        => \&leet_mode);
TLily::UI::command_r("toggle-leet-mode" => \&toggle_leet_mode);
TLily::UI::bind("M-l" => "toggle-leet-mode");
shelp_r("toggle-leet-mode" => "Toggle l33t-speak transliteration of input text", "ui_commands");
