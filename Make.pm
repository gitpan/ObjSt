# Why does MakeMaker make use of standard unix make when it could use
# perl exclusively?  Does make actually add much value? It doesn't
# seem like it.  I hate the syntax too.

# This should probably be redesigned to be completely generic and
# integrated with MakeMaker.

package Make;
use Config;
use ExtUtils::Embed;
use File::stat;

# XXX make compile flags persistent (in AnyDBM?) so we can /depend/ on them

sub x {
    print join(" ", @_)."\n";
    system(@_);
    my ($kill, $exit) = ($? & 255, $? >> 8);
    if ($kill) {
	print "*** Break $kill\n";
	exit;
    }
    if ($exit) {
	print "*** Exit $exit\n";
	exit;
    }
    print "\n";
}

sub xsh { x(join(" ", @_)); }

# XXX be more clever about finding xsubpp & perl
sub new {
    shift;
    my ($final) = @_;
    my $lib=0;
    my $tag = $final;
    if ($final =~ m/^lib(.+)\.a$/) {
	$lib = 1;
	$tag = $1;
    }
    my $flags = {
	'CC' => [qw(-pta )],
	'cxx' => [],
	'ld' => [],
	'LDB' => [],
	'xsubpp' => ["-typemap", "$Config{privlibexp}/ExtUtils/typemap"],
	};
    my $src = {
	'cxx' => []
	};
    my $exe = {
	'cxx' => 'CC',
	'ld' => 'CC',
	'xsubpp' => "$Config{privlibexp}/ExtUtils/xsubpp",
	'perl' => 'perl',
	};
    
    bless { final=>$final, tag=>$tag, lib=>$lib, objstore=>0,
	    src=>$src, flags=>$flags, exe=>$exe };
}

sub flags {
    my ($o, $exe, @add) = @_;
    push(@{$o->{flags}{$exe}}, @add) if @add > 0;
    @{$o->{flags}{$exe}};
}

# XXX cache stat results
sub newer {
    my ($target, @deps) = @_;
    return 1 if !-e $target;
    my $ttm = stat($target)->mtime;
    for (@deps) {
	my $o = stat($_);
	return 1 if ($o and $o->mtime > $ttm);
    }
    0;
}

sub opt {
    my ($o, $opt) = @_;
    if ($opt) {
	$o->flags('cc', '-O');
	$o->flags('cxx', '-O');
    } else {
	$o->flags('cc', '-g');
	$o->flags('cxx', '-g');
    }
}

sub src {
    my $o=shift;
    my $f;
    for $f (@_) {
	if ($f =~ /\.o$/) {
	    push(@{$o->{src}{o}}, $f);
	} else {
	    die "unknown source type '$f'";
	}
    }
}

$OS_FEATURE = {
    'collections' => { ldb => 'liboscol.ldb', lib => '-loscol' },
    'compactor' => { ldb => 'liboscmp.ldb', lib => '-loscmp' },
    'queries' => { ldb => 'libosqry.ldb', lib => '-losqry' },
    'evolution' => { ldb => 'libosse.ldb', lib => '-losse' }
};    
sub objstore {
    my $o = shift;
    die "OS_ROOTDIR not set" unless defined $ENV{OS_ROOTDIR};
    die "OS_LDBBASE not set" unless defined $ENV{OS_LDBBASE};

    $o->{objstore}=1;

    $o->flags('CC', '-vdelx'); # fix vector delete

    $o->{osdbdir} = shift;
    $o->flags('cxx', "-I$ENV{OS_ROOTDIR}/include", qq(-DSCHEMADIR="$o->{osdbdir}"));
    $o->flags('ld', "-R $ENV{OS_ROOTDIR}/lib");

    my %features;
    for (@_) { $features{$_}=1; }
    for (qw( evolution queries compactor collections )) {
	if (defined $features{$_}) {
	    die $_ if !defined $OS_FEATURE->{$_};
	    $o->flags('ld', $OS_FEATURE->{$_}{lib});
	    $o->flags('LDB', "$ENV{OS_LDBBASE}/lib/".$OS_FEATURE->{$_}{ldb});
	}
    }
    $o->flags('ld', "-los", "-losths");
}

# XXX check dependencies
sub cxx {
    my $o=shift;
    die "cxx file.cc" if @_ != 1;
    my $file = shift;
    my $cxx = $o->{exe}{cxx};
    x($cxx, $o->flags($cxx), $o->flags('cxx'), "-c", $file);
    $file =~ s/\.[^.]+$/.o/;
    $o->src($file);
}
 
sub embed_perl {
    my ($o, @mod) = @_;
    my $xsi = 'perlxsi';
    unshift(@mod, 'DynaLoader');
    if (!-e "$xsi.o") {
	xsinit("$xsi.c", 0, \@mod);
	x($Config{cc}, $o->flags('cc'), "-I$Config{archlibexp}/CORE", '-c', "$xsi.c");
	unlink("$xsi.c");
    }
    $o->src("$xsi.o");
    $o->flags('cxx', "-I$Config{archlibexp}/CORE");
    $o->flags('ld', split(/\s+/, ldopts(0,\@mod,[],'')));
}

sub xs {
    die "xs file.xs" if @_ != 2;
    my ($o, $f) = @_;
    $f =~ s/\.xs$//;
    if (newer("$f.o", "$f.xs", "typemap")) {
	xsh($o->{exe}{perl}, $o->{exe}{xsubpp}, '-C++', '-prototypes',
	    $o->flags('xsubpp'), "$f.xs", ">$f.tc");
	x('mv', "$f.tc", "$f.c");
	$o->cxx("$f.c");
    } else {
	$o->src("$f.o");
    }
}

# -G shared library
# -pic
sub link {
    my $o=shift;

    if (! $o->{lib}) {
	if ($o->{'objstore'}) {
	    my @inc = grep(/^-I/, $o->flags('cxx'));
	    x("ossg", @inc, '-asdb', "$o->{osdbdir}/$o->{tag}.adb",
	      '-assf', "$o->{tag}-osschema.c", "$o->{tag}-schema.c",
	      $o->flags('LDB'));
	    $o->cxx("$o->{tag}-osschema.c");
	}
	my $ld = $o->{exe}{'ld'};
	x($ld, $o->flags($ld), @{$o->{'src'}{o}}, "-o", $o->{final},
	  $o->flags('ld'));
	unlink "ir.out";  # tmp file created by the linker??
	x("os_postlink", $o->{final}) if $o->{'objstore'};
    }
}

1;
