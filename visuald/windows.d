module windows;

HRESULT HResultFromLastError()
{
	return HRESULT_FROM_WIN32(GetLastError());
}

int GET_X_LPARAM(LPARAM lp)
{
	return cast(int)cast(short)LOWORD(lp);
}

int GET_Y_LPARAM(LPARAM lp)
{
	return cast(int)cast(short)HIWORD(lp);
}

int MAKELPARAM(int lo, int hi)
{
	return (lo & 0xffff) | (hi << 16);
}

COLORREF RGB(int r, int g, int b)
{
	return cast(COLORREF)(cast(BYTE)r | ((cast(uint)cast(BYTE)g)<<8) | ((cast(uint)cast(BYTE)b)<<16));
}

struct SHFILEINFOW
{
	HICON       hIcon;                      // out: icon
	int         iIcon;                      // out: icon index
	DWORD       dwAttributes;               // out: SFGAO_ flags
	WCHAR       szDisplayName[MAX_PATH];    // out: display name (or path)
	WCHAR       szTypeName[80];             // out: type name
}
alias SHFILEINFOW SHFILEINFO;

extern(Windows)
DWORD_PTR SHGetFileInfoW(LPCWSTR pszPath, DWORD dwFileAttributes, SHFILEINFOW *psfi, 
						 UINT cbFileInfo, UINT uFlags);

const SHGFI_ICON              = 0x000000100;     // get icon
const SHGFI_DISPLAYNAME       = 0x000000200;     // get display name
const SHGFI_TYPENAME          = 0x000000400;     // get type name
const SHGFI_LARGEICON         = 0x000000000;     // get large icon
const SHGFI_SMALLICON         = 0x000000001;     // get small icon
const SHGFI_OPENICON          = 0x000000002;     // get open icon
const SHGFI_SHELLICONSIZE     = 0x000000004;     // get shell size icon
const SHGFI_PIDL              = 0x000000008;     // pszPath is a pidl
const SHGFI_USEFILEATTRIBUTES = 0x000000010;    // use passed dwFileAttribute

const WM_SYSTIMER = 0x118;

version(all)
{
	public import sdk.port.base;
	
	const GUID GUID_NULL;
	const IID IID_IUnknown = uuid("00000000-0000-0000-C000-000000000046");

	HRESULT HRESULT_FROM_WIN32(uint x)
	{
		return cast(HRESULT)(x) <= 0 ? cast(HRESULT)(x) 
									 : cast(HRESULT) (((x) & 0x0000FFFF) | (FACILITY_WIN32 << 16) | 0x80000000);
	}

	extern(Windows)
	{
		export uint GetThreadLocale();
		
		UINT DragQueryFileW(HANDLE hDrop, UINT iFile, LPWSTR lpszFile, UINT cch);
		HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);
	}
}
else
{
struct s_IMAGELIST;
alias s_IMAGELIST *HIMAGELIST;

		export HIMAGELIST ImageList_LoadImageA(HINSTANCE hi, LPCTSTR lpbmp, int cx, int cGrow, COLORREF crMask, UINT uType, UINT uFlags);
		export BOOL ImageList_Destroy(HIMAGELIST imgl);

	public import std.c.windows.windows;
	public import std.c.windows.com;

extern(Windows) export BSTR SysAllocString(in wchar* str);
extern(Windows) export BSTR SysAllocStringLen(in wchar* str, int len);
extern(Windows) export BSTR SysFreeString(BSTR str);
extern(Windows) export void* CoTaskMemAlloc(int sz);
extern(Windows) export void CoTaskMemFree(void* ptr);

extern(Windows) export int StringFromGUID2(in GUID *rguid, LPOLESTR lpsz, int cbMax);

enum { DISP_E_MEMBERNOTFOUND = -2147352573 }

enum
{
	OLE_E_FIRST = 0x80040000,
	OLE_E_LAST  = 0x800400FF,

	OLE_E_OLEVERB                    = 0x80040000, // Invalid OLEVERB structure
	OLE_E_ADVF                       = 0x80040001, // Invalid advise flags
	OLE_E_ENUM_NOMORE                = 0x80040002, // Can't enumerate any more, because the associated data is missing
	OLE_E_ADVISENOTSUPPORTED         = 0x80040003, // This implementation doesn't take advises
	OLE_E_NOCONNECTION               = 0x80040004, // There is no connection for this connection ID
	OLE_E_NOTRUNNING                 = 0x80040005, // Need to run the object to perform this operation
	OLE_E_NOCACHE                    = 0x80040006, // There is no cache to operate on
	OLE_E_BLANK                      = 0x80040007, // Uninitialized object
	OLE_E_CLASSDIFF                  = 0x80040008, // Linked object's source class has changed
	OLE_E_CANT_GETMONIKER            = 0x80040009, // Not able to get the moniker of the object
	OLE_E_CANT_BINDTOSOURCE          = 0x8004000A, // Not able to bind to the source
	OLE_E_STATIC                     = 0x8004000B, // Object is static; operation not allowed
	OLE_E_PROMPTSAVECANCELLED        = 0x8004000C, // User canceled out of save dialog
	OLE_E_INVALIDRECT                = 0x8004000D, // Invalid rectangle
	OLE_E_WRONGCOMPOBJ               = 0x8004000E, // compobj.dll is too old for the ole2.dll initialized
	OLE_E_INVALIDHWND                = 0x8004000F, // Invalid window handle
	OLE_E_NOT_INPLACEACTIVE          = 0x80040010, // Object is not in any of the inplace active states
	OLE_E_CANTCONVERT                = 0x80040011, // Not able to convert object
	OLE_E_NOSTORAGE                  = 0x80040012, // Not able to perform the operation because object is not given storage yet
	OLE_DV_E_FORMATETC               = 0x80040064, // Invalid FORMATETC structure
	OLE_DV_E_DVTARGETDEVICE          = 0x80040065, // Invalid DVTARGETDEVICE structure
	OLE_DV_E_STGMEDIUM               = 0x80040066, // Invalid STDGMEDIUM structure
	OLE_DV_E_STATDATA                = 0x80040067, // Invalid STATDATA structure
	OLE_DV_E_LINDEX                  = 0x80040068, // Invalid lindex
	OLE_DV_E_TYMED                   = 0x80040069, // Invalid tymed
	OLE_DV_E_CLIPFORMAT              = 0x8004006A, // Invalid clipboard format
	OLE_DV_E_DVASPECT                = 0x8004006B, // Invalid aspect(s)
	OLE_DV_E_DVTARGETDEVICE_SIZE     = 0x8004006C, // tdSize parameter of the DVTARGETDEVICE structure is invalid
	OLE_DV_E_NOIVIEWOBJECT           = 0x8004006D, // Object doesn't support IViewObject interface
}

enum
{
	OLECMDERR_E_FIRST            = (OLEERR.E_LAST+1),
	OLECMDERR_E_NOTSUPPORTED     = (E_FIRST),
	OLECMDERR_E_DISABLED         = (E_FIRST+1),
	OLECMDERR_E_NOHELP           = (E_FIRST+2),
	OLECMDERR_E_CANCELED         = (E_FIRST+3),
	OLECMDERR_E_UNKNOWNGROUP     = (E_FIRST+4),
}

enum
{
	MK_LBUTTON   = 0x0001,
	MK_RBUTTON   = 0x0002,
	MK_SHIFT     = 0x0004,
	MK_CONTROL   = 0x0008,
	MK_MBUTTON   = 0x0010,
	MK_XBUTTON1  = 0x0020,
	MK_XBUTTON2  = 0x0040,
}

extern(Windows)
{
	const GMEM_SHARE =          0x2000;
	const GMEM_MOVEABLE =       0x0002;
	const GMEM_ZEROINIT =       0x0040;
	const GHND =                (GMEM_MOVEABLE | GMEM_ZEROINIT);
	
	HWND GetActiveWindow();
	BOOL IsWindowEnabled(HWND hWnd);
	BOOL EnableWindow(HWND hWnd, BOOL bEnable);
	int MessageBoxW(HWND hWnd, in wchar* lpText, in wchar* lpCaption, uint uType);

	HGLOBAL GlobalAlloc(UINT uFlags, SIZE_T dwBytes);
	void* GlobalLock(HANDLE hMem);
	//int GlobalUnlock(HANDLE hMem);
	SIZE_T GlobalSize(HGLOBAL hMem);

	export void OutputDebugStringA(in char* lpOutputString);
}

extern(Windows)
DWORD GetModuleFileNameW(in HMODULE hModule, wchar* lpFilename, DWORD nSize);

extern(Windows)
LONG RegOpenKeyExW(in HKEY hKey, in wchar* lpSubKey, in DWORD ulOptions, in REGSAM samDesired, HKEY* phkResult);

extern(Windows)
LONG RegCreateKeyExW(in HKEY hKey, in wchar* lpSubKey, DWORD Reserved, in wchar* lpClass, in DWORD dwOptions,
                     in REGSAM samDesired, in SECURITY_ATTRIBUTES* lpSecurityAttributes, HKEY* phkResult, DWORD* lpdwDisposition);

extern(Windows)
LONG RegSetValueExW(in HKEY hKey, in wchar* lpValueName, DWORD reserved, DWORD dwType, in ubyte* data, DWORD nSize);

extern(Windows)
LONG RegQueryValueW(in HKEY hKey, in wchar* lpSubKey, wchar* lpValue, LONG *lpcbValue);

extern(Windows)
LONG RegQueryValueExW(in HKEY hkey, in wchar* lpValueName, in int Reserved, DWORD* type, void *lpData, LONG *pcbData);

extern(Windows)
LONG RegQueryInfoKeyW(in HKEY hKey, wchar* lpClass, DWORD* lpcClass, DWORD* lpReserved,
                      DWORD* lpcSubKeys, DWORD* lpcMaxSubKeyLen, DWORD* lpcMaxClassLen,
                      DWORD* lpcValues, DWORD* lpcMaxValueNameLen, DWORD* lpcMaxValueLen,
                      DWORD* lpcbSecurityDescriptor, FILETIME* lpftLastWriteTime);

extern(Windows)
LONG RegEnumKeyW(in HKEY hKey, in DWORD dwIndex, wchar* lpName, in DWORD cchName);

extern(Windows)
LONG RegEnumKeyExW(in HKEY hKey, in DWORD dwIndex, wchar* lpName, DWORD* lpcName,
                   DWORD* lpReserved, wchar* lpClass, DWORD* lpcClass, FILETIME* lpftLastWriteTime);

extern(Windows)
LONG RegDeleteKeyW(in HKEY hKey, in wchar* lpSubKey);

enum { ERROR_INSUFFICIENT_BUFFER = 122 }

HRESULT HRESULT_FROM_WIN32(ulong x)
{
	enum { FACILITY_WIN32 = 7 };
	return cast(HRESULT)(x) <= 0 ? cast(HRESULT)(x) 
	                             : cast(HRESULT) (((x) & 0x0000FFFF) | (FACILITY_WIN32 << 16) | 0x80000000);
}

enum
{
    CBS_SIMPLE            =0x0001L,
    CBS_DROPDOWN          =0x0002L,
    CBS_DROPDOWNLIST      =0x0003L,
    CBS_OWNERDRAWFIXED    =0x0010L,
    CBS_OWNERDRAWVARIABLE =0x0020L,
    CBS_AUTOHSCROLL       =0x0040L,
    CBS_OEMCONVERT        =0x0080L,
    CBS_SORT              =0x0100L,
    CBS_HASSTRINGS        =0x0200L,
    CBS_NOINTEGRALHEIGHT  =0x0400L,
    CBS_DISABLENOSCROLL   =0x0800L,
    CBS_UPPERCASE           =0x2000L,
    CBS_LOWERCASE           =0x4000L,
}

const CB_ADDSTRING = 0x0143;
const CB_FINDSTRING = 0x014C;
const CB_SELECTSTRING = 0x014D;
const CB_SETCURSEL = 0x014E;
const CB_GETCURSEL = 0x0147;

const GWL_USERDATA = -21;
const WS_EX_STATICEDGE = 0x00020000;
const WM_SETFONT = 0x0030;
const TRANSPARENT = 1;

const PSN_APPLY = -202;
const GA_ROOT = 2;

extern(Windows)
{
export BOOL UnregisterClassA(LPCSTR lpClassName, HINSTANCE hInstance);
export LONG GetWindowLongA(HWND hWnd,int nIndex);
export int SetWindowLongA(HWND hWnd, int nIndex, int dwNewLong);
export DWORD GetSysColor(int);
export BOOL DestroyWindow(HWND hWnd);
export HBRUSH CreateSolidBrush(COLORREF c);
export BOOL MoveWindow(HWND hWnd, int x, int y, int w, int h, byte bRepaint);
export BOOL EnableWindow (HWND hWnd, BOOL enable);
export HWND CreateWindowExW(DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName, DWORD dwStyle,
    int X, int Y, int nWidth, int nHeight, HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam);
export BOOL SendMessageW(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);
HWND GetAncestor(HWND hwnd, UINT gaFlags);

struct NMHDR
{
	HWND      hwndFrom;
	UINT_PTR  idFrom;
	UINT      code;         // NM_ code
}

	HRESULT CreateDataAdviseHolder(IDataAdviseHolder* ppDAHolder);

	const CF_BITMAP           = 2;
	const CF_METAFILEPICT     = 3;
	const CF_PALETTE          = 9;

	const DATA_S_SAMEFORMATETC  = 0x00040130L;
	const OLE_E_NOCONNECTION    = cast(HRESULT) 0x80040004L;
}

extern(Windows)
{
	export uint GetThreadLocale();

	export HANDLE LoadImageA(HINSTANCE hinst, LPCTSTR lpszName, UINT uType, int cxDesired, int cyDesired, UINT fuLoad);

	export HIMAGELIST ImageList_LoadImageA(HINSTANCE hi, LPCTSTR lpbmp, int cx, int cGrow, COLORREF crMask, UINT uType, UINT uFlags);
	export BOOL ImageList_Destroy(HIMAGELIST imgl);

	UINT RegisterClipboardFormatW(LPCWSTR lpszFormat);

	UINT DragQueryFileW(HANDLE hDrop, UINT iFile, LPWSTR lpszFile, UINT cch);
	HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);

}

}
