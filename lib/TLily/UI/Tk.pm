# -*- Perl -*-
#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2003  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Id$

package TLily::UI::Tk;

use strict;
use Carp;
use vars qw(@ISA);

use Tk;
use Tk::ROText;
use Tk::Dialog;
use Tk::Font;

use TLily::Config qw(%config);
use TLily::UI;
use TLily::Event;
use TLily::UI::Tk::Event;

@ISA = qw(TLily::UI);

# The default set of mappings from command names to functions.
my %commandmap =
  (
   'accept-line'          => sub { $_[0]->accept_line() },
   'previous-history'     => sub { $_[0]->previous_history() },
   'next-history'         => sub { $_[0]->next_history() },
   'insert-self'          => sub { $_[0]->insert_self($_[2]) },
   'forward-char'         => ['SetCursor', Ev('index','insert+1c')],
   'backward-char'        => ['SetCursor', Ev('index','insert-1c')],
   'forward-word'         => ['SetCursor', Ev('index','insert+1c wordstart')],
   'backward-word'        => ['SetCursor', Ev('index','insert-1c wordstart')],
   'beginning-of-line'    => ['SetCursor', '1.0'],
   'end-of-line'          => ['SetCursor', 'end-1char'],
   'delete-char'          => ['Delete'],
   'backward-delete-char' => ['deleteBefore'],
   'transpose-chars'      => ['Transpose'],

   # replacing the default behavior with sub{1} caused the default
   # behavior, which is occasionally correct, to go away.
   # commenting out kill-line fixes PR#919
   #'kill-line'            => sub { 1 },
   #'backward-kill-line'   => sub { 1 },
   #'kill-word'            => sub { 1 },
   #'backward-kill-word'   => sub { 1 },
   #'yank'                 => sub { 1 },

   'page-up'              => sub {
       $_[0]->{stext}->yview(scroll => -1, "pages") },
   'page-down'            => sub {
       $_[0]->{stext}->yview(scroll =>  1, "pages") },
   'line-up'              => sub {
       $_[0]->{stext}->yview(scroll => -1, "lines") },
   'line-down'            => sub {
       $_[0]->{stext}->yview(scroll =>  1, "lines") },
   'scroll-to-top'        => sub { $_[0]->{text}->see("1.0") },
   'scroll-to-bottom'     => sub { $_[0]->{text}->see("end-1char") },
   'refresh'              => sub { 1 },
   'suspend'              => sub { 1 },
   'noop'                 => ['NoOp'],
  );

# The default set of keybindings.
my %bindmap =
  (
   'Right'	       => 'forward-char',
   'Left'	       => 'backward-char',
   'Up'		       => 'previous-history',
   'Down'	       => 'next-history',
   'Delete'	       => 'delete-char',
   'Return'	       => 'accept-line',
   'BackSpace'	       => 'backward-delete-char',
   'Prior'	       => 'page-up',
   'Next'	       => 'page-down',
   'Control-a'	       => 'beginning-of-line',
   'Control-b'	       => 'backward-char',
   'Control-d'	       => 'delete-char',
   'Control-e'	       => 'end-of-line',
   'Control-f'	       => 'forward-char',
   'Control-h'	       => 'backward-delete-char',
   'Control-k'	       => 'kill-line',
   'Control-l'	       => 'refresh',
   'Control-m'	       => 'accept-line',
   'Control-n'	       => 'next-history',
   'Control-p'	       => 'previous-history',
   'Control-t'	       => 'transpose-chars',
   'Control-u'	       => 'backward-kill-line',
   'Control-v'	       => 'page-down',
   'Control-w'	       => 'backward-kill-word',
   'Control-y'	       => 'yank',
   'Control-z'	       => 'suspend',
   'Meta-b'	       => 'backward-word',
   'Meta-d'	       => 'kill-word',
   'Meta-f'	       => 'forward-word',
   'Meta-v'	       => 'page-up',
   'Meta-bracketleft'  => 'line-up',
   'Meta-bracketright' => 'line-down',
   'Meta-less'	       => 'scroll-to-top',
   'Meta-greater'      => 'scroll-to-bottom',
  );

my %remap =
  (
   nl	     => "Return",
   pageup    => "Prior",
   pagedown  => "Next",
   bs	     => "BackSpace",
   del	     => "Delete",
   up	     => "Up",
   down	     => "Down",
   left	     => "Left",
   right     => "Right",
   "C-i"     => "Tab",
   "<"	     => "less",
   ">"	     => "greater",
   "{"	     => "braceleft",
   "}"	     => "braceright",
   "["	     => "bracketleft",
   "]"	     => "bracketright",
   "("	     => "parenleft",
   ")"	     => "parenright",
   "/"	     => "slash",
   "!"	     => "exclam",
   "@"	     => "at",
   "#"	     => "numbersign",
   "\$"	     => "dollar",
   "%"	     => "percent",
   "^"	     => "asciicircum",
   "&"	     => "ampersand",
   "*"	     => "asterisk",
   "|"	     => "bar",
   "\\"	     => "backslash",
   "'"	     => "apostrophe",
   '"'	     => "quotedbl",
   ";"	     => "semicolon",
   ":"	     => "colon",
   ","	     => "comma",
   "."	     => "period",
   "?"	     => "question",
   "-"	     => "minus",
   "_"	     => "underscore",
   "+"	     => "plus",
   "="       => "equal",
  );

my %color =
  (
   black       => "#000000",
   white       => "#d9d9d9",
   grey        => "#7f7f7f",
   green       => "#00cd00",
   cyan        => "#00cdcd",
   brightgreen => "#00ff00",
   brightcyan  => "#00ffff",
   red         => "#cd0000",
   yellow      => "#ffff00",
   blue        => "#0000ff",
  );

my %font;

my $mainwin;
my $logo;
sub new {
    print STDERR "TLily::Tk::new() called\n" if $config{ui_debug};
    my $proto = shift;
    my %arg   = @_;

    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    bless($self, $class);

    if(defined $mainwin) {
	# "Lister, have you ever been hit over the head with a polo mallet?"
	$self->{toplevel} = $mainwin->Toplevel;
    } else {
	# "OK, you guys got yourself a ship."
	$mainwin = new MainWindow;
	#$logo = $mainwin->Photo(-format => "gif",
	#			 -data   => $image_data);
	$font{normal} = $mainwin->Font(-family => "Courier", -size => 12),
	$font{bold}   = $mainwin->Font(-family => "Courier",
				       -size => 12,
				       -weight => "bold"),
	$font{italic} = $mainwin->Font(-family => "Courier",
				       -size => 12,
				       -slant  => "italic"),
	$font{bold_italic} = $mainwin->Font(-family => "Courier",
					    -size => 12,
					    -weight => "bold",
					    -slant => "italic"),
	$self->{toplevel} = $mainwin;
    }

    $self->{event_core} = new TLily::UI::Tk::Event($mainwin);
    TLily::Event::replace_core($self->{event_core});

    # "I don't know what all this trouble is about,
    #  but I'm sure it must be your fault..."
    $self->{toplevel}->setPalette(background          => $color{black},
				  foreground          => $color{white},
				  highlightColor      => $color{black},
				  highlightBackground => $color{black},
				  insertBackground    => $color{white},
				  selectColor         => $color{grey},
				  selectBackground    => $color{grey},);

    $self->{cur_style} = "normal";
    $self->{indent} = "";
    $self->{page} = 1;
    $self->{styles} = {};

    $self->{history}     = [ "" ];
    $self->{history_pos} = 0;

    $self->{left}     = [];
    $self->{right}    = [];
    $self->{override} = [];
    $self->{var}      = {};
    $self->{left_str} = '';
    $self->{right_str} = '';

    $self->{cols}     = 80;

    $self->{menubar} = $self->{toplevel}->Frame()->pack(-fill => 'x',
							-expand => 0);
    $self->{menu_file} = $self->{menubar}->Menubutton
      (-text      => "File",
       -underline => 0,
       -tearoff   => 0,
       -menuitems =>
       [[Button   => '~Quit',
	 -command => sub { exit }],
       ])->pack(-side => "left");

    $self->{menu_help} = $self->{menubar}->Menubutton
      (-text      => "Help",
       -underline => 0,
       -tearoff   => 0,
       -menuitems =>
       [
	[Button   => '~About',
	 -command => \&about],
       ])->pack(-side => "right");

    $self->{stext} = $self->{toplevel}->Scrolled
      ("ROText",
       -scrollbars   => 'e',
       -font         => $font{normal},
       -takefocus    => 0,
       -setgrid      => 1,
       -insertontime => 0,
       -wrap         => "word",
       -state        => "disabled")->pack(-fill => "both", -expand => 1);

    $self->{text} = $self->{stext}->Subwidget("rotext");


    $self->{status} = $self->{toplevel}->Frame(-bg => $color{blue});

    $self->{status_left} = $self->{status}->Label
      (-textvariable => \$self->{left_str},
       -background   => $color{blue},
       -foreground   => $color{yellow},
       -font         => $font{normal},
       -justify      => "left")->pack(-side   => "left",
				      -expand => 1,
				      -fill => "x",
				      -ipady  => 0,
				      -anchor => 'nw');

    $self->{status_right} = $self->{status}->Label
      (-textvariable => \$self->{right_str},
       -background   => $color{blue},
       -foreground   => $color{yellow},
       -font         => $font{normal},
       -justify      => "right",)->pack(-side => "left",
					-expand => 1,
				      -fill => "x",
					-ipady => 0,
					-anchor => 'ne');

    $self->{entry} = $self->{toplevel}->Frame();

    $self->{input} = $self->{entry}->Text
      (-font	      => $font{normal},
       -height	      => 1,
       -width	      => 80,
       -takefocus     => 1,
       -wrap	      => "word",
       -insertofftime => 0,)->pack(-side => "right",
				   -fill => 'x',
				   -expand => 0,
				   -anchor => "s");

    $self->{entry}->pack(-pady   => 0,
			 -ipady  => 0,
			 -padx   => 0,
			 -ipadx  => 0,
			 -fill   => 'x',
			 -expand => 0,
			 -side   => "bottom",
			 -anchor => "s");

    $self->{status}->pack(-pady   => 0,
			  -ipady  => 0,
			  -padx   => 0,
			  -ipadx  => 0,
			  -fill   => 'x',
			  -expand => 0,
			  -side   => "bottom",
			  -anchor => "s");

    $self->{text}->configure(-state => "normal");
    #$self->{text}->image("create", "1.0", -image => $logo) if !$config{quiet};
    $self->{text}->insert("end", "\n");
    $self->{text}->configure(-state => "disabled");
    $self->{text}->see("end");
    $self->{input}->mark("set", "insert", "0.0");
    $self->{input}->focus();

    $self->{intercept} = undef;

    $self->{prompt}    = undef;

    $self->ui_bindings();
    $self->inherit_global_bindings();

    return $self;
}

sub about {
    $mainwin->Dialog(-title => "About Tigerlily",
                  -text  => qq{Tigerlily $TLily::Version::VERSION\n(C) 1998-2001, The Tigerlily Team\n},
                  -default_button => "Ok",
                  -buttons => ["Ok"])->Show();
                  ###-image => $logo,
}

sub ui_bindings {
    my $self = shift;

    $mainwin->bind(ref $self->{input},'<Meta-B1-Motion>','NoOp');
    $mainwin->bind(ref $self->{input},'<Meta-1>','NoOp');
    $mainwin->bind(ref $self->{input},'<Alt-KeyPress>','NoOp');
    $mainwin->bind(ref $self->{input},'<Escape>','unselectAll');

    $mainwin->bind(ref $self->{input},'<1>',['Button1',Ev('x'),Ev('y')]);
    $mainwin->bind(ref $self->{input},'<B1-Motion>','B1_Motion' ) ;
    $mainwin->bind(ref $self->{input},'<B1-Leave>','B1_Leave' ) ;
    $mainwin->bind(ref $self->{input},'<B1-Enter>','CancelRepeat');
    $mainwin->bind(ref $self->{input},'<ButtonRelease-1>','CancelRepeat');
    $mainwin->bind(ref $self->{input},'<Control-1>',
		   ['markSet','insert',Ev('@')]);
    $mainwin->bind(ref $self->{input},'<Double-1>','selectWord' ) ;
    $mainwin->bind(ref $self->{input},'<Triple-1>','selectLine' ) ;
    $mainwin->bind(ref $self->{input},'<Shift-1>','adjustSelect' ) ;
    $mainwin->bind(ref $self->{input},'<Double-Shift-1>',
		   ['SelectTo', Ev('@'),'word']);
    $mainwin->bind(ref $self->{input},'<Triple-Shift-1>',
		   ['SelectTo', Ev('@'),'line']);

#    $mainwin->bind(ref $self->{input},'<Left>',
#		   ['SetCursor', Ev('index','insert-1c')]);
    $mainwin->bind(ref $self->{input},'<Shift-Left>',
		   ['KeySelect', Ev('index','insert-1c')]);
    $mainwin->bind(ref $self->{input},'<Control-Left>',
		   ['SetCursor', Ev('index','insert-1c wordstart')]);
    $mainwin->bind(ref $self->{input},'<Shift-Control-Left>',
		   ['KeySelect', Ev('index','insert-1c wordstart')]);

#    $mainwin->bind(ref $self->{input},'<Right>',
#		   ['SetCursor', Ev('index','insert+1c')]);
    $mainwin->bind(ref $self->{input},'<Shift-Right>',
		   ['KeySelect', Ev('index','insert+1c')]);
    $mainwin->bind(ref $self->{input},'<Control-Right>',
		   ['SetCursor', Ev('index','insert+1c wordend')]);
    $mainwin->bind(ref $self->{input},'<Shift-Control-Right>',
		   ['KeySelect', Ev('index','insert wordend')]);

#    $mainwin->bind(ref $self->{input},'<Up>',\&previous_history);
    $mainwin->bind(ref $self->{input},'<Shift-Up>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<Control-Up>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<Shift-Control-Up>', 'NoOp');

#    $mainwin->bind(ref $self->{input},'<Down>', [ next_history => $self ]);
    $mainwin->bind(ref $self->{input},'<Shift-Down>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<Control-Down>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<Shift-Control-Down>', 'NoOp');

    $mainwin->bind(ref $self->{input},'<Home>',
		   ['SetCursor','insert linestart']);
    $mainwin->bind(ref $self->{input},'<Shift-Home>',
		   ['KeySelect','insert linestart']);
    $mainwin->bind(ref $self->{input},'<Control-Home>',['SetCursor','1.0']);
    $mainwin->bind(ref $self->{input},'<Control-Shift-Home>',
		   ['KeySelect','1.0']);

    $mainwin->bind(ref $self->{input},'<End>',
		   ['SetCursor','insert lineend']);
    $mainwin->bind(ref $self->{input},'<Shift-End>',
		   ['KeySelect','insert lineend']);
    $mainwin->bind(ref $self->{input},'<Control-End>',
		   ['SetCursor','end-1char']);
    $mainwin->bind(ref $self->{input},'<Control-Shift-End>',
		   ['KeySelect','end-1char']);

#    $mainwin->bind(ref $self->{input}, "<Prior>",
#		   [$stext => "yview", scroll => -1, "pages"]);
    $mainwin->bind(ref $self->{input},'<Shift-Prior>',
		   ['KeySelect',Ev('ScrollPages',-1)]);
    $mainwin->bind(ref $self->{input},'<Control-Prior>',
		   ['xview','scroll',-1,'page']);

#    $mainwin->bind(ref $self->{input}, "<Next>",
#		   [$stext => "yview", scroll =>  1, "pages"]);
    $mainwin->bind(ref $self->{input},'<Shift-Next>',
		   ['KeySelect',Ev('ScrollPages',1)]);
    $mainwin->bind(ref $self->{input},'<Control-Next>',
		   ['xview','scroll',1,'page']);

    $mainwin->bind(ref $self->{input},'<Shift-Tab>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<Control-Tab>','NoOp');
    $mainwin->bind(ref $self->{input},'<Control-Shift-Tab>','NoOp');

    $mainwin->bind(ref $self->{input},'<Control-space>',
		   ['markSet','anchor','insert']);
    $mainwin->bind(ref $self->{input},'<Select>',
		   ['markSet','anchor','insert']);
    $mainwin->bind(ref $self->{input},'<Control-Shift-space>',
		   ['SelectTo','insert','char']);
    $mainwin->bind(ref $self->{input},'<Shift-Select>',
		   ['SelectTo','insert','char']);
    $mainwin->bind(ref $self->{input},'<Control-slash>','selectAll');
    $mainwin->bind(ref $self->{input},'<Control-backslash>','unselectAll');

#    $mainwin->bind(ref $self->{input},'<Control-a>',
#		   ['SetCursor','insert linestart']);
#    $mainwin->bind(ref $self->{input},'<Control-b>',
#		   ['SetCursor','insert-1c']);
#    $mainwin->bind(ref $self->{input},'<Control-e>',
#		   ['SetCursor','insert lineend']);
#    $mainwin->bind(ref $self->{input},'<Control-f>',
#		   ['SetCursor','insert+1c']);
#    $mainwin->bind(ref $self->{input},'<Meta-b>',
#		   ['SetCursor','insert-1c wordstart']);
#    $mainwin->bind(ref $self->{input},'<Meta-f>',
#		   ['SetCursor','insert wordend']);
#    $mainwin->bind(ref $self->{input},'<Meta-less>',
#		   [$text => "see", "1.0"]);
#    $mainwin->bind(ref $self->{input},'<Meta-greater>',
#		   [$text => "see", "end"]);

#    $mainwin->bind(ref $self->{input},'<Control-n>',
#		   ['SetCursor',Ev('UpDownLine',1)]);
#    $mainwin->bind(ref $self->{input},'<Control-p>',
#		   ['SetCursor',Ev('UpDownLine',-1)]);

    $mainwin->bind(ref $self->{input},'<2>',
		   ['Button2',Ev('x'),Ev('y')]);
    $mainwin->bind(ref $self->{input},'<B2-Motion>',
		   ['Motion2',Ev('x'),Ev('y')]);
    $mainwin->bind(ref $self->{input},'<ButtonRelease-2>','ButtonRelease2');

    $mainwin->bind(ref $self->{input},'<Destroy>','Destroy');

    $mainwin->bind(ref $self->{input}, '<3>',
		   ['PostPopupMenu', Ev('X'), Ev('Y')]  );

    $mainwin->bind(ref $self->{input},'<Tab>', 'insertTab');
    $mainwin->bind(ref $self->{input},'<Control-i>', 'NoOp');
#    $mainwin->bind(ref $self->{input},'<Return>', ['Insert',"\n"]);
#    $mainwin->bind(ref $self->{input},'<Delete>','Delete');
#    $mainwin->bind(ref $self->{input},'<BackSpace>','Backspace');
    $mainwin->bind(ref $self->{input},'<Insert>', \&ToggleInsertMode ) ;
    $mainwin->bind(ref $self->{input},'<KeyPress>',['InsertKeypress',Ev('A')]);

    $mainwin->bind(ref $self->{input},'<F1>', \&about);
    $mainwin->bind(ref $self->{input},'<F2>', 'NoOp');
    $mainwin->bind(ref $self->{input},'<F3>', 'NoOp');
#    $mainwin->bind(ref $self->{input},'<Control-d>',['delete','insert']);
    $mainwin->bind(ref $self->{input},'<Control-k>','deleteToEndofLine') ;#kill
    $mainwin->bind(ref $self->{input},'<Control-o>','NoOp');
#    $mainwin->bind(ref $self->{input},'<Control-t>','Transpose');
    $mainwin->bind(ref $self->{input},'<Meta-d>',
		   ['delete','insert','insert wordend']); #kill
    $mainwin->bind(ref $self->{input},'<Meta-BackSpace>',
		   ['delete','insert-1c wordstart','insert']);
#    $mainwin->bind(ref $self->{input},'<Control-h>','deleteBefore');
    $self->{input}->bind("<KeyPress>", sub { $self->update_input() });

    foreach my $key (keys %bindmap) {
	$self->bind($key, $bindmap{$key});
    }
}

sub update_input {
    my $self = shift;
    my $len = length($self->{input}->get("1.0", "end-1char"));
    my $width = $self->{input}->cget("-width");
    my $height = $self->{input}->cget("-height");
    print STDERR "len(txt)=$len width=$width height=$height\n" if $config{ui_debug};
    if($len > ($height*$width)) {
	$self->{input}->configure(-height => ($height+1));
    } elsif($len < (($height-1)*$width)) {
	$self->{input}->configure(-height => ($height-1));
    }
}

sub accept_line {
    print STDERR "TLily::Tk::accept_line() called\n" if $config{ui_debug};
    my($self) = @_;
    my $txt = $self->{input}->get("1.0","end");
    chomp $txt;
    print STDERR "<1>->$txt<-\n" if $config{ui_debug};
    if($txt eq "") {
	$self->{stext}->yview(scroll =>  1, "pages");
    } else {
#	if(defined $self->{indent}) {
#	    $txt = $self->{indent} . $txt;
#	}
#	print STDERR "<2>->$txt<-\n" if $config{ui_debug};
	$self->{input}->delete("1.0", "end");
	$self->style("user_input");
	$self->print($txt, "\n");
	$self->style("normal");
	$self->{text}->see("end - 2c") unless $self->{page};
	if($txt ne $self->{history}->[$#{$self->{history}}]) {
	    $self->{history}->[$#{$self->{history}}] = $txt;
	    push @{$self->{history}}, "";
	    $self->{history_pos} = $#{$self->{history}};
	}
        TLily::Event::send(type => 'user_input',
                           text => $txt,
                           ui   => $self);
	$self->{event_core}->activate();

    }
}


sub prompt_for {
    print STDERR ": TLily::Tk::prompt_for\n" if $config{ui_debug};
    my($self, %args) = @_;
    print STDERR "prompt  : $args{prompt}\n" if $config{ui_debug};
    print STDERR "password: $args{password}\n" if $config{ui_debug};
    print STDERR "call    : $args{call}\n" if $config{ui_debug};
    if(exists $args{prompt}) { $self->prompt($args{prompt}) }

    my @args = (-insertofftime => 500, -insertontime => 500,
		-font => $font{normal});
    if($args{password}) { push(@args, -show => "*") }

    $self->{input}->packForget();
    $self->{prompt_for_w} = $self->{entry}->Entry(@args)
      ->pack(-side => "right", -fill => 'x', -expand => 1);
    $self->{prompt_for_w}->focus();
    $self->{prompt_for_w}->grab();
    $self->{prompt_for_w}->bind('<Meta-less>',
			    [$self->{text} => "see", "1.0"]);
    $self->{prompt_for_w}->bind('<Meta-greater>',
			    [$self->{text} => "see", "end"]);
    $self->{prompt_for_w}->bind("<Prior>",
			    [$self->{stext}, "yview", scroll => -1, "pages"]);
    $self->{prompt_for_w}->bind("<Next>",
			    [$self->{stext}, "yview", scroll =>  1, "pages"]);
    $self->{prompt_for_w}->bind("<Return>",
			    [sub {
				 my $txt = $self->{prompt_for_w}->get();
				 print STDERR "prompt_==>$txt<==\n" if $config{ui_debug};
				 $args{call}->($self, $txt);
				 $self->{event_core}->activate();
				 $self->{prompt_for_w}->grabRelease();
				 $self->{prompt_for_w}->destroy();
				 if(exists $args{prompt}) {
				     $self->prompt(undef);
				 }
				 $self->{input}->pack(-side   => "right",
						      -fill   => 'x',
						      -expand => 1,
						      -anchor => "s");
				 $self->{input}->focus();
			     }]);
}


sub splitwin {
    my($self, $name) = @_;

    $self->not_supported();
    return undef;
}


sub not_supported {
    $_[0]->{toplevel}->Dialog
      (-title	       => "Not Supported",
       -text	       => "This feature is\nnot supported.",
       -bitmap	       => "info",
       -default_button => "Ok",
       -buttons	       => ["Ok"])->Show();
}


sub DESTROY {
    $mainwin->destroy();
}


sub run {
    print STDERR ": TLily::UI::Tk::run\n" if $config{ui_debug};
}


sub configure {
    print STDERR ": TLily::UI::Tk::configure\n" if $config{ui_debug};
}


sub needs_terminal { 0 }

sub suspend { 1 }

sub resume { 1 }


sub defstyle {
    my($self, $style, @attrs) = @_;
    $self->defcstyle($style, $color{white}, $color{black}, @attrs);
}


sub defcstyle {
    my($self, $style, $fg, $bg, @attrs) = @_;

    $bg = $color{black} if $bg eq "-";
    $fg = $color{white} if $fg eq "-";
    $bg = $color{$bg} if exists $color{$bg};
    $fg = $color{$fg} if exists $color{$fg};

    my(@attr);
    my %fn = ("normal" => 1);
    my $rv = 0;
    foreach my $attr (@attrs) {
	if($attr eq "normal") {
	    %fn = (normal => 1);
	    $rv = 0;
	} elsif($attr eq "standout") {
	    # not supported
	} elsif($attr eq "underline") {
	    push(@attr, -underline => 1);
	} elsif($attr eq "reverse") {
	    $rv=1;
	} elsif($attr eq "blink") {
	    # not supported
	} elsif($attr eq "dim") {
	    # not supported
	} elsif($attr eq "bold") {
	    $fn{bold} = 1;
	} elsif($attr eq "italic") {
	    $fn{italic} = 1;
	} elsif($attr eq "altcharset") {
	    # not supported
#	} elsif($attr eq "indent3") {
#	    push(@attr, -lindent1 => "36p",
#		        -lindent2 => "36p");
#	} elsif($attr eq "indent4") {
#	    push(@attr, -lindent1 => "48p",
#		        -lindent2 => "48p");
	}
    }
    if($rv) {
	push(@attr, -foreground => $bg, -background => $fg);
    } else {
	push(@attr, -foreground => $fg, -background => $bg);
    }
    if(not $fn{bold}      and not $fn{italic}) {
	push(@attr, -font => $font{normal});
    } elsif(    $fn{bold} and not $fn{italic}) {
	push(@attr, -font => $font{bold});
    } elsif(not $fn{bold} and     $fn{italic}) {
	push(@attr, -font => $font{italic});
    } elsif(    $fn{bold} and     $fn{italic}) {
	push(@attr, -font => $font{bold_italic});
    }
    print STDERR "defcstyle: style=$style, attr=@attr\n" if $config{ui_debug};
    $self->{styles}->{$style} = [@attr];
    $self->{text}->tag("configure", $style, @attr);
}


sub clearstyle {
    my($self) = @_;
    1;
}


sub style {
    my($self, $style) = @_;
    print STDERR "style: $style\n" if $config{ui_debug};
    $self->{cur_style} = $style;
}


sub indent {
    my $self = shift;
    print STDERR "indent: @_\n" if $config{ui_debug};
    $self->SUPER::indent(@_);
    $self->{indent} = $_[1];
}


sub print {
    my $self = shift;
    return if $config{quiet};
    $self->SUPER::print(@_);
#    my $txt = join("", @_);
#    if($self->{indent}) {
#	$txt =~ s/\n/\n$self->{indent}/g;
#	$txt = $self->{indent} . $txt;
#    }
    $self->{text}->configure(-state => "normal");
#    $self->{text}->insert("end", $txt, $self->{cur_style});
    foreach(@_) { $self->{text}->insert("end", $_, $self->{cur_style}) }
    $self->{text}->configure(-state => "disabled");
    $self->{text}->see("end - 2c") unless $self->{page};
};


sub redraw {
    print STDERR ": TLily::UI::Tk::redraw\n" if $config{ui_debug};
    return 1;
}


sub command_r {
    my($self, $command, $func) = @_;
    return if ($commandmap{$command});
    $commandmap{$command} = $func;
    return 1;
}


sub command_u {
    my($self, $command) = @_;
    return unless ($commandmap{$command});
    delete $commandmap{$command};
    return 1;
}


sub bind {
    my($self, $key, $command) = @_;
    unless(exists $commandmap{$command}) {
	print STDERR "Unknown command: $command\n";
	return 1;
    }

    my $realkey = $key;
    $realkey = $remap{$key} if exists $remap{$key};
    $realkey =~ s/^C-/Control-/;
    $realkey =~ s/^M-/Meta-/;
    print STDERR "bind:key:'$key'\trealkey:'$realkey'\n" if $config{ui_debug};

    if(ref $commandmap{$command} eq "CODE") {
	$mainwin->bind(ref $self->{input}, "<$realkey>", sub {
			   $commandmap{$command}->($self, $command, $key);
		       });
    } elsif(ref $commandmap{$command} eq "ARRAY") {
	$mainwin->bind(ref $self->{input}, "<$realkey>",
		       $commandmap{$command});
    }
    $self->{input}->bind(      "<$realkey>", undef);
    $mainwin->bind(            "<$realkey>", undef);
    $mainwin->bind("all",      "<$realkey>", undef);
    return 1;
}


sub intercept_r {
    print STDERR ": TLily::UI::Tk::intercept_r\n" if $config{ui_debug};
    my($self, $name) = @_;
#    return if (defined($self->{intercept}) && $self->{intercept} ne $name);
#    $self->{intercept} = $name;
    return 1;
}


sub intercept_u {
    print STDERR ": TLily::UI::Tk::intercept_u\n" if $config{ui_debug};
    my($self, $name) = @_;
#    return unless (defined($self->{intercept}));
#    return if ($name ne $self->{intercept});
#    $self->{intercept} = undef;
    return 1;
}


sub command {
    my($self, $command, $key) = @_;
    print STDERR "command:@_\n" if $config{ui_debug};
    my $rc = eval { $commandmap{$command}->($self, $command, $key); };
    warn "Command \"$command\" caused error: $@" if ($@);
    return $rc;
}

sub insert_self {
    my($self, $key) = @_;
    print STDERR "insert-self:@_\n" if $config{ui_debug};
    $self->{input}->insert("insert", $key);
}

sub prompt {
    my($self, $prompt) = @_;
    if(defined $prompt) {
	$prompt =~ s/\s+$//;
	$self->{prompt} = $prompt;
	$self->{prompt_w} = $self->{entry}->Label(-font => $font{normal},
						  -text => $prompt);
	$self->{prompt_w}->pack(-side => "left");
    } else {
	$self->{prompt_w}->destroy();
	$self->{prompt} = $self->{prompt_w} = undef;
    }
}


sub page {
    my($self, $page) = @_;
    print STDERR "page:page:$page\n" if $config{ui_debug};
    if($page == 1) { $self->{page} = 1; }
    else { $self->{page} = 0; }
}


sub define {
    my($self, $name, $pos) = @_;
    $pos ||= 'right';

    # Remove this variable from the existing lists.
    @{$self->{left}}     = grep { $_ ne $name } @{$self->{left}};
    @{$self->{right}}    = grep { $_ ne $name } @{$self->{right}};
    @{$self->{override}} = grep { $_ ne $name } @{$self->{override}};

    if ($pos eq 'left') {
        push @{$self->{left}}, $name;
    } elsif ($pos eq 'right') {
        unshift @{$self->{right}}, $name;
    } elsif ($pos eq 'override') {
        push @{$self->{override}}, $name;
    } else {
        croak "Unknown position: \"$pos\".";
    }
}


sub set {
    my($self, $name, $val) = @_;
    if (defined($self->{var}->{$name}) == defined($val)) {
        return if (!defined($val) || ($self->{var}->{$name} eq $val));
    }
    $self->{var}->{$name} = $val;
    $self->build_string();
}

sub build_string {
    my $self = shift;
    foreach my $v (@{$self->{override}}) {
        next unless (defined $self->{var}->{$v});
        my $s = $self->{var}->{$v};
        my $x = int(($self->{cols} - length($s)) / 2);
        $x = 0 if $x < 0;
        $self->{left_str} = (' ' x $x) . $s;
        return;
    }

    my @l = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
                @{$self->{left}});
    my @r = map({ defined($self->{var}->{$_}) ? $self->{var}->{$_} : () }
                @{$self->{right}});

    $self->{left_str}  = join(" | ", @l) || "";
    $self->{right_str} = join(" | ", @r) || "";
}

sub get_input {
    my($self) = @_;
    my $line = $self->{input}->get("1.0", "end-1char");
    my $pos = $self->{input}->index("insert");
    print STDERR "get_input:line:'$line'\nget_input:pos:'$pos'\n" if $config{ui_debug};
    $pos =~ /\.(\d+)$/;
    $pos = $1;
    print STDERR "get_input:line:'$line'\nget_input:pos:'$pos'\n" if $config{ui_debug};
    return ($pos, $line);
}


sub set_input {
    my $self = shift;
    my($pos, $line) = @_;
    $self->{input}->delete("1.0", "end");
    $self->{input}->insert("end", $line);
    $self->{input}->mark("set", "insert", "1.$pos");
    return 1;
}


sub istyle_fn_r {
    print STDERR ": TLily::UI::Tk::istyle_fn_r\n" if $config{ui_debug};
    #    my($self, $style_fn) = @_;
    #    return if ($self->{input}->style_fn());
    #    $self->{input}->style_fn($style_fn);
    #    return $style_fn;
    return undef;
}


sub istyle_fn_u {
    print STDERR ": TLily::UI::Tk::istyle_fn_u\n" if $config{ui_debug};
    #    my($self, $style_fn) = @_;
    #    if ($style_fn) {
    #	my $cur = $self->{input}->style_fn();
    #	return unless ($cur && $cur == $style_fn);
    #    }
    #    $self->{input}->style_fn(undef);
    return 1;
}

# Search through the history for a given string
sub search_history {
    my $self = shift;
    my $string = shift;
    my $dir = shift || -1;
    $dir = ($dir >= 0)?1:-1;

    return unless ($string);
    my $hist_idx = $self->{history_pos};

    while (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}) ) {
        last if ($self->{history}->[$hist_idx] =~ /$string/);
        $hist_idx += $dir;
    }
    return unless (($hist_idx >= 0) && ($hist_idx <= $#{$self->{history}}));

    $self->{history_pos} = $hist_idx;

    $self->{input}->delete("1.0","end");
    $self->{input}->insert("end", $self->{history}->[$self->{history_pos}]);
    $self->{input}->mark("set", "insert", "end");

    my $pos = index($self->{text}, $string);
    $self->{input}->mark("set", "insert", "1.$pos");
}


sub previous_history {
    my($self) = shift;
    print STDERR "history_pos: $self->{history_pos}\n" if $config{ui_debug};
    print STDERR "\#history  : $#{$self->{history}}\n" if $config{ui_debug};
    return if ($self->{history_pos} <= 0);
    my $txt = $self->{input}->get("1.0", "end");
    $self->{input}->delete("1.0","end");
    chomp $txt;
    $self->{history}->[$self->{history_pos}] = $txt;
    $self->{history_pos}--;
    $self->{input}->insert("end", $self->{history}->[$self->{history_pos}]);
    $self->{input}->mark("set", "insert", "end");
}

sub next_history {
    my($self) = shift;
    print STDERR "history_pos: $self->{history_pos}\n" if $config{ui_debug};
    print STDERR "\#history  : $#{$self->{history}}\n" if $config{ui_debug};
    return if ($self->{history_pos} >= $#{$self->{history}});
    my $txt = $self->{input}->get("1.0", "end");
    $self->{input}->delete("1.0","end");
    chomp $txt;
    $self->{history}->[$self->{history_pos}] = $txt;
    $self->{history_pos}++;
    $self->{input}->insert("end", $self->{history}->[$self->{history_pos}]);
    $self->{input}->mark("set", "insert", "end");
}

sub bell {
    my($self) = @_;
    $self->{toplevel}->bell;
}

sub dump_to_file {
    my($self, $filename) = @_;

    local(*FILE);
    open(FILE, '>', $filename);
    if($!) {
        $self->print("(Unable to open $filename for writing: $!)\n");
	return 0;
    }

    print FILE $self->{text}->get("1.0", "end");
    close(FILE);
    return int($self->{text}->index("end"))-1;
}

1;
