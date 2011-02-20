# -*- Perl -*-

use strict;

sub uitest_command {
    my($ui, $args) = @_;

    my $text = <<END ;
(The following assumes an 80-character display.)

This is a rather long line which will word wrap with a single word flush against the right margin.  The next line (this one) should not begin with a space.

This is another long line.  This one tests the ability to consume spaces         properly.  There should be one space at the start of the line.
END
    $ui->print($text);

    $ui->print("Several newlines.\n");
    $ui->print("\n" x ($args || 1));

    $ui->indent("> ");
    $ui->print("This is a test.  We need a rather long line which will wrap around several times, in order to check to see if everything is working properly.  Is this long enough?  Yes, I think it is.\n");
    $ui->indent("");
    $ui->print("ok?\n");
}

sub style_fn {
    my($text) = @_;
    my @f;

    pos($text) = 0;
    if ($text =~ /\G([^\s;:]*[;:])/gc) {
        push @f, length($1), "input_dest";
    }

    while ($text =~ /\G(.*?)(foo)/g) {
        push @f, length($1), "input_window", length($2), "input_foo";
    }

    #print STDERR "style_fn: @f\n";
    return @f;
}

sub load {
    TLily::User::command_r(uitest => \&uitest_command);

    my $ui = TLily::UI::name();
    $ui->defstyle(input_dest => 'bold');
    $ui->defstyle(input_foo  => 'reverse');
    $ui->defcstyle(input_dest => 'white', 'black', 'reverse');
    $ui->defcstyle(input_foo  => 'white', 'black', 'reverse');
    TLily::UI::istyle_fn_r(\&style_fn);
}
