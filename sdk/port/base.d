// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module sdk.port.base;

version = Win8;
version = sdk;
version(sdk) {} else version = vsi;

version(sdk) {
	public import sdk.win32.windef;
	public import sdk.win32.winnt;
	public import sdk.win32.wtypes;
	public import sdk.win32.ntstatus;
	public import sdk.win32.winbase;
	public import sdk.win32.winuser;
	public import sdk.win32.winerror;
	public import sdk.win32.wingdi;
	public import core.vararg;
} else {
	public import std.c.windows.windows;
	public import std.c.windows.com;
	public import sdk.win32.wtypes;
}

public import sdk.port.pp;
public import sdk.port.bitfields;

/*
union CY
{
	struct {
		uint  Lo;
		int   Hi;
	};
	long int64;
}
*/

//alias long LONGLONG;
//alias ulong ULONGLONG;

version(sdk)
{
	enum _WIN32_WINNT = 0x600;

	alias char CHAR;
//	alias short SHORT;
	alias int LONG;
	alias int HRESULT;

// needed by Windows SDK 8.0
//	alias int INT;
//	alias uint UINT;

	struct GUID { uint Data1; ushort Data2; ushort Data3; ubyte[8] Data4; }
	alias GUID *LPGUID;
	alias GUID *LPCGUID;
	alias GUID *REFGUID;

	alias GUID IID;
	alias GUID *LPIID;
	alias GUID *REFIID;

	alias GUID CLSID;
	//alias GUID *LPCLSID;
	alias GUID *REFCLSID;

	alias GUID FMTID;
	alias GUID *LPFMTID;
	alias GUID *REFFMTID;
}
alias GUID *LPCLSID;

alias void * I_RPC_HANDLE;

alias long hyper;
alias wchar wchar_t;

alias ushort _VARIANT_BOOL;
alias DWORD OLE_COLOR;
alias bool boolean;
alias ulong uint64;

version(sdk) {}
else {
	alias double DOUBLE;
//	alias ushort _VARIANT_BOOL;
	alias int INT_PTR;
	alias uint ULONG_PTR;
	alias uint DWORD_PTR;
	alias int LONG_PTR;
	alias ulong ULARGE_INTEGER;
	alias long LARGE_INTEGER;
	alias ulong ULONG64;
	alias long LONG64;
	alias ulong DWORD64;
	alias ulong UINT64;
	alias long INT64;
	alias int INT32;
	alias uint UINT32;
	alias int LONG32;
	alias uint ULONG32;

	alias uint SIZE_T;
	alias uint FMTID;
	//alias uint LCID;
	//alias uint DISPID;

	version(D_Version2) {} else
	{
	alias uint UINT_PTR;
	}
}

version(D_Version2) {} else
{
	alias LONG SCODE;
}

enum uint UINT_MAX = uint.max;

alias LONG NTSTATUS;

struct _PROC_THREAD_ATTRIBUTE_LIST;
struct _EXCEPTION_REGISTRATION_RECORD;
struct _TP_CALLBACK_INSTANCE;
struct _TP_POOL;
struct _TP_WORK;
struct _TP_TIMER;
struct _TP_WAIT;
struct _TP_IO;
struct _TP_CLEANUP_GROUP;
struct _ACTIVATION_CONTEXT;
struct _TEB;

alias HANDLE HMETAFILEPICT;

alias LPRECT LPCRECT;
alias LPRECT LPCRECTL;

enum STACK_ALIGN = 4;

int ALIGN_UP_BY(uint sz, uint algn) { return (sz + algn - 1) & ~(algn-1); }

int V_INT_PTR(void* p) { return cast(int) p; }
uint V_UINT_PTR(void* p) { return cast(uint) p; }

// for winnt.d (7.1)
struct _PACKEDEVENTINFO;
struct _EVENTSFORLOGFILE;

// for winuser.d (7.1)
alias HANDLE HPOWERNOTIFY;

// for prsht.d
struct _PSP;
struct _PROPSHEETPAGEA;
struct _PROPSHEETPAGEW;

// for commctrl.d
struct _IMAGELIST {}
struct _TREEITEM;
struct _DSA;
struct _DPA;
interface IImageList {}
// 7.1
enum CCM_TRANSLATEACCELERATOR = (WM_USER+97);

// msdbg*.d
alias ULONG32 XINT32;

// Win SDK 10.0.22621.0
struct _UNWIND_HISTORY_TABLE;

version(sdk) {}
else {

struct _RECTL
{
    LONG    left;
    LONG    top;
    LONG    right;
    LONG    bottom;
}
alias _RECTL RECTL; alias _RECTL *PRECTL; alias _RECTL *LPRECTL;

struct tagSIZEL
{
    LONG cx;
    LONG cy;
}
alias tagSIZEL SIZEL; alias tagSIZEL *PSIZEL; alias tagSIZEL *LPSIZEL;
alias tagSIZEL SIZE;

struct _POINTL
{
    LONG  x;
    LONG  y;
}
alias _POINTL POINTL; alias _POINTL *PPOINTL;

struct _POINTS
{
    SHORT x;
    SHORT y;
}
alias _POINTS POINTS; alias _POINTS *PPOINTS;

struct LOGFONTW
{
    LONG      lfHeight;
    LONG      lfWidth;
    LONG      lfEscapement;
    LONG      lfOrientation;
    LONG      lfWeight;
    BYTE      lfItalic;
    BYTE      lfUnderline;
    BYTE      lfStrikeOut;
    BYTE      lfCharSet;
    BYTE      lfOutPrecision;
    BYTE      lfClipPrecision;
    BYTE      lfQuality;
    BYTE      lfPitchAndFamily;
    WCHAR[32] lfFaceName;
}
alias LOGFONTW* PLOGFONTW, NPLOGFONTW, LPLOGFONTW;
} // !sdk

//enum OLE_E_LAST = 0x800400FF;

version(vsi)
{
enum WM_USER = 0x400;

// from winerror.h
enum SEVERITY_SUCCESS    = 0;
enum SEVERITY_ERROR      = 1;

}
HRESULT MAKE_HRESULT(uint sev, uint fac, uint code) { return cast(HRESULT) ((sev<<31) | (fac<<16) | code); }
SCODE   MAKE_SCODE(uint sev, uint fac, uint code)   { return cast(SCODE)   ((sev<<31) | (fac<<16) | code); }

version(none)
{

// from adserr.h
enum FACILITY_WINDOWS                 = 8;
enum FACILITY_STORAGE                 = 3;
enum FACILITY_RPC                     = 1;
enum FACILITY_SSPI                    = 9;
enum FACILITY_WIN32                   = 7;
enum FACILITY_CONTROL                 = 10;
enum FACILITY_NULL                    = 0;
enum FACILITY_ITF                     = 4;
enum FACILITY_DISPATCH                = 2;

// from commctrl.h
enum TV_FIRST                = 0x1100;      // treeview messages
enum TVN_FIRST               = (0U-400U);   // treeview notifications
}

version(none)
{
extern(Windows) UINT RegisterClipboardFormatW(LPCWSTR lpszFormat);

UINT RegisterClipboardFormatW(wstring format)
{
	format ~= "\0"w;
	return RegisterClipboardFormatW(cast(LPCWSTR) format.ptr);
}
}

// alias /+[unique]+/ FLAGGED_WORD_BLOB * wireBSTR;

version(Win8) {} else
struct FLAGGED_WORD_BLOB
{
                        uint    fFlags;
                        uint    clSize;
    /+[size_is(clSize)]+/   ushort[0]   asData;
}

version(vsi)
{
enum prjBuildActionCustom = 3;

}

version(none)
{
enum {
	CLR_NONE                = 0xFFFFFFFF,
	CLR_DEFAULT             = 0xFF000000,
}

enum { IMAGE_BITMAP = 0, IMAGE_ICON = 1, IMAGE_CURSOR = 2, IMAGE_ENHMETAFILE = 3 };

enum {
	LR_DEFAULTCOLOR     = 0x00000000,
	LR_MONOCHROME       = 0x00000001,
	LR_COLOR            = 0x00000002,
	LR_COPYRETURNORG    = 0x00000004,
	LR_COPYDELETEORG    = 0x00000008,
	LR_LOADFROMFILE     = 0x00000010,
	LR_LOADTRANSPARENT  = 0x00000020,
	LR_DEFAULTSIZE      = 0x00000040,
	LR_VGACOLOR         = 0x00000080,
	LR_LOADMAP3DCOLORS  = 0x00001000,
	LR_CREATEDIBSECTION = 0x00002000,
	LR_COPYFROMRESOURCE = 0x00004000,
	LR_SHARED           = 0x00008000,
}
}

///////////////////////////////////////////////////////////////////////////////
// incomplete structs

///////////////////////////////////////////////////////////////////////////////
uint strtohex(string s)
{
	uint hex = 0;
	for(int i = 0; i < s.length; i++)
	{
		int dig;
		if(s[i] >= '0' && s[i] <= '9')
			dig = s[i] - '0';
		else if(s[i] >= 'a' && s[i] <= 'f')
			dig = s[i] - 'a' + 10;
		else if(s[i] >= 'A' && s[i] <= 'F')
			dig = s[i] - 'A' + 10;
		else
			assert(false, "invalid hex digit");
		hex = (hex << 4) | dig;
	}
	return hex;
}

GUID uuid(string g)
{
//	return GUID(0, 0, 0, [ 0, 0, 0, 0, 0, 0, 0, 0 ]);

	if(g.length == 38)
	{
		assert(g[0] == '{' && g[$-1] == '}', "Incorrect format for GUID.");
		g = g[1 .. $-1];
	}
	assert(g.length == 36);
	assert(g[8] == '-' && g[13] == '-' && g[18] == '-' && g[23] == '-', "Incorrect format for GUID.");

	uint Data1 = strtohex(g[0..8]);
	ushort Data2 = cast(ushort)strtohex(g[9..13]);
	ushort Data3 = cast(ushort)strtohex(g[14..18]);
	ubyte b0 = cast(ubyte)strtohex(g[19..21]);
	ubyte b1 = cast(ubyte)strtohex(g[21..23]);

	ubyte b2 = cast(ubyte)strtohex(g[24..26]);
	ubyte b3 = cast(ubyte)strtohex(g[26..28]);
	ubyte b4 = cast(ubyte)strtohex(g[28..30]);
	ubyte b5 = cast(ubyte)strtohex(g[30..32]);
	ubyte b6 = cast(ubyte)strtohex(g[32..34]);
	ubyte b7 = cast(ubyte)strtohex(g[34..36]);

	return GUID(Data1, Data2, Data3, [ b0, b1, b2, b3, b4, b5, b6, b7 ]);
}

const GUID const_GUID_NULL = { 0, 0, 0, [ 0, 0, 0, 0,  0, 0, 0, 0 ] };

const GUID GUID_NULL;
const IID IID_IUnknown = uuid("00000000-0000-0000-C000-000000000046");

///////////////////////////////////////////////////////////////////////////////
// functions declared in headers, but not found in import libraries
///////////////////////////////////////////////////////////////////////////////

/+
InterlockedBitTestAndSet
InterlockedBitTestAndReset
InterlockedBitTestAndComplement
YieldProcessor
ReadPMC
ReadTimeStampCounter
DbgRaiseAssertionFailure
GetFiberData
GetCurrentFiber
NtCurrentTeb
+/

version(Win8) {
///////////////////////////////////////////////////////////////////////////////
// used as intrinsics in Windows SDK 8.0
extern(Windows) LONG InterlockedAdd (LONG /*volatile*/ *Destination, LONG Value);
alias InterlockedAdd _InterlockedAdd;

extern(Windows) LONG InterlockedAnd (LONG /*volatile*/ *Destination, LONG Value);
alias InterlockedAnd _InterlockedAnd;

extern(Windows) LONG InterlockedOr (LONG /*volatile*/ *Destination, LONG Value);
alias InterlockedOr _InterlockedOr;

extern(Windows) LONG InterlockedXor (LONG /*volatile*/ *Destination, LONG Value);
alias InterlockedXor _InterlockedXor;

version(Win64)
{
	private import core.atomic;

	LONG InterlockedIncrement (/*__inout*/ LONG /*volatile*/ *Addend)
	{
		return atomicOp!"+="(*cast(shared(LONG)*)Addend, 1);
	}
	LONG InterlockedDecrement (/*__inout*/ LONG /*volatile*/ *Addend)
	{
		return atomicOp!"+="(*cast(shared(LONG)*)Addend, -1);
	}
	LONG InterlockedExchange (/*__inout*/ LONG /*volatile*/ *Target, /*__in*/ LONG Value)
	{
		LONG old;
		do
			old = *Target;
		while( !cas( cast(shared(LONG)*)Target, old, Value ) );
		return old;
	}
	LONG InterlockedExchangeAdd (/*__inout*/ LONG /*volatile*/ *Target, /*__in*/ LONG Value)
	{
		LONG old;
		do
			old = *Target;
		while( !cas( cast(shared(LONG)*)Target, old, old + Value ) );
		return old;
	}
	LONG InterlockedCompareExchange (/*__inout*/ LONG /*volatile*/ *Destination, /*__in*/ LONG ExChange, /*__in*/ LONG Comperand)
	{
		if( cas( cast(shared(LONG)*)Destination, Comperand, ExChange ) )
			return Comperand;
		return Comperand - 1;
	}
}
else
{
extern(Windows) LONG InterlockedIncrement (/*__inout*/ LONG /*volatile*/ *Addend);
extern(Windows) LONG InterlockedDecrement (/*__inout*/ LONG /*volatile*/ *Addend);

extern(Windows) LONG InterlockedExchange (/*__inout*/ LONG /*volatile*/ *Target, /*__in*/ LONG Value);
extern(Windows) LONG InterlockedExchangeAdd (/*__inout*/ LONG /*volatile*/ *Target, /*__in*/ LONG Value);

extern(Windows) LONG InterlockedCompareExchange (/*__inout*/ LONG /*volatile*/ *Destination, /*__in*/ LONG ExChange, /*__in*/ LONG Comperand);
}

extern(Windows)
LONGLONG /*__cdecl*/ InterlockedCompareExchange64 (
								  /*__inout*/ LONGLONG /*volatile*/ *Destination,
								  /*__in*/    LONGLONG ExChange,
								  /*__in*/    LONGLONG Comperand
								  );

alias void ReadULongPtrAcquire;
alias void ReadULongPtrNoFence;
alias void ReadULongPtrRaw;
alias void WriteULongPtrRelease;
alias void WriteULongPtrNoFence;
alias void WriteULongPtrRaw;

     version(GNU)     extern(C) DWORD __readfsdword (DWORD Offset) { assert(0); }
else version(AArch64) extern(C) DWORD __readfsdword (DWORD Offset) { assert(0); }
else                  extern(C) DWORD __readfsdword (DWORD Offset) { asm { naked; mov EAX,[ESP+4]; mov EAX, FS:[EAX]; } }

enum TRUE = 1;
public import sdk.win32.winbase;
//enum FALSE = 0;

alias void _CONTRACT_DESCRIPTION;
alias void _BEM_REFERENCE;

struct tagPROPVARIANT;

public import sdk.port.propidl;
}
