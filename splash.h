/*
 * Version 1.91
 * Written by Jim Morris,  morris@netcom.com
 * Kudos to Larry Wall for inventing Perl
 * Copyrights only exist on the regex stuff, and all have been left intact.
 * The only thing I ask is that you let me know of any nifty fixes or
 * additions.
 * 
 * Credits:
 * I'd like to thank Michael Golan <mg@Princeton.EDU> for his critiques
 * and clever suggestions. Some of which have actually been implemented
 *
 * 06-19-97 Pritikin - Hacked for use with ObjectStore!
 */

#ifndef	_SPLASH_H
#define	_SPLASH_H

#include <string.h>

#ifdef	DEBUG
#include	<stdio.h>
#endif

#define	INLINE	inline

// ************************************************************
// This is the base class for SPList, it handles the underlying
// dynamic array mechanism
// ************************************************************

template<class T>
class SPListBase
{
private:
    enum{ALLOCINC=20};
    T *a;
    int cnt;
    int first;
    int allocated;
    int allocinc;
    int firstshift;
    void grow(int amnt= 0, int newcnt= -1);

protected:
    void compact(const int i);

public:
#ifdef	USLCOMPILER
    // USL 3.0 bug with enums losing the value
    SPListBase(int n= 20, int fs = 1)
#else
    SPListBase(int n= ALLOCINC, int fs = 1)
#endif
    {
      os_segment *WHERE = os_segment::of(this);
	a= new(WHERE, T::get_os_typespec(), n) T[n];
	cnt= 0;
	firstshift = fs;
        first= n>>firstshift;
	allocated= n;
	allocinc= n;
#	ifdef	DEBUG
	fprintf(stderr, "SPListBase(int %d) a= %p, first= %d\n", allocinc, a, first);
#	endif
    }

    SPListBase(const SPListBase<T>& n);
    SPListBase<T>& SPListBase<T>::operator=(const SPListBase<T>& n);
    virtual ~SPListBase(){
#       ifdef	DEBUG
	fprintf(stderr, "~SPListBase() a= %p, allocinc= %d\n", a, allocinc);
#       endif
	delete [] a;
    }

    INLINE T& operator[](const int i);
    INLINE const T& operator[](const int i) const;

    int count(void) const{ return cnt; }

    void add(const T& n);
    void add(const int i, const T& n);
    void erase(void){ cnt= 0; first= (allocated>>firstshift);}
};

// ************************************************************
// SPList
// ************************************************************

template <class T>
class SPList: private SPListBase<T>
{
public:
    SPList(int sz= 10, int fs=1): SPListBase<T>(sz, fs){}
    
    // stuff I want public to see from SPListBase
    T& operator[](const int i){return SPListBase<T>::operator[](i);}
    const T& operator[](const int i) const{return SPListBase<T>::operator[](i);}
    SPListBase<T>::count;   // some compilers don''t like this

    // add perl-like synonyms
    void reset(void){ erase(); }
    int scalar(void) const { return count(); }

    operator void*() { return count()?this:0; } // so it can be used in tests
    int isempty(void) const{ return !count(); } // for those that don''t like the above (hi michael)

    T pop(void);

    void push(const T& a){ add(a);}
    void push(const SPList<T>& l);

    T shift(void);
    
    int unshift(const T& ent){ add(0, ent); return count(); }
    int unshift(const SPList<T>& l);

    SPList<T> splice(int offset, int len, const SPList<T>& l);
    SPList<T> splice(int offset, int len);
    SPList<T> splice(int offset);
};

// ************************************************************
// Implementation of template functions for splistbase
// ************************************************************

template <class T>
INLINE T& SPListBase<T>::operator[](const int i)
{
    assert((i >= 0) && (first >= 0) && ((first+cnt) <= allocated));
    int indx= first+i;
        
    if(indx >= allocated){  // need to grow it
	grow((indx-allocated)+allocinc, i+1); // index as yet unused element
	indx= first+i;			  // first will have changed in grow()
    }
    assert(indx >= 0 && indx < allocated);

    if(i >= cnt) cnt= i+1;  // it grew
    return a[indx];
}

template <class T>
INLINE const T& SPListBase<T>::operator[](const int i) const
{
     assert((i >= 0) && (i < cnt));
     return a[first+i];
}

template <class T>
SPListBase<T>::SPListBase(const SPListBase<T>& n)
{
    allocated= n.allocated;
    allocinc= n.allocinc;
    cnt= n.cnt;
    first= n.first;
    os_segment *WHERE = os_segment::of(this);
    a= new(WHERE, T::get_os_typespec(), allocated) T[allocated];
    for(int i=0;i<cnt;i++) a[first+i]= n.a[first+i];
#ifdef	DEBUG
    fprintf(stderr, "SPListBase(SPListBase&) a= %p, source= %p\n", a, n.a);
#endif

}

template <class T>
SPListBase<T>& SPListBase<T>::operator=(const SPListBase<T>& n){
//  cout << "SPListBase<T>::operator=()" << endl;
    if(this == &n) return *this;
#ifdef	DEBUG
    fprintf(stderr, "~operator=(SPListBase&) a= %p\n", a);
#endif
    delete [] a; // get rid of old one
    allocated= n.allocated;
    allocinc= n.allocinc;
    cnt= n.cnt;
    first= n.first;
    os_segment *WHERE = os_segment::of(this);
    a= new(WHERE, T::get_os_typespec(), allocated) T[allocated];
    for(int i=0;i<cnt;i++) a[first+i]= n.a[first+i];
#ifdef	DEBUG
    fprintf(stderr, "operator=(SPListBase&) a= %p, source= %p\n", a, n.a);
#endif
    return *this;
}
/* 
** increase size of array, default means array only needs
** to grow by at least 1 either at the end or start
** First tries to re-center the first pointer
** Then will increment the array by the inc amount
*/
template <class T>
void SPListBase<T>::grow(int amnt, int newcnt){
int newfirst;
    
    if(amnt <= 0){ // only needs to grow by 1
        newfirst= (allocated>>firstshift) - (cnt>>firstshift); // recenter first
        if(newfirst > 0 && (newfirst+cnt+1) < allocated){ // this is all we need to do
            for(int i=0;i<cnt;i++){ // move rest up or down
                int idx= (first > newfirst) ? i : cnt-1-i;
                a[newfirst+idx]= a[first+idx];
	    }
#ifdef DEBUG
            fprintf(stderr, "SPListBase::grow() moved a= %p, first= %d, newfirst= %d, amnt= %d, cnt= %d, allocated= %d\n",
                    a, first, newfirst, amnt, cnt, allocated);
#endif
           first= newfirst;
           return;
        }
    }

    // that wasn''t enough, so allocate more space
    if(amnt <= 0) amnt= allocinc; // default value
    if(newcnt < 0) newcnt= cnt;   // default
    allocated += amnt;
    os_segment *WHERE = os_segment::of(a);
    T *tmp= new(WHERE, T::get_os_typespec(),allocated) T[allocated];
    newfirst= (allocated>>1) - (newcnt>>1);
    for(int i=0;i<cnt;i++) tmp[newfirst+i].operator=(&a[first+i]);
#ifdef	DEBUG
    fprintf(stderr, "SPListBase::grow() a= %p, old= %p, allocinc= %d, first= %d, amnt= %d, cnt= %d, allocated= %d\n",
            tmp, a, allocinc, first, amnt, cnt, allocated);
    fprintf(stderr, "~SPListBase::grow() a= %p\n", a);
#endif
    delete [] a;
    a= tmp;
    first= newfirst;
}

template <class T>
void SPListBase<T>::add(const T& n){
    if(cnt+first >= allocated) grow();
    assert((cnt+first) < allocated);
    a[first+cnt]= n;
#ifdef DEBUG
    fprintf(stderr, "add(const T& n): first= %d, cnt= %d, idx= %d, allocated= %d\n",
                first, cnt, first+cnt, allocated);
#endif
    cnt++;
}

template <class T>
void SPListBase<T>::add(const int ip, const T& n){
    assert(ip >= 0 && ip <= cnt);
    if(ip == 0){ // just stick it on the bottom
    	if(first <= 0) grow(); // make room at bottom for one more
    	assert(first > 0);
        first--;
        a[first]= n;
    }else{
        if((first+cnt+1) >= allocated) grow(); // make room at top for one more
        assert((first+cnt) < allocated && (first+ip) < allocated);
        for(int i=cnt;i>ip;i--) // shuffle up
	    a[first+i]= a[(first+i)-1];
        a[first+ip]= n;
    }
#ifdef DEBUG
    fprintf(stderr, "add(const int ip, const T& n): first= %d, cnt= %d, idx= %d, allocated= %d\n",
                first, cnt, first+ip, allocated);
#endif
    cnt++;
}

template <class T>
void SPListBase<T>::compact(const int n){ // shuffle down starting at n
int i;
    assert((n >= 0) && (n < cnt));
    if(n == 0) first++;
    else for(i=n;i<cnt-1;i++){
	    a[first+i]= a[(first+i)+1];
    }
    cnt--;
}

// ************************************************************
// implementation of template functions for SPList
// ************************************************************
template <class T>
T SPList<T>::pop(void)
{
T tmp;
int n= count()-1;
    if(n >= 0){
	tmp= (*this)[n];
	compact(n);
    }
    return tmp;
}

template <class T>
T SPList<T>::shift(void)
{
T tmp= (*this)[0];
    compact(0);
    return tmp;
}

template <class T>
void SPList<T>::push(const SPList<T>& l)
{
    for(int i=0;i<l.count();i++)
	add(l[i]);
}

template <class T>
int SPList<T>::unshift(const SPList<T>& l)
{
    for(int i=l.count()-1;i>=0;i--)
	unshift(l[i]);
    return count();
}

template <class T>
SPList<T> SPList<T>::splice(int offset, int len, const SPList<T>& l)
{
SPList<T> r= splice(offset, len);

    if(offset > count()) offset= count();
    for(int i=0;i<l.count();i++){
	add(offset+i, l[i]);	// insert into list
    }
    return r;
}

template <class T>
SPList<T>  SPList<T>::splice(int offset, int len)
{
SPList<T> r;
int i;

    if(offset >= count()) return r;
    for(i=offset;i<offset+len;i++){
    	r.add((*this)[i]);
    }

    for(i=offset;i<offset+len;i++)
	compact(offset);
    return r;
}

template <class T>
SPList<T>  SPList<T>::splice(int offset)
{
SPList<T> r;
int i;

    if(offset >= count()) return r;
    for(i=offset;i<count();i++){
	r.add((*this)[i]);
    }

    int n= count(); // count() will change so remember what it is
    for(i=offset;i<n;i++)
	compact(offset);
    return r;
}



#endif

