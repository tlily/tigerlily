use strict;

my $help = <<END
#(Warning: This is a work in progress, and not ready for prime time.)
#
#The 'cformat' extension allows the format of sends to be controlled without
#writing code.  The 'public_fmt', 'private_fmt', and 'emote_fmt' configuration
#variables contain strings defining how to format messages.
#
#It is also possible to specify the format via the "format" attribute of
#an event.  For example:
#  %on public to tigerlily %attr format "TL| %From>%| %Body\\\\n"
#
#The current implementation of %set does not allow you to assign values
#with spaces to a variable, so you will need to use %eval to modify these
#variables.  For example:
#  %eval $config{emote_fmt} = '%[> ]%(Server )(to %To) %From%|%Body\\n';
#
#The following codes may be used in a format:
#  %[ ]     Set the indentation string.
#  %Var     Insert a variable.
#  %{Var}   Insert a variable.
#  %(Var)   Insert a variable, surrounded by parenthesis.
#  %|       Indicate the end of the header, and the start of the body.
#  \\n       Newline.
#
#When a variable is surrounded by brackets (%{Var} or %(Var)), the brackets
#may also contain non-alphabetic text.  This text will be printed only if
#the variable is set.  For example, %(Time ) will expand to "(12:00 )" if
#the Time variable is set, and "" otherwise.
#
#Available variables are:
#  %Server  The server the send was made to.  Set only if there is more than
#           one server.
#  %Time    The current time.  Set only if the message timestamp was set.
#  %From    The sender.
#  %Blurb   The sender's blurb.
#  %To      The destination.
#  %Body    The message body.
#
#The default formats are:
#  public:
#    \\n%[ -> ]%(Server )%(Time )From %From%{ FromBlurb}, to %To:%|
#    %[ - ]\\n%Body\\n
#  private:
#    \\n%[ -> ]%(Server )%(Time )Private message from %From%{ FromBlurb}:%|
#    %[ - ]\\n%Body\\n
#  emote:
#    %[> ]%(Server )(to %To) %From%|%Body\\n
END
  ;
$help =~ s/^\#//gm;
help_r("cformat" => $help);

sub timestamp {
    my ($time) = @_;
    
    my ($min, $hour) = (localtime($time))[1,2];
    my $t = ($hour * 60) + $min;
    my $ampm = '';
    $t += $config{zonedelta} if defined($config{zonedelta});
    $t += (60 * 24) if ($t < 0);
    $t -= (60 * 24) if ($t >= (60 * 24));
    $hour = int($t / 60);
    $min  = $t % 60;
    if (defined($config{zonetype}) and ($config{zonetype} eq '12')) {
        if ($hour >= 12) {
            $ampm = 'p';
            $hour -= 12 if $hour > 12;
        } else {
            $ampm = 'a';
        }
    }
    return sprintf("%02d:%02d%s", $hour, $min, $ampm);
}

# 09:22 mellon This is really much better

sub generic_fmt {
    my($ui, $e) = @_;

    my %vars;
    my %fmts;
    my $fmt;

    if (defined $e->{format}) {
	    $fmt = $e->{format};
    } elsif ($e->{type} eq 'public') {
	    $fmt = $config{public_fmt} || 
	      '\n%[ -> ]%(Server )%(Time )From %From%{ Blurb}, to %To:%|'.
		'%[ - ]\n%Body\n';
    } elsif ($e->{type} eq 'private') {
	    $fmt = $config{private_fmt} || 
	      '\n%[ -> ]%(Server )%(Time )'.
		'Private message from %From%{ Blurb}:%|'.
		'%[ - ]\n%Body\n';
    } elsif ($e->{type} eq 'emote') {
	    $fmt = $config{emote_fmt} ||
	      '%[> ]%(Server )(to %To) %From%|%Body\n';
    }


    $fmts{server} = $e->{server_fmt} || "$e->{type}_server";
    $fmts{header} = $e->{header_fmt} || "$e->{type}_header";
    $fmts{from}   = $e->{sender_fmt} || "$e->{type}_sender";
    $fmts{to}     = $e->{dest_fmt}   || "$e->{type}_dest";
    $fmts{body}   = $e->{body_fmt}   || "$e->{type}_body";
    my $default = $fmts{header};

    $vars{server} = $e->{server}->name()
      if (scalar(TLily::Server::find()) > 1);
    $vars{time} = timestamp($e->{TIME})
      if ($e->{STAMP});
    $vars{from} = $e->{SOURCE};
    $vars{blurb} = $e->{server}->get_blurb(HANDLE => $e->{SHANDLE});
    if (defined $vars{blurb} && $vars{blurb} ne "") {
	    $vars{blurb} = "[" . $vars{blurb} . "]";
    } else {
	    undef $vars{blurb};
    }
    $vars{to} = $e->{RECIPS};
    $vars{body} = $e->{VALUE};

    while (pos($fmt) < length($fmt)) {
	    if ($fmt =~ /\G \\n/xgc) {
		    $ui->print("\n");
	    }

	    elsif ($fmt =~ /\G \\(.?)/xgc) {
		    $ui->print($1) if defined($1);
	    }

	    elsif ($fmt =~ /\G %(\() ([^\)]*) \)/xgc ||
		   $fmt =~ /\G %(\{) ([^\}]*) \}/xgc ||
		   $fmt =~ /\G %() (\w+)/xgc) {

		    my $type = $1;
		    my $var  = $2;
		    my $prefix;
		    my $suffix;

		    ($prefix, $var, $suffix) = $var =~ /^(\W*)(.*?)(\W*)$/;
		    if ($type eq '(') {
			    $prefix .= "(";
			    $suffix  = ")" . $suffix;
		    }

		    $var = lc($var);

		    if (defined($vars{$var})) {
			    $ui->prints($default                => $prefix,
					$fmts{$var} || $default => $vars{$var},
					$default                => $suffix);
		    }
	    }

	    elsif ($fmt =~ /\G %\| /xgc) {
		    $default = $fmts{body};
	    }

	    elsif ($fmt =~ /\G %\[ ([^\]]*) \]/xgc) {
		    $ui->indent($default => $1);
	    }

	    elsif ($fmt =~ /\G ([^%\\]+)/xgc) {
		    $ui->prints($default => $1);
	    }
    }

    $ui->indent();
}

event_r(type  => 'public',
        call  => sub { $_[0]->{formatter} = \&generic_fmt; return });
event_r(type  => 'private',
        call  => sub { $_[0]->{formatter} = \&generic_fmt; return });
event_r(type  => 'emote',
        call  => sub { $_[0]->{formatter} = \&generic_fmt; return });
