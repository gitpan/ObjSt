#!/usr/local/bin/perl -w

# Please set the following environment variables before compiling.

# OS_ROOTDIR=/nw/dist/vendor/os/4.0.2/sunpro
# OS_LDBBASE=/export2/os/4.0.2/sunpro
# .ldb files must be on the osserver's local filesystem
 
# PATH+=$OS_ROOTDIR/bin
# LD_LIBRARY_PATH+=$OS_ROOTDIR/lib
# MANPATH+=$OS_ROOTDIR/man
 
# The makefile is set up for SunPro C++ (SC4.0 18 Oct 1995 C++ 4.1).
# To retarget for other compilers, you will need to make changes
# to Make.pm.

# Also, make sure you pick a good directory for the application
# schema, below.

use lib ".";
use Make;
use ExtUtils::Manifest qw(&mkmanifest &manicheck);
use Test::Harness;

sub osperl {
    my $o = new Make('osperl');
    $o->opt(1);

    # specify a good directory for the application schema
    $o->objstore('/opt/os/joshua', 'collections');

    $o->embed_perl('ObjStore');
    $o->xs('ObjStore.xs');
    $o->cxx('osperl.c');
    $o->link;
    &test;
}

sub test {
    print "
t/hash fails 2/4 until perl bug is fixed
------------------------------------------------------------------------------
";
    $^X = './osperl';
#    system("./osperl t/basic.t");
#    system("./osperl t/cursor.t");
#    system("./osperl t/hash.t");
#    system("./osperl t/segment.t");
    runtests(grep(!/\~$/, sort glob('t/*')));
}

sub clean {
    # most of this should be moved to Make.pm (?)
    unlink glob('*.o'), glob('osperl-osschema.*'), 'osperl', 'ObjStore.c';
    system("rm -rf Templates.DB");
}

{
    if (@ARGV == 0) {
	osperl();
    } elsif ($ARGV[0] eq 'clean') {
	clean();
    } elsif ($ARGV[0] eq 'test') {
	test();
    } elsif ($ARGV[0] eq 'manifest') {
	mkmanifest;
    } elsif ($ARGV[0] eq 'check') {
	print "Looks good.\n" if ! manicheck;
    } elsif ($ARGV[0] eq 'install') {
	print "Not yet.\n";
    }
}

