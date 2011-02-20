# -*- Perl -*-

use TLily::Version;
use strict;
use warnings;

sub applescript_cmd {
    my $ui = shift;

    return unless @_;  # nothing to do.

    my $cmd = join(" ", grep {defined} @_);

    $cmd =~ s/\\n/\n/g;
    open (my $fh, '|-', 'osascript 2> /dev/null') ;
    print {$fh} $cmd;
    close($fh);

    return;
}

command_r('applescript' => \&applescript_cmd);

shelp_r("applescript" => "Run arbitrary applescript");
help_r("applescript",  <<END
Usage: %applescript "applescript"

No, that's it. run arbitrary applescript. Be very quiet about errors, though.
END
);

1;
