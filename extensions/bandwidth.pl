sub load {
    my $ui = ui_name("main");
    my $server = server_name();

    if ($server) {
	init_bandwidth();
    
    } else {
	event_r(type => 'connected',
		call => \&init_bandwidth);
    }
}


sub init_bandwidth {
    my $ui = ui_name("main");
    my $server = server_name();
    my $last_in  = $server->{bytes_in};
    
    $ui->define(bandwidth => 'right');
    my $update = 10;		# seconds
    
    my $sub = sub {
	my $ui = ui_name("main");
	my $server = server_name();
	return unless ($server);
	
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
    
    return;
}

