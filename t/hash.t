BEGIN { $| = 1; $tx=1; print "1..4\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

{
    my $osdir = ObjStore->schema_dir;
    my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);
    
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	my $xr = $john->{nest}{rat} = {};
	tied %$xr ? ok : not_ok;

	$xr->{blat} = 69;
	$john->{nest}{rat}{blat} == 69 ? ok : not_ok;

	delete $john->{nest}{rat}{blat};
	delete $john->{nest}{rat};
	delete $john->{nest};

	defined $john->{nest} ? not_ok : ok;
    };
    print "[Abort] $@\n" if $@;
}
