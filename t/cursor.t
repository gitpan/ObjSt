BEGIN { $| = 1; $tx=1; print "1..2\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

{
    my $osdir = ObjStore->schema_dir;
    my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);
    
    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	my $ok=0;
	for (sort keys %$john) {
	    $ok=1 if $_ eq 'cnt';
	}
	$ok? ok : not_ok
    };
    print "[Abort] $@\n" if $@;
}
