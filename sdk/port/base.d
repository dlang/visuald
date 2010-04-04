module sdk.port.base;

version(sdk) {} else version = vsi;
//version = sdk;

version(sdk) {
	public import sdk.win32.windef;
	public import sdk.win32.winnt;
	public import sdk.win32.ntstatus;
	public import sdk.win32.winbase;
	public import std.stdarg;
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
	const _WIN32_WINNT = 0x600;

	alias char CHAR;
	alias short SHORT;
	alias long LONG;
	alias int HRESULT;
//	alias int INT;

	struct GUID { uint Data1; ushort Data2; ushort Data3; ubyte Data4[ 8 ]; }
	alias GUID CLSID;
	alias GUID *LPGUID;
	alias GUID *LPCGUID;
}

alias long hyper;
alias wchar wchar_t;

version(sdk) {} else {
alias double DOUBLE;
alias bool boolean;
alias ushort _VARIANT_BOOL;
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

const uint UINT_MAX = uint.max;

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

alias GUID *LPCLSID;
alias LPRECT LPCRECT;
alias LPRECT LPCRECTL;

int V_INT_PTR(void* p) { return cast(int) p; }
uint V_UINT_PTR(void* p) { return cast(uint) p; }

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
    WCHAR     lfFaceName[32 ];
}
alias LOGFONTW* PLOGFONTW, NPLOGFONTW, LPLOGFONTW;

const OLE_E_LAST = 0x800400FF;

version(vsi)
{
const WM_USER = 0x400;

// from winerror.h
const SEVERITY_SUCCESS    = 0;
const SEVERITY_ERROR      = 1;

SCODE   MAKE_SCODE(uint sev, uint fac, uint code)   { return cast(SCODE)   ((sev<<31) | (fac<<16) | code); }
HRESULT MAKE_HRESULT(uint sev, uint fac, uint code) { return cast(HRESULT) ((sev<<31) | (fac<<16) | code); }
}

// from adserr.h
const FACILITY_WINDOWS                 = 8;
const FACILITY_STORAGE                 = 3;
const FACILITY_RPC                     = 1;
const FACILITY_SSPI                    = 9;
const FACILITY_WIN32                   = 7;
const FACILITY_CONTROL                 = 10;
const FACILITY_NULL                    = 0;
const FACILITY_ITF                     = 4;
const FACILITY_DISPATCH                = 2;

// from commctrl.h
const TV_FIRST                = 0x1100;      // treeview messages
const TVN_FIRST               = (0U-400U);   // treeview notifications

extern(Windows) UINT RegisterClipboardFormatW(LPCWSTR lpszFormat);

UINT RegisterClipboardFormatW(wstring format)
{
	format ~= "\0"w;
	return RegisterClipboardFormatW(format.ptr);
}

// alias /+[unique]+/ FLAGGED_WORD_BLOB * wireBSTR;

struct FLAGGED_WORD_BLOB
{
                        uint    fFlags;
                        uint    clSize;
    /+[size_is(clSize)]+/   ushort   asData[0];
}

version(vsi)
{
const prjBuildActionCustom = 3;

// VSI specifics
IUnknown DOCDATAEXISTING_UNKNOWN;

static this() { *cast(int*)&DOCDATAEXISTING_UNKNOWN = -1; }

enum TokenType : int
{
	Unknown,
	Text,
	Keyword,
	Identifier,
	String,
	Literal,
	Operator,
	Delimiter,
	LineComment,
	Comment
}

enum TokenColor : int
{
	Text,
	Keyword,
	Comment,
	Identifier,
	String,
	Literal,
};

GUID GUID_COMPlusNativeEng = { 0x92EF0900, 0x2251, 0x11D2, [ 0xB7, 0x2E, 0x00, 0x00, 0xF8, 0x75, 0x72, 0xEF ] };
}

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

