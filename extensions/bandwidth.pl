# -*- Perl -*-
# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/extensions/bandwidth.pl,v 1.4 1999/10/02 02:45:15 mjr Exp $

sub load {
    my $ui = ui_name("main");
    my $server = TLily::Server::active();

    if ($server) {
	init_bandwidth();
    
    } else {
	event_r(type => 'connected',
		call => \&init_bandwidth);
    }
}


sub init_bandwidth {
    my $ui = ui_name("main");
    my $server = TLily::Server::active();
    my $last_in  = $server->{bytes_in};
    
    $ui->define(bandwidth => 'right');
    my $update = 10;		# seconds
    
    my $sub = sub {
	my $ui = ui_name("main");
	my $server = TLily::Server::active();
	return 2 unless ($server);
	
	my $in       = $server->{bytes_in} - $last_in;
	my $last_in  = $server->{bytes_in};
	
	$in  = int($in/$update);
	if ($in > 1024) {
	    $in = sprintf "%.1f k", ($in / 1024);
	} else {
	    $in .= " b";
	}
	$in  .= "/s";
	
	$ui->set(bandwidth => $in);
    };
    TLily::Event::time_r(after    => $update,
			 interval => $update,
			 call     => $sub);
    
    return 0;
}

