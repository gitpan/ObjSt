/*
Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
*/

#include <assert.h>
#include <string.h>
#include "osperl.hh"

//#define DEBUG_MEMORY
//#define DEBUG_REFCNT

/*--------------------------------------------- OSSV */

// OSSV_in
//
// 1. recursively mirror SVs into OSSV object tree
// 2. untie a tied OSSV object
// 3. or just pass through a blessed OSSV object
//
typedef OSSV OSSV_in;

// OSSV_out - tie a new var to an OSSV bless reference (depreciated)
//
typedef OSSV OSSV_out;

OSSV::OSSV()
{ _type = ossv_undef; }

OSSV::OSSV(SV *nval)
{ _type = ossv_undef; this->operator=(nval); }

OSSV::OSSV(OSSV *nval)
{ this->operator=(nval); }

OSSV::~OSSV()
{ undef(); }

// references and roots can REFER
// hashes and arrays (OSSVPV) can BE REFERRED TO

int OSSV::refs() 
{
  switch (natural()) {
  case ossv_av: case ossv_hv:
    return ((OSSVPV*)ref)->refs;
    break;
  default: return 0;
  }
}

void OSSV::REF_inc(void *nval)
{
  switch (natural()) {
  case ossv_av: case ossv_hv:
    if (nval) ref = nval;
    assert(ref != 0);
    ((OSSVPV*)ref)->REF_inc();
    break;
  }
}

void OSSV::REF_dec()
{
  switch (natural()) {
  case ossv_av: case ossv_hv:
    ((OSSVPV*)ref)->REF_dec();
    ref = 0;
    break;
  }
}

OSSV *OSSV::operator=(SV *nval)
{
  // bless ref to ObjStore object?
  if (sv_isobject( nval ) && (SvTYPE(SvRV( nval )) == SVt_PVMG) ) {
    OSSV *ossv = (OSSV *) SvIV((SV*)SvRV( nval ));
    this->s(ossv);
    return this;
  }

  int ok=0;
  char *tmp; unsigned tmplen;	// for extracting strings
  switch (natural()) {		// try to avoid coercing in the DB
    case ossv_iv:
      if (SvIOK(nval)) { s((os_int32) SvIV(nval)); ok=1; }
      break;
    case ossv_nv:
      if (SvNOK(nval)) { s(SvNV(nval)); ok=1; }
      break;
    case ossv_pv:
      if (SvPOK(nval)) {
        tmp = SvPV(nval, tmplen);   //memory leak? XXX
        s(tmp, tmplen);
        ok=1;
      }
      break;
    default: break;
  }
  if (ok) return this;
  if (SvIOKp(nval)) {
    s((os_int32) SvIV(nval));
  } else if (SvNOKp(nval)) {
    s(SvNV(nval));
  } else if (SvPOKp(nval)) {
    tmp = SvPV(nval, tmplen);   //memory leak? XXX
    s(tmp, tmplen);
  } else if (! SvOK(nval)) {
    undef();
  } else {
    warn("OSSV::operator =(SV*) - not yet");
  }
  return this;
}

OSSV *OSSV::operator =(OSSV *nval)
{ s(nval); return this; }

ossvtype OSSV::natural()
{ return _type; }

os_int32 OSSV::discriminant()
{
  // XXX handle byte swapping for mixed architectures
  switch (natural()) {
    case ossv_undef: return 0;
    case ossv_iv:    return 1;
    case ossv_nv:    return 2;
    case ossv_pv:    return 3;
    case ossv_rv:    return 0;
    case ossv_av:    return 0;
    case ossv_hv:    return 0;
    default:         return 0;
  }
}

// prepare to switch to new data/datatype
int OSSV::morph(ossvtype nty)
{
  if (_type == nty) return 0;
  REF_dec();
  switch (_type) {
  case ossv_undef: case ossv_iv: case ossv_nv:
    break;

  case ossv_pv:
#ifdef DEBUG_MEMORY
    warn("OSSV::morph(%d -> %d): deleting string '%s' 0x%x", _type, nty, ref, ref);
#endif
    delete [] ((char*)ref);
    ref = 0;
    break;

  case ossv_rv: case ossv_av: case ossv_hv: break;

  default: croak("OSSV::morph type unknown");
  }
  _type = nty;
  return 1;
}

void OSSV::undef()
{ morph(ossv_undef); }

void OSSV::s(os_int32 nval)
{ morph(ossv_iv); iv = nval; }

void OSSV::s(double nval)
{ morph(ossv_nv); nv = nval; }

// nlen is length of string including null terminator
void OSSV::s(char *nval, os_unsigned_int32 nlen)  // simple copy implementation
{
//  warn("OSSV::s - prior type = %d", _type);
  if (!morph(ossv_pv)) {
#ifdef DEBUG_MEMORY
    warn("OSSV::s(%s, %d): deleting string 0x%x", nval, nlen, ref);
#endif
    delete [] ((char*)ref);   // probably wrong length
    ref = 0;
  }
  len = nlen;
  char *str = new(os_segment::of(this), os_typespec::get_char(), len) char[len]; //OSNEW
#ifdef DEBUG_MEMORY
  warn("OSSV::s(%s, %d): alloc string 0x%x", nval, nlen, str);
#endif
  memcpy(str, nval, len);
  ref = str;
}

void OSSV::s(OSSV *nval)
{ 
  switch (nval->natural()) {

   // value semantics
  case ossv_undef: undef(); break;
  case ossv_iv: s(nval->iv); break;
  case ossv_nv: s(nval->nv); break;
  case ossv_pv: s((char*) nval->ref, nval->len); break;
    
  case ossv_rv:			// alien data
    morph(nval->natural());
    croak("not yet");
    break;
    
  case ossv_av: case ossv_hv:   // ref counted semantics
    if (morph(nval->natural())) {
      REF_inc(nval->ref);
    } else if (ref != nval->ref) {
      REF_dec();
      REF_inc(nval->ref);
    }
    break;
  }
}

void OSSV::new_array(char *rep)
{
  if (natural() != ossv_undef) croak("Can't create new array now.");
  morph(ossv_av);
  croak("arrays not implemented yet");
}

void OSSV::new_hash(char *rep)
{
  if (natural() != ossv_undef) croak("Can't create new hash now.");
  morph(ossv_hv);
  if (strcmp(rep, "array")==0) {
    ref = new(os_segment::of(this), OSPV_array::get_os_typespec()) OSPV_array; //OSNEW
#ifdef DEBUG_MEMORY
    warn("OSSV::new_hash(): new OSPV_array = 0x%x", ref);
#endif
  } else if (strcmp(rep, "dict")==0) {
    ref = new(os_segment::of(this), OSPV_dict::get_os_typespec()) OSPV_dict; //OSNEW
#ifdef DEBUG_MEMORY
    warn("OSSV::new_hash(): new OSPV_dict = 0x%x", ref);
#endif
  } else {
    croak("new_hash(%s): unknown representation", rep);
  }
}

char *OSSV::Type()  // similar to Ref
{
  switch (natural()) {
   case ossv_undef: return "undef";
   case ossv_iv:    return "int";
   case ossv_nv:    return "double";
   case ossv_pv:    return "string";
   case ossv_rv:    return "REF";
   case ossv_av:    return "ARRAY";
   case ossv_hv:    return "HASH";
   default: croak("unknown type");
  }
};

char *OSSV::CLASS()  // figure out where to bless OSSV
{
  char *CL;
  if (natural() == ossv_av) {
    CL = "ObjStore::AV";
  } else if (natural() == ossv_hv) {
    CL = "ObjStore::HV";
  } else {
    CL = "ObjStore::SV";
  }
  return CL;
}

char OSSV::MAGIC()	// figure out magic vtbl
{
  char mg;
  if (natural() == ossv_av || natural() == ossv_hv) {
    mg = 'P';
  } else {
    mg = 'q';
  }
  return mg;
}

os_segment *OSSV::get_segment()
{
    switch (natural()) {
      case ossv_av:
      case ossv_hv:
	return ((OSSVPV*)ref)->get_segment();
      default:
	return os_segment::of(this);
    }
}

os_int32 OSSV::as_iv()
{
  switch (natural()) {
    case ossv_iv: return iv;
    case ossv_nv: return (I32) nv;
    default:
      warn("SV %s has no int representation", Type());
      return 0;
  }
}

double OSSV::as_nv()
{
  switch (natural()) {
    case ossv_iv: return iv;
    case ossv_nv: return nv;
    default:
      warn("SV %s has no double representation", Type());
      return 0;
  }
}

char OSSV::strrep[32];  // temporary space for string representation

char *OSSV::as_pv()     // returned string does not need to be freed
{
  switch (natural()) {
    case ossv_iv:   sprintf(strrep, "%ld", iv); break;
    case ossv_nv:   sprintf(strrep, "%f", nv); break;
    case ossv_pv:   return (char*) ref;
    case ossv_rv: case ossv_av: case ossv_hv:
      sprintf(strrep, "%s(0x%lx)", Type(), ref);
      break;
    default:
      warn("SV %s has no string representation", Type());
      strrep[0]=0;
      break;
  }
  return strrep;
}

os_unsigned_int32 OSSV::as_pvn()
{
  if (natural() == ossv_pv) {
    return len;
  } else {
    warn("SV %s has no string length", Type());
    return 0;
  }
}

// always use return value - may return sv_undef
SV *OSSV::as_sv(SV *sv)
{
  switch (natural()) {
    case ossv_undef: sv = &sv_undef; break;
    case ossv_iv: sv_setiv(sv, iv); break;
    case ossv_nv: sv_setnv(sv, nv); break;
    case ossv_pv: sv_setpvn(sv, (char*) ref, len); break;
    default:
      warn("OSSV %s is not scalar", Type());
      sv = &sv_undef;
      break;
  }
  return sv;
}

/*--------------------------------------------- hkey */
// A hkey is smaller than a pointer to a string!
// hkey assumes no strings with embedded nulls - problem? XXX

hkey::hkey()
{ undef(); }

hkey::hkey(const hkey &k1)
{ memcpy(str, k1.str, HKEY_MAXLEN); }

hkey::hkey(const char *s1)
{
  if (strlen(s1) > HKEY_MAXLEN)
    warn("hkey must be less than %d chars: '%s' truncated", HKEY_MAXLEN, s1);
  strncpy(str, s1, HKEY_MAXLEN);
}

void hkey::undef()
{ str[0] = 0; }

int hkey::valid()
{ return str[0] != 0; }

hkey *hkey::operator=(hkey *k1)
{ memcpy(this->str, k1->str, HKEY_MAXLEN); return this; }

hkey *hkey::operator=(char *k1)
{ hkey tmp(k1); *this = tmp; return this; }

SV *hkey::as_sv()
{
  char buf[HKEY_MAXLEN+2];
  memset(buf, 0, HKEY_MAXLEN+2);
  memcpy(buf, str, HKEY_MAXLEN);
  return sv_2mortal(newSVpv(buf, 0));
}

os_unsigned_int32 hkey::hash(const void *v1)
{
  const hkey *s1 = (hkey*)v1;
  return *((os_unsigned_int32*) s1->str);
}

// just use memcmp? XXX
int hkey::rank(const void *v1, const void *v2)
{
  const hkey *s1 = (hkey*)v1;
  const hkey *s2 = (hkey*)v2;
  const unsigned long h1 = *((unsigned long*) s1->str);
  const unsigned long h2 = *((unsigned long*) s2->str);
  if (h1 == h2) {
    return strncmp(s1->str, s2->str, HKEY_MAXLEN);
  } else {
    if (h1 > h2) return os_collection::GT;
    else return os_collection::LT;
  }
}

hent *hent::operator=(hent *nval)
{
  hk.operator=(&nval->hk); hv.operator=(&nval->hv);
  return this;
}

/*--------------------------------------------- OSSVPV */

static void tie_ossv(OSSV *in, SV **out)
{
  if (! in ) *out = &sv_undef;
  else {
    if (in->natural() == ossv_hv || in->natural() == ossv_av) {
      SV *_tied = sv_setref_pv(sv_newmortal(), in->CLASS(), (void*)in);
      SV *_tmpsv;
      if (in->natural() == ossv_hv) _tmpsv = sv_2mortal((SV*)newHV());
      else _tmpsv = sv_2mortal((SV*)newAV());
      sv_magic(_tmpsv, _tied, in->MAGIC(), Nullch, 0);
      *out = newRV_noinc(_tmpsv);
    } else {
      *out = in->as_sv( *out );
    }
  }
}

OSSVPV::OSSVPV()
  : refs(0)
{}
void OSSVPV::REF_inc() {
  refs++;
#ifdef DEBUG_REFCNT
  warn("OSSVPV::REF_inc() 0x%x to %d", this, refs);
#endif
}
void OSSVPV::REF_dec() { 
  refs--;
#ifdef DEBUG_REFCNT
  warn("OSSVPV::REF_dec() 0x%x to %d", this, refs);
#endif
  if (refs == 0) {
//    warn("OSSVPV::REF_dec() deleting 0x%x", this);
    delete this;
  }
}

os_segment *OSSVPV::get_segment()
{ return os_segment::of(this); }

OSSVPV::~OSSVPV() {}
void OSSVPV::FETCHi(int, SV **) { croak("OSSVPV::FETCH"); }
void OSSVPV::STOREi(int, SV *, SV **) { croak("OSSVPV::STORE"); }
void OSSVPV::FETCHp(char *, SV **) { croak("OSSVPV::FETCH"); }
void OSSVPV::STOREp(char *, SV *, SV **) { croak("OSSVPV::STORE"); }
void OSSVPV::DELETE(char *) { croak("OSSVPV::DELETE"); }
void OSSVPV::CLEAR() { croak("OSSVPV::CLEAR"); }
int OSSVPV::EXISTS(char *) { croak("OSSVPV::EXISTS"); return 0; }
SV *OSSVPV::FIRSTKEY() { croak("OSSVPV::FIRSTKEY"); return 0; }
SV *OSSVPV::NEXTKEY(char *) { croak("OSSVPV::NEXTKEY"); return 0; }

/*--------------------------------------------- OSPV_array */

OSPV_array::OSPV_array()
  : cursor(0), hv(7,8)
{}

OSPV_array::~OSPV_array()
{ CLEAR(); }

int OSPV_array::index_of(char *key)
{
  hkey look(key);
  int ok=0;
  for (int xx=0; xx < hv.count(); xx++) {
    if (hkey::rank(&hv[xx].hk, &look) == 0) return xx;
  }
  return -1;
}

void OSPV_array::FETCHp(char *key, SV **out)
{
  int xx = index_of(key);
  if (xx == -1) {
    tie_ossv(0, out);
  } else {
    tie_ossv(&hv[xx].hv, out);
  }
}

void OSPV_array::STOREp(char *key, SV *value, SV **out)
{
  int xx = index_of(key);
  if (xx == -1) {
    xx = hv.count();
    hv[hv.count()].hk = key;
  }
  hv[xx].hv = value;
  tie_ossv(&hv[xx].hv, out);  // may not be valid if array grows... XXX
}

void OSPV_array::DELETE(char *key)
{
  int xx = index_of(key);
  if (xx != -1) {
    hv[xx].hk.undef();
    hv[xx].hv.undef();
  }
}

void OSPV_array::CLEAR()
{
  cursor = 0;
  while ((cursor = first(cursor)) != -1) {
    hv[cursor].hk.undef();
    hv[cursor].hv.undef();
    cursor++;
  }
}

int OSPV_array::EXISTS(char *key)
{ return index_of(key) != -1; }

int OSPV_array::first(int start)
{
  int xx;
  for (xx=start; xx < hv.count(); xx++) {
    if (hv[xx].hk.valid()) return xx;
  }
  return -1;
}

SV *OSPV_array::FIRSTKEY()
{
  SV *out;
  cursor = first(0);
  if (cursor != -1) {
    out = hv[cursor].hk.as_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_array::NEXTKEY(char *lastkey)
{
  SV *out;
  cursor++;
  cursor = first(cursor);
  if (cursor != -1) {
    out = hv[cursor].hk.as_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

/*--------------------------------------------- OSPV_dict */

OSPV_dict::OSPV_dict()
  : hv(107,
       os_dictionary::signal_dup_keys |
       os_collection::pick_from_empty_returns_null |
       os_dictionary::dont_maintain_cardinality),
    cs(hv)
{}

OSPV_dict::~OSPV_dict()
{ CLEAR(); }

void OSPV_dict::FETCHp(char *key, SV **out)
{
  OSSV *ret = hv.pick(key);
  //	warn("fetch %s => %s", key, ret? ret->as_pv() : "<0x0>");
  tie_ossv(ret, out);
}

void OSPV_dict::STOREp(char *key, SV *nval, SV **out)
{
  os_segment *WHERE = os_segment::of(this);
  OSSV *ossv;

  int insert=0;
  ossv = (OSSV*) hv.pick(key);
  if (!ossv) {
    insert=1;
    ossv = new(WHERE, OSSV::get_os_typespec()) OSSV; //OSNEW
#ifdef DEBUG_MEMORY
    warn("OSPV_dict::STOREp(%s, SV *nval, SV **out): new OSSV = 0x%x", key, ossv);
#endif
  }

  *ossv = nval;
//	warn("insert %s %s", key, ossv->as_pv());
  if (insert) hv.insert(key, ossv);

  tie_ossv(ossv, out);
}

void OSPV_dict::DELETE(char *key)
{
  OSSV *val = hv.pick(key);
  hv.remove_value(key);
#ifdef DEBUG_MEMORY
  warn("OSPV_dict::DELETE(%s) deleting hash value 0x%x", key, val);
#endif
  if (val) delete val;   //XXX val==0 ?
  val = 0;
}

void OSPV_dict::CLEAR()
{
  while (cs.first()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    OSSV *val = hv.pick(k1);
    hv.remove_value(*k1);
#ifdef DEBUG_MEMORY
    warn("OSPV_dict::CLEAR() deleting hash value 0x%x", val);
#endif
    if (val) delete val;
  }
}

int OSPV_dict::EXISTS(char *key)
{
  int out = hv.pick(key) != 0;
//	warn("exists %s => %d", key, RETVAL);
  return out;
}

SV *OSPV_dict::FIRSTKEY()
{
  SV *out;
  if (cs.first()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    assert(k1);
    out = k1->as_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

SV *OSPV_dict::NEXTKEY(char *lastkey)
{
  SV *out;
  if (cs.next()) {
    hkey *k1 = (hkey*) hv.retrieve_key(cs);
    assert(k1);
    out = k1->as_sv();
  } else {
    out = &sv_undef;
  }
  return out;
}

/*--------------------------------------------- util */

static SV *inline_tied(SV *rv)		// snapped from pp_sys.c 5.004
{
    if (! SvROK(rv)) return 0;
    SV *sv = SvRV(rv);
    MAGIC * mg ;
    if (SvMAGICAL(sv)) {
        if (SvTYPE(sv) == SVt_PVHV || SvTYPE(sv) == SVt_PVAV)
            mg = mg_find(sv, 'P') ;
        else
            mg = mg_find(sv, 'q') ;

        if (mg)  {
            return mg->mg_obj;
	}
    }
    return 0;
}

// how does this stuff work?!
static void warn_tie_magic(SV *var)
{
  MAGIC * mg ;

  warn("exploring tie magic 0x%x", var);

  if (SvROK(var)) {
    warn("deref");
    var = SvRV(var);
  }

  warn("SvTYPE(var) = %d", SvTYPE(var));
  if (SvTYPE(var) == SVt_PVHV || SvTYPE(var) == SVt_PVAV) {
    warn("AV or HV");
    mg = mg_find(var, 'P');
    if (mg) warn("tied!");
  } else {
    warn("SV");
    mg = mg_find(var, 'q');
    if (mg) warn("tied SV!");
  }
}

//----------------------------- ObjStore

MODULE = ObjStore	PACKAGE = ObjStore

BOOT:
  objectstore::initialize();		// should delay boot for flexibility XXX
  objectstore::set_thread_locking(0);
  os_collection::set_thread_locking(0);
  os_index_key(hkey, hkey::rank, hkey::hash);

static char *
ObjStore::schema_dir()
	CODE:
	RETVAL = SCHEMADIR;
	OUTPUT:
	RETVAL

static void
ObjStore::begin_update()
	CODE:
	os_transaction::begin(os_transaction::update);

static void
ObjStore::begin_read()
	CODE:
	os_transaction::begin(os_transaction::read_only);

static void
ObjStore::commit()
	CODE:
	os_transaction::commit();

static void
ObjStore::abort()
	CODE:
	os_transaction::abort();

#-----------------------------# Database

MODULE = ObjStore	PACKAGE = ObjStore::Database

static os_database *
os_database::open(pathname, read_only, create_mode)
	char *pathname
	int read_only
	int create_mode

void
os_database::close()

void
os_database::destroy()

void
os_database::decache()

int
os_database::get_default_segment_size()

int
os_database::get_sector_size()

time_t
os_database::time_created()

int
os_database::is_open()

void
os_database::open_mvcc()

int
os_database::is_open_mvcc()

int
os_database::is_open_read_only()

int
os_database::is_writable()

os_segment *
os_database::get_segment(num)
	int num
	CODE:
	char *CLASS = "ObjStore::Segment";
	RETVAL = THIS->get_segment(num);
	OUTPUT:
	RETVAL

void
os_database::get_all_segments()
	PPCODE:
	char *CLASS = "ObjStore::Segment";
	os_int32 num = THIS->get_n_segments();
	os_segment **segs = new os_segment*[num];
	THIS->get_all_segments(num, segs, num);
	EXTEND(sp, num);
	int xx;
	for (xx=0; xx < num; xx++) {
		PUSHs(sv_setref_pv( newSViv(0) , CLASS, segs[xx] ));
	}

OSSV *
os_database::newHV(rep)
	char *rep
	CODE:
	os_segment *arena = THIS->get_default_segment();
	OSSV *sv = new(arena, OSSV::get_os_typespec()) OSSV; //OSNEW
#ifdef DEBUG_MEMORY
	warn("os_database::newHV(%s): OSSV = 0x%x", rep, sv);
#endif
	sv->new_hash(rep);
	RETVAL = sv;
	OUTPUT:
	RETVAL

#-----------------------------# Root

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_database_root *
os_database::create_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

os_database_root *
os_database::find_root(name)
	char *name
	PREINIT:
	char *CLASS = "ObjStore::Root";

MODULE = ObjStore	PACKAGE = ObjStore::Root

void
os_database_root::destroy()
	CODE:
	delete THIS;

OSSV_out *
os_database_root::get_value()
	CODE:
	if (!THIS) XSRETURN_UNDEF;
	RETVAL = (OSSV*) THIS->get_value();
	OUTPUT:
	RETVAL

void
os_database_root::set_value(ossv)
	OSSV_in *ossv
	CODE:
	if (!THIS) croak("ObjStore::ROOT->set_value(nval)");
	OSSV *prior = (OSSV*) THIS->get_value();
	if (prior) {		// check type first XXX
#ifdef DEBUG_MEMORY
	  warn("os_database_root::set_value() deleting old root 0x%x", prior);
#endif
	  delete prior;
	}
	THIS->set_value(ossv, OSSV::get_os_typespec());
	ossv->REF_inc();

#-----------------------------# Transaction (?)

MODULE = ObjStore	PACKAGE = ObjStore::Transaction

static os_transaction *
os_transaction::get_current()

#-----------------------------# Segment

MODULE = ObjStore	PACKAGE = ObjStore::Database

os_segment *
os_database::create_segment()
	PREINIT:
	char *CLASS = "ObjStore::Segment";

MODULE = ObjStore	PACKAGE = ObjStore::Segment

void
os_segment::destroy()

int
os_segment::size()

int
os_segment::get_number()

void
os_segment::set_comment(info)
	char *info
	CODE:
	char short_info[32];
	strncpy(short_info, info, 31);
	short_info[31] = 0;
	THIS->set_comment(short_info);

char *
os_segment::get_comment()

static os_segment *
os_segment::of(ref)
	OSSV_in *ref
	CODE:
	RETVAL = ref->get_segment();
	OUTPUT:
	RETVAL

OSSV *
os_segment::newHV(rep)
	char *rep
	CODE:
	OSSV *sv = new(THIS, OSSV::get_os_typespec()) OSSV; //OSNEW
#ifdef DEBUG_MEMORY
	warn("os_segment::newHV(%s): OSSV = 0x%x", rep, sv);
#endif
	sv->new_hash(rep);
	RETVAL = sv;
	OUTPUT:
	RETVAL

#-----------------------------# HV

MODULE = ObjStore	PACKAGE = ObjStore::HV

int
OSSV::refs()

SV *
OSSV::FETCH(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	ST(0) = sv_newmortal();
	hv->FETCHp(key, & ST(0));

SV *
OSSV::_STORE(key, nval)
	char *key;
	SV *nval;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	ST(0) = sv_newmortal();
	hv->STOREp(key, nval, & ST(0));

void
OSSV::DELETE(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	hv->DELETE(key);

int
OSSV::EXISTS(key)
	char *key;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	RETVAL = hv->EXISTS(key);
	OUTPUT:
	RETVAL

SV *
OSSV::FIRSTKEY()
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	ST(0) = hv->FIRSTKEY();

SV *
OSSV::NEXTKEY(lastkey)
	char *lastkey;
	CODE:
	if (!THIS) croak("THIS invalid");
	if (THIS->natural() != ossv_hv) croak("THIS must be hash");
	OSSVPV *hv = (OSSVPV *) THIS->ref;
	assert(hv);
	ST(0) = hv->NEXTKEY(lastkey);

