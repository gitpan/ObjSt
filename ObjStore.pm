# Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package ObjStore;

use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT);

require Exporter;
@ISA     = qw(Exporter);
@EXPORT  = qw(&try_update &try_read);
$VERSION = '1.000';

bootstrap ObjStore;

package ObjStore;

# try_update { complex transaction }
# print "[Abort] $@\n" if $@;

sub try_update(&) {
    my ($fun) = @_;
    ObjStore->begin_update();
    eval {
#	local $SIG{'__DIE__'};
	&$fun;
    };
    if ($@) {
	ObjStore->abort;
    } else {
	ObjStore->commit;
    }
}

sub try_read(&) {        # is this a dumb idea?
    my ($fun) = @_;
    ObjStore->begin_read;
    eval {
#	local $SIG{'__DIE__'};
	&$fun;
    };
    if ($@) {
	ObjStore->abort;  # Abort after reading?  Whatever.
    } else {
	ObjStore->commit;
    }
}

package ObjStore::Database;

sub root {
    my ($o, $roottag, $nval) = @_;
    my $root = $o->find_root($roottag);
    $root = $o->create_root($roottag) unless $root;
    $root->set_value($nval) if $nval;
    $root->get_value();
}

package ObjStore::Segment;

sub newTiedHV {
    my ($seg, $rep) = @_;
    my $hvobj = $seg->newHV($rep);
    my %h;
    tie %h, 'ObjStore::HV', $hvobj;
    \%h;
}

package ObjStore::HV;
use Carp;

sub TIEHASH {
    my ($class, $o) = @_;
    croak "Expecting ObjStore::HV" if ref $o ne 'ObjStore::HV';
    bless $o, $class;
}

sub STORE {
    my ($o, $k, $nval) = @_;
    if (!ref $nval) {
	$o->_STORE($k, $nval);
    } elsif (ref $nval eq 'HASH') {
	if (tied %$nval) {
	    $o->_STORE($k, tied %$nval);
	} else {
	    my $seg = ObjStore::Segment->of($o);
	    my $hv = $seg->newHV('array');         # allow customization XXX
	    while (my($hk,$v) = each %$nval) {
		$hv->STORE($hk, $v);
	    }
	    $o->_STORE($k, $hv);
	}
    } elsif (ref $nval eq 'ObjStore::HV') {
	$o->_STORE($k, $nval);
    } else {
	croak "Don't know how to store $nval";
    }
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

ObjStore - Perl extension for ObjectStore ODMS

=head1 SYNOPSIS

  use ObjStore;

  $osdir = ObjStore->schema_dir;
  $DB = ObjStore::Database->open($osdir . "/perltest.db", 0, 0666);

  try_update {
      $top = $DB->root('megabase', $DB->newHV('dict'));
      for (1..1000000000) $top->{$_} = "Wow-$_!";      # might run out of RAM?
  };
  print "[Abort] $@\n" if $@;

=head1 DESCRIPTION

Stub documentation for ObjStore was created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.  [Yup.]

=head1 AUTHOR

Joshua Pritikin, pritikin@mindspring.com

=head1 SEE ALSO

ObjectStore Documentation

=cut
