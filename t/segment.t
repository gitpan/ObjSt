BEGIN { $| = 1; $tx=1; print "1..3\n"; }

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

use ObjStore;

{
    my $osdir = ObjStore->schema_dir;
    my $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);
    
    my $junk = {
	'nums' => { 1..50 },
	'strs' => { qw(a b c d e f g h) },
    };

    try_update {
	my $john = $DB->root('John');
	$john ? ok : not_ok;

	my $seg;
	if (!defined $john->{h1}) {
	    $seg = $DB->create_segment();
	    $john->{h1} = $seg->newHV('array');
	    $john->{seg} = $seg->get_number();
	} else {
	    $seg = $DB->get_segment($john->{seg});
	}
	for (keys %$junk) { $john->{h1}{$_} = $junk->{$_}; }

	# segment is from OSSVPV, not from OSSV
	my $nseg = ObjStore::Segment->of(tied %{$john->{h1}});
        if ($nseg->get_number() == $seg->get_number()) {
	    ok;
	} else {
	    not_ok;
	}

	# easy double-check
	$nseg = ObjStore::Segment->of(tied %{$john->{h1}{nums}});
        if ($nseg->get_number() == $seg->get_number()) {
	    ok;
	} else {
	    not_ok;
	}

	delete $john->{h1};
	$seg->destroy;
    };
    print "[Abort] $@\n" if $@;
}
