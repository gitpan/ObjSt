// aim for generic & excellent scalability

#ifdef __cplusplus
extern "C" {
#endif
#define __attribute__(attr)
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include <ostore/ostore.hh>
#include <ostore/coll.hh>
#include <ostore/coll/dict_pt.hh>

#undef DEBUG   // where did this get defined?
//#define DEBUG
#include "splash.h"

enum ossvtype {
  ossv_undef=1,
  ossv_iv=2,
  ossv_nv=3,
  ossv_pv=4,
  ossv_rv=5,	// alien data (not implemented - needs MOP support)
  ossv_av=6,    // ref counted containers
  ossv_hv=7
};

struct OSSV {
  static os_typespec *get_os_typespec();
  static char strrep[32];
  ossvtype _type;
  void *ref;
  union {
    os_int32 iv;
    double nv;
    os_unsigned_int32 len;
  };

  //init
  OSSV();
  OSSV(SV *);
  OSSV(OSSV *);
  ~OSSV();
  OSSV *operator =(SV *);
  OSSV *operator =(OSSV *);
  //what
  os_int32 discriminant();
  int morph(ossvtype nty);
  ossvtype natural();
  char *Type();
  char *CLASS();
  char MAGIC();
  os_segment *get_segment();
  //refcnt
  int refs();
  void REF_inc(void *foo=0);
  void REF_dec();
  //set
  void undef();
  void s(os_int32);
  void s(double);
  void s(char *, os_unsigned_int32 len);
  void s(OSSV *);
  void new_array(char *rep);
  void new_hash(char *rep);
  //get
  os_int32 as_iv();
  double as_nv();
  char *as_pv();
  os_unsigned_int32 as_pvn();
  SV *as_sv(SV*);           // always use returned value - may return &sv_undef
};

#define HKEY_MAXLEN 12

struct hkey {
  static os_typespec *get_os_typespec();
  char str[HKEY_MAXLEN];
  hkey();
  hkey(const hkey &);
  hkey(const char *);
  int valid();
  void undef();
  hkey *operator=(hkey *);
  hkey *operator=(char *k1);
  SV *as_sv();
  static int rank(const void *s1, const void *s2);
  static os_unsigned_int32 hash(const void *s1);
};

struct hent {
  static os_typespec *get_os_typespec();
  hkey hk;
  OSSV hv;
  hent *operator=(hent *);
};

// OSSVPV - Used for tieing both hashes & arrays.

// The return protocol is inconsistent for historical reasons.  Why is
// the most efficient way to manipulate the perl stack?

struct OSSVPV {
  static os_typespec *get_os_typespec();
  int refs;
  OSSVPV();
  virtual ~OSSVPV();
  void REF_inc();
  void REF_dec();
  virtual os_segment *get_segment();
  // array
  virtual void FETCHi(int xx, SV **out);
  virtual void STOREi(int xx, SV *value, SV **out);
  // hash
  virtual void FETCHp(char *key, SV **out);
  virtual void STOREp(char *key, SV *value, SV **out);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
};

struct OSPV_dict : OSSVPV {
  static os_typespec *get_os_typespec();
  os_Dictionary < hkey, OSSV* > hv;
  os_cursor cs;
  OSPV_dict();
  virtual ~OSPV_dict();
  virtual void FETCHp(char *key, SV **out);
  virtual void STOREp(char *key, SV *value, SV **out);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
};

struct OSPV_array : OSSVPV {
  static os_typespec *get_os_typespec();
  SPList < hent > hv;
  int cursor;
  OSPV_array();
  virtual ~OSPV_array();
  int index_of(char *key);
  int first(int start);
  virtual void FETCHp(char *key, SV **out);
  virtual void STOREp(char *key, SV *value, SV **out);
  virtual void DELETE(char *key);
  virtual void CLEAR();
  virtual int EXISTS(char *key);
  virtual SV *FIRSTKEY();
  virtual SV *NEXTKEY(char *lastkey);
};
