package LC::Server::SLCP;

use strict;
use vars qw(@ISA);

use LC::Server;
use LC::Extend;

@ISA = qw(LC::Server);


sub new {
	my($proto, %args) = @_;
	my $class = ref($proto) || $proto;

	$args{port}     ||= 7777;
	$args{protocol}   = "slcp";

	# Load in the parser.
	LC::Extend::load("slcp");

	my $self = $class->SUPER::new(%args);

	$self->{HANDLE} = {};
	$self->{NAME}   = {};

	bless $self, $class;
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
	return $rec{NAME} if ($rec{NAME} =~ /\S/);
	return $hdl;
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

	# OK, the rest of this function refers to the normal records, which are 
	# indexed by HANDLE and NAME.

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
