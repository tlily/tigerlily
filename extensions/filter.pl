use strict;

#
# $config{filter} is a hashref to word/subst combos.
#
shelp_r('filter', "hashref of words to subst text for %filter", "variables");
shelp_r('filter', "Specify words to filter, and their substitutions");
help_r('filter', <<EOHELP);

this extension parses all blurb, public, private, emote, and text events,
altering any words that it finds in your config variable, 'filter'. You may
specify in your tlily.cf:

%filter = qw/test t**t/;

and any text in the event types listed above that contains the word "test"
will automatically be changed to "t**t".
EOHELP

if (!defined($config{filter})) {
  $config{filter}={};
}

sub filter {
	my ($event, $handler) = @_;

   	foreach my $word (keys %{$config{filter}}) {
          $event->{VALUE} =~ s/$word/$config{filter}->{$word}/gi;
          $event->{text} =~ s/$word/$config{filter}->{$word}/gi;
        }
	return;
}

# Insert event handlers for everything we care about.
foreach my $type (qw/private public emote blurb text/) {
  event_r(type=>$type, order=>'before', call => \&filter);
}
