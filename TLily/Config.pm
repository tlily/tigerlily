package Config;

use strict;
use vars qw(@ISA @EXPORT_OK %config);

use Exporter;

@ISA       = qw(Exporter);
@EXPORT_OK = qw(%config);

%config = ();


1;
