package TLily::UI::ReadLine;

use strict;
use vars qw(@ISA %commandmap %bindmap);

use TLily::UI;
use Term::ReadLine;
use TLily::Event;

@ISA = qw(TLily::UI); #) cperl mode is getting confused


#
# Use Term::Size to determine the terminal size after a SIGWINCH, but don't
# actually require that it be installed.
#

my $termsize_installed;
my $sigwinch;
my $cols;
my $lines;
BEGIN {
    eval { require Term::Size; import Term::Size; };
    if ($@) {
	warn("*** WARNING: Unable to load Term::Size ***\n");
	$termsize_installed = 0;
	($cols, $lines) = (80, 24);
    } else {
	($cols, $lines) = Term::Size::chars();
	$termsize_installed = 1;
    }
}


sub accept_line {
    my($self, $text) = @_;

    if (@{$self->{prompt}} > 0) {
	my $args = shift @{$self->{prompt}};
	$self->prompt("") if defined ($args->{prompt});

	if ($args->{password}) {
	    $self->password(0) 
	} else {
	    $self->{R}->AddHistory($text);
	}

	$args->{call}->($self, $text);

	if (@{$self->{prompt}} > 0) {
	    $args = $self->{prompt}->[0];
	    $self->prompt($args->{prompt}) if defined ($args->{prompt});
	    $self->password(1) if ($args->{password});
	}

	return;
    }

    $self->{R}->AddHistory($text);

    TLily::Event::send(type => 'user_input',
		       text => $text,
		       ui   => $self);

    return;
}


my $meta = 0;
sub run {
    my($self) = @_;

    while ($sigwinch) {
        $sigwinch = 0;
        if ($termsize_installed) {
	    ($cols, $lines) = Term::Size::chars();
        }
    }

    my $c = $self->{R}->read_key();
    my $ctrl;
    my $key;
    if ($c == 27) {
	$meta = 1;
	return;
    }

    if ($c >= 128) {
	$c -= 128;
	$meta = 1;
    }

    if ($c <= 31) {
	$c += 96;
	$ctrl = 1;
    }

    $key = ($ctrl ? "C-" : "") . ($meta ? "M-" : "") . chr($c);

    my $cmd = $self->{bindings}->{$key};
    if ($cmd && $self->{command}->{$cmd}) {
	$self->command($cmd, $key);
	return;
    }

    $c -= 96 if ($ctrl);
    $c += 128 if ($meta);
    $ctrl = $meta = 0;

    $self->{R}->stuff_char($c);
    $self->{R}->callback_read_char();
    return;
}


sub new {
    my $proto = shift;
    my %arg   = @_;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    bless($self, $class);

    $| = 1;

    $self->{R} = Term::ReadLine->new('tlily');

    if ($self->{R}->ReadLine() !~ /Gnu/) {
	warn "
WARNING: At present, the ReadLine UI requires Term::ReadLine::Gnu.
         You have " . $self->{R}->ReadLine() . " installed.  This may not work.
         If you have multiple Term::ReadLine modules installed, you may
         specify which module to use by setting the PERL_RL environment
         variable.\n\n";
    }

    $self->{R}->callback_handler_install("", sub { $self->accept_line(@_) });

    $self->{prompt}   = [];
    $self->{command}  = {};
    $self->{bindings} = {};
    $self->{printed}  = 0;

    TLily::Event::io_r(handle => \*STDIN,
		       mode   => 'r',
		       obj    => $self,
		       call   => \&run);

    $self->inherit_global_bindings();

    return $self;
}


sub prompt_for {
    my($self, %args) = @_;
    croak("required parameter \"call\" missing.") unless ($args{call});

    push @{$self->{prompt}}, \%args;
    return if (@{$self->{prompt}} > 1);

    $self->prompt($args{prompt}) if (defined $args{prompt});
    $self->password(1) if ($args{password});
    return;
}


sub needs_terminal {
    1;
}


sub suspend {
    my($self) = @_;
}


sub resume {
    my($self) = @_;
}


sub defstyle {
    my($self, $style, @attrs) = @_;
}


sub defcstyle {
    my($self, $style, $fg, $bg, @attrs) = @_;
}


sub clearstyle {
    my($self) = @_;
}


sub style {
    my($self, $style) = @_;
}


sub indent {
    my $self = shift;
}


sub print {
    my $self = shift;
    print @_;
    $self->{printed} = 1;
};


sub redraw {
    my($self) = @_;
    return 1;
}


sub command_r {
    my($self, $command, $func) = @_;
    $self->{command}->{$command} = $func;
    return 1;
}


sub command_u {
    my($self, $command) = @_;
    delete $self->{command}->{$command};
    return 1;
}


sub bind {
    my($self, $key, $command) = @_;
    if ($command eq "insert-self") {
	delete $self->{bindings}->{$key};
    } else {
	$self->{bindings}->{$key} = $command;
    }
    return 1;
}


sub intercept_r {
    my($self, $name) = @_;
    return 1;
}


sub intercept_u {
    my($self, $name) = @_;
    return 1;
}


sub command {
    my($self, $command, $key) = @_;
    return unless ($self->{command}->{$command});
    $self->{printed} = 0;
    my $rc = eval { $self->{command}->{$command}->($self, $command, $key); };
    warn "Command \"$command\" caused error: $@" if ($@);
    $self->{R}->on_new_line() if ($self->{printed});
    return $rc;
    $self->{R}->call_function($command, 1, $key);
}


sub password {
    my($self, $password) = @_;
}


sub prompt {
    my($self, $prompt) = @_;
    $self->{R}->callback_handler_install($prompt,
					 sub { $self->accept_line(@_) });
}


sub page {
    my $self = shift;
}


sub define {
    my($self, $name, $pos) = @_;
}


sub set {
    my($self, $name, $val) = @_;
}


sub get_input {
    my($self) = @_;
    my $attr = $self->{R}->Attribs;
    return ($attr->{point}, $attr->{line_buffer});
}


sub set_input {
    my($self, $point, $line) = @_;
    my $attr = $self->{R}->Attribs;
    #print "set: $point '$line'\n";
    $self->{R}->modifying(0, $attr->{end});
    ($attr->{point}, $attr->{line_buffer}) = ($point, $line);
}


sub istyle_fn_r {
    my($self, $style_fn) = @_;
}


sub istyle_fn_u {
    my($self, $style_fn) = @_;
}


sub bell {
    my($self) = @_;
    $self->{R}->ding();
}

1;
