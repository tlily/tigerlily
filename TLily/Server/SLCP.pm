package LC::Server::SLCP;

use strict;
use vars qw(@ISA %config);

use Carp;

use LC::Server;
use LC::Extend;
use LC::Config qw(%config);

@ISA = qw(LC::Server);


sub new {
	my($proto, %args) = @_;
	my $class = ref($proto) || $proto;

	$args{port}     ||= 7777;
	$args{protocol}   = "slcp";
	$args{ui_name}    = "main" unless exists($args{ui_name});

	# Load in the parser.
	LC::Extend::load("slcp");

	my $self = $class->SUPER::new(%args);

	$self->{HANDLE} = {};
	$self->{NAME}   = {};
	$self->{DATA}   = {};

	bless $self, $class;
}


=item expand_name()

Translates a name into a full lily name.  For example, 'cougar' might become
'Spineless Cougar', and 'comp' could become '-computer'.  The name returned
will be identical to canonical one used by lily for that abberviation,
with the exception that discussions are returned with a preceding '-'.
If the name is an exact match (modulo case) for a group, the group name
is returned.  Substrings of groups are not, however, expanded.  This is
in line with current lily behavior.

If $config{expand_group} is set, groups will be expanded into a
comma-separated list of their members.

    expand_name('comp');

=cut

sub expand_name {
	my($self,$name) = @_;
	my $disc;

	$name = lc($name);
	$name =~ tr/ /_/;
	$disc = 1 if ($name =~ s/^-//);

	# KLUDGE!  Rather that rewrite things properly I took the lazy way out.
	# shoot me.
	my (%Users,%Groups,%Discs,$Me);
	$Me = $self->user_name;
	foreach (keys %{$self->{NAME}}) {
		if ($self->{NAME}{$_}->{LOGIN}) {
			$Users{lc($_)}->{Name} = $_;
		}
		if ($self->{NAME}{$_}->{CREATION}) {
			$Discs{lc($_)}->{Name} = $_;
		}
	}
	# END KLUDGE

	# Check for "me".
	if (!$disc && $name eq 'me') {
		return $Me || 'me';
	}

	# Check for an exact match.
	if ($Groups{$name}) {
		if ($config{expand_group}) {
			return join(',', @{$Groups{$name}->{Members}});
		} else {
			return $Groups{$name}->{Name};
		}
	}
	if (!$disc && $Users{$name}) {
		return $Users{$name}->{Name};
	}
	if ($Discs{$name}) {
		return '-' . $Discs{$name}->{Name};
	}
        
	my @unames = keys %Users;
	my @dnames = keys %Discs;

	# Check the "preferred match" list.
	if (ref($config{prefer}) eq "ARRAY") {
		my $m;
		foreach $m (@{$config{prefer}}) {
			$m = lc($m);
			return $m if (index($m, $name) == 0);
			return $m if ($m =~ /^-/ && index($m, $name) == 1);
		}
	}
        
	my @m;
	# Check for a prefix match.
	unless ($disc) {
		@m = grep { index($_, $name) == 0 } @unames;
		return $Users{$m[0]}->{Name} if (@m == 1);
		return undef if (@m > 1);
	}
	@m = grep { index($_, $name) == 0 } @dnames;
	return '-' . $Discs{$m[0]}->{Name} if (@m == 1);
	return undef if (@m > 1);
        
	# Check for a substring match.
	unless ($disc) {
		@m = grep { index($_, $name) != -1 } @unames;
		return $Users{$m[0]}->{Name} if (@m == 1);
		return undef if (@m > 1);
	}
	@m = grep { index($_, $name) != -1 } @dnames;
	return '-' . $Discs{$m[0]}->{Name} if (@m == 1);
	return undef if (@m > 1);
	
	return undef;
}


=item user_name

The pseudo used by the current user.  Example:

    $Me = $serv->user_name;

=cut

sub user_name () {
	my ($self) = @_;

	my $hdl = $self->user_handle();
	return unless (defined $hdl);

	my %rec = $self->state(HANDLE => $hdl);
	return defined($rec{NAME}) ? $rec{NAME} : $hdl;
}


=item user_handle

The MOO object ID for the current user.

=cut

sub user_handle () {
    my ($self) = @_;

    return $self->{DATA}{whoami};
}


=item state()

This function provides access to the Server module's User State database.
It allows creating, updating, and retrieval of records from this db.

The syntax is a little special because of this flexibility, but I think
it will make sense.  Parameter names map directly to SLCP's, in case
you were curious.  Extra parameters will be ignored.  Currently
HANDLE and NAME are the database keys, and any other data is stored.

Note that this state database makes no distinction between users, groups,
and discussions.  All can be stored here, which is convenient.

Example:

    # add "Josh"
    $serv->state(HANDLE => "#123",
                 NAME => "Josh",
                 BLURB => "@work");

    # retrieve Josh's record by Handle
    %josh = $serv->state(HANDLE => "#123");

    # retrieve Josh's record by Name
    %josh = $serv->state(NAME => "Josh");

    # set a DATA item:
    $serv->state(DATA => 1,
                 NAME => "whoami",
                 VALUE => "#850");

    # retrieve a DATA item:
    $val = $serv->state(DATA => 1,
                        NAME => "whoami");

or

    $val = $serv->{DATA}{whoami};

=cut

sub state {
	my ($self,%args) = @_;

	# Deal with DATA items.
	# The DATA arg must be set if you want to use these.
	if ($args{DATA}) {
		if ($args{VALUE}) {
			$self->{DATA}{$args{NAME}} = $args{VALUE};      
		}
		return $self->{DATA}{$args{NAME}};
	} 

	# OK, the rest of this function refers to the normal records, which
	# are indexed by HANDLE and NAME.

	carp "bad state call"  unless ($args{HANDLE} || $args{NAME});

	# figure out if the user is querying or insert/updating.
	my $query = 1;
	foreach (keys %args) {
		if ( ! /^(HANDLE|NAME)$/ ) { $query = 0; }
	}

	if ($query) {
		# ok, it's a query.  return a copy of the record (preferring
		# the HANDLE index, but using either.
		if ($args{HANDLE}) {
			my $h = $self->{HANDLE}{$args{HANDLE}};
			return $h ? %$h : undef;
		} else {
			my $h = $self->{NAME}{$args{NAME}};
			return $h ? %$h : undef;
		}
	} else {
		# OK.  So now we have either an insert or an update.
		# First check to see if we have a record in the
		# database (in which case it's an update)

		my $record;
		if ($args{HANDLE}) {
			$record = $self->{HANDLE}{$args{HANDLE}};
		} else {
			$record = $self->{NAME}{$args{NAME}};
		}

		if (! ref($record)) {
			# create a new record if one was not found.
			$record = {};
		}

		# OK, now update the record with our arguments.
		foreach (keys %args) { $record->{$_}=$args{$_}; }

		# And recreate the indices to make sure things are nice and 
		# consistent.

		$self->{HANDLE}{$record->{HANDLE}} = $record
			if ($record->{HANDLE});
		$self->{NAME}{$record->{NAME}}     = $record
			if ($record->{NAME});

		# and return a copy of the new record.
		return %{$record};
	}
}


=item get_name()

=cut

sub get_name {
	my ($self,%args) = @_;

	my %rec = $self->state(%args);

	return $rec{NAME} if ($rec{NAME} =~ /\S/);
	return $args{HANDLE} || "[unknown]";
}


=item get_blurb()

=cut

sub get_blurb {
	my ($self,%args) = @_;

	my %rec = $self->state(%args);
	return $rec{BLURB};
}


=item get_title()

=cut

sub get_title {
	my ($self,%args) = @_;

	my %rec = $self->state(%args);
	return $rec{TITLE};
}


# this is a fun hack.  a %dumpstate for querying the state database :)
# need to document this.
# usage: %dumpstate
#        %dumpstate [HANDLE|NAME KEY]
#        %dumpstate NAME
#        %dumpstate NAME Josh
#        %dumpstate HANDLE #850
sub dumpstate {
    my ($self,$args) = @_;
    my ($dindex,$dkey) = split /\s+/,$args;
    my ($rec,$index,$key);

    ui_output("Desired index: \"$dindex\", key: \"$dkey\"");

    foreach $index (sort keys %{$self}) {
        if ($dindex && ($index ne $dindex)) { next; }
        ui_output("$index:");
        if (! ref($self->{$index})) {
            ui_output("   $self->{$index}\n");
        }
        foreach $key (sort keys %{$self->{$index}}) {
            if ($dkey && ($key ne $dkey)) { next; }
            if (! ref($self->{$index}{$key})) {
                ui_output("   $key=$self->{$index}{$key}");
            } else {
                ui_output("   $key = {");
                $rec = $self->{$index}{$key};
                foreach (sort keys %{$rec}) {
                    ui_output("     $_=$rec->{$_}");
                }
                ui_output("   }");
            }
        }
    }
}


1;

=back
=cut
