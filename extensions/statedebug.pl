

command_r(statedebug => \&state_cmd);
shelp_r(statedebug => "Debug the SLCP state database");
help_r(statedebug => "

Usage: %statedebug
        %statedebug [HANDLE|NAME KEY]

Examples:
%statedebug DATA whoami
Desired index: \"DATA\", key: \"whoami\"
DATA:
   whoami=#850
%statedebug NAME josh
Desired index: \"NAME\", key: \"josh\"
NAME:
   josh = {
     BLURB=
     HANDLE=#850
     LOGIN=921806974
     NAME=Josh
     STATE=here
   }
%statedebug HANDLE #850
Desired index: \"HANDLE\", key: \"#850\"
HANDLE:
   #850 = {
     BLURB=
     HANDLE=#850
     LOGIN=921806974
     NAME=Josh
     STATE=here
   }
");

sub state_cmd {
    my ($ui,$args) = @_;
    my ($dindex,$dkey) = split /\s+/,$args;
    my ($rec,$index,$key);

    my $server = server_name();

    TLily::Event::keepalive();

    $ui->print("Desired index: \"$dindex\", key: \"$dkey\"\n");

    foreach $index (sort keys %{$server}) {
        if ($dindex && ($index ne $dindex)) { next; }
        $ui->print("$index:\n");
        if (! ref($server->{$index})) {
            $ui->print("   $server->{$index}\n");
        }
        foreach $key (sort keys %{$server->{$index}}) {
            if ($dkey && ($key ne $dkey)) { next; }
            if (! ref($server->{$index}{$key})) {
                $ui->print("   $key=$server->{$index}{$key}\n");
            } else {
                $ui->print("   $key = {\n");
                $rec = $server->{$index}{$key};
                foreach (sort keys %{$rec}) {
                    $ui->print("     $_=$rec->{$_}\n");
                }
                $ui->print("   }\n");
            }
        }
    }

    TLily::Event::keepalive(5);
}
