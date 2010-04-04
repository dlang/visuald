module comutil;

import std.c.windows.windows;
import std.c.windows.com;
import std.c.string;
import std.c.stdlib;
import std.string;
import std.utf;
import std.traits;
//import variant;

public import sdk.port.base;
public import sdk.port.stdole2;

version(D_Version2)
{
	import core.runtime;
	import core.memory;

	const string d2_shared = "__gshared";
}
else
{
	import std.gc;
	import std.outofmemory;

	const string d2_shared = "";
}

import logutil;

extern (C) void _d_callfinalizer(void *p);

///////////////////////////////////////////////////////////////////////////////

enum { DISP_E_MEMBERNOTFOUND = -2147352573 }

enum OLEERR
{
	E_FIRST = 0x80040000,
	E_LAST  = 0x800400FF,

	E_OLEVERB                    = 0x80040000, // Invalid OLEVERB structure
	E_ADVF                       = 0x80040001, // Invalid advise flags
	E_ENUM_NOMORE                = 0x80040002, // Can't enumerate any more, because the associated data is missing
	E_ADVISENOTSUPPORTED         = 0x80040003, // This implementation doesn't take advises
	E_NOCONNECTION               = 0x80040004, // There is no connection for this connection ID
	E_NOTRUNNING                 = 0x80040005, // Need to run the object to perform this operation
	E_NOCACHE                    = 0x80040006, // There is no cache to operate on
	E_BLANK                      = 0x80040007, // Uninitialized object
	E_CLASSDIFF                  = 0x80040008, // Linked object's source class has changed
	E_CANT_GETMONIKER            = 0x80040009, // Not able to get the moniker of the object
	E_CANT_BINDTOSOURCE          = 0x8004000A, // Not able to bind to the source
	E_STATIC                     = 0x8004000B, // Object is static; operation not allowed
	E_PROMPTSAVECANCELLED        = 0x8004000C, // User canceled out of save dialog
	E_INVALIDRECT                = 0x8004000D, // Invalid rectangle
	E_WRONGCOMPOBJ               = 0x8004000E, // compobj.dll is too old for the ole2.dll initialized
	E_INVALIDHWND                = 0x8004000F, // Invalid window handle
	E_NOT_INPLACEACTIVE          = 0x80040010, // Object is not in any of the inplace active states
	E_CANTCONVERT                = 0x80040011, // Not able to convert object
	E_NOSTORAGE                  = 0x80040012, // Not able to perform the operation because object is not given storage yet
	DV_E_FORMATETC               = 0x80040064, // Invalid FORMATETC structure
	DV_E_DVTARGETDEVICE          = 0x80040065, // Invalid DVTARGETDEVICE structure
	DV_E_STGMEDIUM               = 0x80040066, // Invalid STDGMEDIUM structure
	DV_E_STATDATA                = 0x80040067, // Invalid STATDATA structure
	DV_E_LINDEX                  = 0x80040068, // Invalid lindex
	DV_E_TYMED                   = 0x80040069, // Invalid tymed
	DV_E_CLIPFORMAT              = 0x8004006A, // Invalid clipboard format
	DV_E_DVASPECT                = 0x8004006B, // Invalid aspect(s)
	DV_E_DVTARGETDEVICE_SIZE     = 0x8004006C, // tdSize parameter of the DVTARGETDEVICE structure is invalid
	DV_E_NOIVIEWOBJECT           = 0x8004006D, // Object doesn't support IViewObject interface
}

enum OLECMDERR
{
	E_FIRST            = (OLEERR.E_LAST+1),
	E_NOTSUPPORTED     = (E_FIRST),
	E_DISABLED         = (E_FIRST+1),
	E_NOHELP           = (E_FIRST+2),
	E_CANCELED         = (E_FIRST+3),
	E_UNKNOWNGROUP     = (E_FIRST+4),
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

///////////////////////////////////////////////////////////////////////////////

class ComPtr(Interface)
{
	Interface ptr;

	this()
	{
	}

	this(Interface i)
	{
		ptr = i;
		if(ptr)
			ptr.AddRef();
	}

	this(IUnknown i)
	{
		ptr = qi_cast!(Interface)(i);
	}

	~this()
	{
		if(ptr)
			ptr.Release();
	}

	void opAssign(Interface i) 
	{
		if(ptr)
			ptr.Release();
		ptr = i;
		if(ptr)
			ptr.AddRef();
	}

	void opAssign(IUnknown i) 
	{ 
		if(ptr)
			ptr.Release();
		ptr = qi_cast!(Interface)(i);
	}
}

///////////////////////////////////////////////////////////////////////
bool queryInterface2(I)(I obj, in IID iid, IID* riid, void** pvObject)
{
	if(*riid == iid)
	{
		*pvObject = cast(void*)obj;
		obj.AddRef();
		return true;
	}
	return false;
}

bool queryInterface(I)(I obj, IID* riid, void** pvObject)
{
	return queryInterface2!(I)(obj, I.iid, riid, pvObject);
}

I qi_cast(I)(IUnknown obj)
{
	I iobj;
	if(obj && obj.QueryInterface(&I.iid, cast(void**)&iobj) == S_OK)
		return iobj;
	return null;
}

///////////////////////////////////////////////////////////////////////////////

uint Advise(Interface)(IUnknown pSource, IUnknown pSink)
{
	scope auto container = new ComPtr!(IConnectionPointContainer)(pSource);
	if(container.ptr)
	{
		scope auto point = new ComPtr!(IConnectionPoint);
		if(container.ptr.FindConnectionPoint(&Interface.iid, &point.ptr) == S_OK)
		{
			uint cookie;
			if(point.ptr.Advise(pSink, &cookie) == S_OK)
				return cookie;
		}
	}
	return 0;
}


uint Unadvise(Interface)(IUnknown pSource, uint cookie)
{
	scope auto container = new ComPtr!(IConnectionPointContainer)(pSource);
	if(container.ptr)
	{
		scope auto point = new ComPtr!(IConnectionPoint);
		if(container.ptr.FindConnectionPoint(&Interface.iid, &point.ptr) == S_OK)
		{
			if(point.ptr.Unadvise(cookie) == S_OK)
				return cookie;
		}
	}
	return 0;
}

///////////////////////////////////////////////////////////////////////////////

class DComObject : IUnknown
{
	new(uint size)
	{
		void* p = std.c.stdlib.malloc(size);
version(D_Version2)
{
		GC.addRange(p, size);
}
else
{
		if(!p)
			_d_OutOfMemory();

		addRange(p, cast(char*) p + size);
}
		return p;
	}

extern (System):
	override HRESULT QueryInterface(IID* riid, void** ppv)
	{
		if (*riid == IID_IUnknown)
		{
			*ppv = cast(void*)cast(IUnknown)this;
			AddRef();
			return S_OK;
		}
		else
		{
			logCall("%s.QueryInterface(this=%s,riid=%s) no interface!", this, cast(void*)this, _toLog(riid));

			*ppv = null;
			return E_NOINTERFACE;
		}
	}

	override ULONG AddRef()
	{
	    return InterlockedIncrement(&count);
	}

	override ULONG Release()
	{
	    LONG lRef = InterlockedDecrement(&count);
	    if (lRef == 0)
	    {
		// free object
		// com objects are allocated with malloc, so they are not under GC control, we have to explicitely release it ourselves

		// if there is an invariant defined for this object, it will definitely fail or crash!

		_d_callfinalizer(cast(void *)this);
version(D_Version2)
{
		GC.removeRange(cast(void*) this);
}
else
{
		removeRange(cast(void*) this);
}
//		std.c.stdlib.free(cast(void*) this); 
		return 0;
	    }
	    return cast(ULONG)lRef;
	}

	LONG count = 0;		// object reference count
}

class DisposingComObject : DComObject
{
	override ULONG Release()
	{
		if(count == 1)
		{
			// avoid recursive delete if the object is temporarily ref-counted
			// while executing Dispose()
			count = 0x12345678;
			Dispose();
			assert(count == 0x12345678);
			count = 1;
		}
		return super.Release();
	}

	abstract void Dispose();
}

struct PARAMDATA 
{
	OLECHAR* szName;
	VARTYPE vtReturn;
}

struct METHODDATA 
{
	OLECHAR* zName;
	PARAMDATA* ppData;
	DISPID dispid;
	uint iMeth;
	CALLCONV cc;
	uint cArgs;
	ushort wFlags;
	VARTYPE vtReturn;
}

struct INTERFACEDATA
{
	METHODDATA* pmethdata;   // Pointer to an array of METHODDATAs.
	uint cMembers;           // Count of 
}

class DisposingDispatchObject : DisposingComObject, IDispatch
{
	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IDispatch) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IDispatch
	override int GetTypeInfoCount( 
		/* [out] */ UINT *pctinfo)
	{
//		mixin(LogCallMix);
		*pctinfo = 1;
		return S_OK;
	}

	override int GetTypeInfo( 
		/* [in] */ in UINT iTInfo,
		/* [in] */ in LCID lcid,
		/* [out] */ ITypeInfo *ppTInfo)
	{
		mixin(LogCallMix);

		if(iTInfo != 0)
			return returnError(E_INVALIDARG);
		*ppTInfo = addref(getTypeHolder());
		return S_OK;
	}

	override int GetIDsOfNames( 
		/* [in] */ in IID* riid,
		/* [size_is][in] */ LPOLESTR *rgszNames,
		/* [range][in] */ UINT cNames,
		/* [in] */ in LCID lcid,
		/* [size_is][out] */ DISPID *rgDispId)
	{
		mixin(LogCallMix);
		return getTypeHolder().GetIDsOfNames(rgszNames, cNames, rgDispId);
	}

	override int Invoke( 
		/* [in] */ in DISPID dispIdMember,
		/* [in] */ in IID* riid,
		/* [in] */ in LCID lcid,
		/* [in] */ in WORD wFlags,
		/* [out][in] */ DISPPARAMS *pDispParams,
		/* [out] */ VARIANT *pVarResult,
		/* [out] */ EXCEPINFO *pExcepInfo,
		/* [out] */ UINT *puArgErr)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	abstract ComTypeInfoHolder getTypeHolder();
}

struct DispatchData
{
	int id;
	string name;
	FUNCDESC* desc;
}

template callWithVariantArgs(DG)
{
	int call(DG dg, VARIANT[] args)
	{
		alias ParameterTypeTuple!(DG) argTypes;
		
	}
}


class ComTypeInfoHolder : DComObject, ITypeInfo
{
	string[int] m_pMap;

	this()
	{
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(ITypeInfo) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override int GetTypeAttr( 
		/* [out] */ TYPEATTR **ppTypeAttr)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetTypeComp( 
		/* [out] */ ITypeComp* ppTComp)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetFuncDesc( 
		/* [in] */ in UINT index,
		/* [out] */ FUNCDESC **ppFuncDesc)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetVarDesc( 
		/* [in] */ in UINT index,
		/* [out] */ VARDESC **ppVarDesc)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetNames( 
		/* [in] */ in MEMBERID memid,
		/* [length_is][size_is][out] */ BSTR *rgBstrNames,
		/* [in] */ in UINT cMaxNames,
		/* [out] */ UINT *pcNames)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetRefTypeOfImplType( 
		/* [in] */ in UINT index,
		/* [out] */ HREFTYPE *pRefType)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetImplTypeFlags( 
		/* [in] */ in UINT index,
		/* [out] */ INT *pImplTypeFlags)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetIDsOfNames( 
		/* [size_is][in] */ LPOLESTR *rgszNames,
		/* [in] */ in UINT cNames,
		/* [size_is][out] */ MEMBERID *pMemId)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Invoke( 
		/* [in] */ in PVOID pvInstance,
		/* [in] */ in MEMBERID memid,
		/* [in] */ in WORD wFlags,
		/* [out][in] */ DISPPARAMS *pDispParams,
		/* [out] */ VARIANT *pVarResult,
		/* [out] */ EXCEPINFO *pExcepInfo,
		/* [out] */ UINT *puArgErr)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	override int GetDocumentation( 
		/* [in] */ in MEMBERID memid,
		/* [out] */ BSTR *pBstrName,
		/* [out] */ BSTR *pBstrDocString,
		/* [out] */ DWORD *pdwHelpContext,
		/* [out] */ BSTR *pBstrHelpFile)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetDllEntry( 
		/* [in] */ in MEMBERID memid,
		/* [in] */ in INVOKEKIND invKind,
		/* [out] */ BSTR *pBstrDllName,
		/* [out] */ BSTR *pBstrName,
		/* [out] */ WORD *pwOrdinal)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetRefTypeInfo( 
		/* [in] */ in HREFTYPE hRefType,
		/* [out] */ ITypeInfo* ppTInfo)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AddressOfMember( 
		/* [in] */ in MEMBERID memid,
		/* [in] */ in INVOKEKIND invKind,
		/* [out] */ PVOID *ppv)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int CreateInstance( 
		/* [in] */ IUnknown pUnkOuter,
		/* [in] */ in IID* riid,
		/* [iid_is][out] */ PVOID *ppvObj)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetMops( 
		/* [in] */ in MEMBERID memid,
		/* [out] */ BSTR *pBstrMops)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetContainingTypeLib( 
		/* [out] */ ITypeLib *ppTLib,
		/* [out] */ UINT *pIndex)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/* [local] */ void ReleaseTypeAttr( 
		/* [in] */ in TYPEATTR *pTypeAttr)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/* [local] */ void ReleaseFuncDesc( 
		/* [in] */ in FUNCDESC *pFuncDesc)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/* [local] */ void ReleaseVarDesc( 
		/* [in] */ in VARDESC *pVarDesc)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
}

///////////////////////////////////////////////////////////////////////////////

T addref(T)(T p)
{
	if(p)
		p.AddRef();
	return p;
}

T release(T)(T p)
{
	if(p)
		p.Release();
	return null;
 }

///////////////////////////////////////////////////////////////////////////////

// alias wchar* BSTR;

extern(Windows) export BSTR SysAllocString(in wchar* str);
extern(Windows) export BSTR SysAllocStringLen(in wchar* str, int len);
extern(Windows) export BSTR SysFreeString(BSTR str);
extern(Windows) export void* CoTaskMemAlloc(int sz);

extern(Windows) export int StringFromGUID2(in GUID *rguid, LPOLESTR lpsz, int cbMax);

static const size_t clsidLen  = 127;
static const size_t clsidSize = clsidLen + 1;

wstring GUID2wstring(in GUID clsid)
{
	//get clsid's as string
	wchar oleCLSID_arr[clsidLen+1];
	if (StringFromGUID2(&clsid, oleCLSID_arr.ptr, clsidLen) == 0)
		return "";
	wstring oleCLSID = to_wstring(oleCLSID_arr.ptr);
	return oleCLSID;
}

string GUID2string(in GUID clsid)
{
	return toUTF8(GUID2wstring(clsid));
}

BSTR allocwBSTR(wstring s)
{
	return SysAllocStringLen(s.ptr, s.length);
}

BSTR allocBSTR(string s)
{
	wstring ws = toUTF16(s);
	return SysAllocStringLen(ws.ptr, ws.length);
}

wstring wdetachBSTR(ref BSTR bstr)
{
	if(!bstr)
		return ""w;
	wstring ws = to_wstring(bstr);
	SysFreeString(bstr);
	bstr = null;
	return ws;
}

string detachBSTR(ref BSTR bstr)
{
	if(!bstr)
		return "";
	wstring ws = to_wstring(bstr);
	SysFreeString(bstr);
	bstr = null;
	string s = toUTF8(ws);
	return s;
}

void freeBSTR(BSTR bstr)
{
	if(bstr)
		SysFreeString(bstr);
}

wchar* wstring2OLESTR(wstring s)
{
	int sz = (s.length + 1) * 2;
	wchar* p = cast(wchar*) CoTaskMemAlloc(sz);
	p[0 .. s.length] = s[0 .. $];
	p[s.length] = 0;
	return p;
}

wchar* string2OLESTR(string s)
{
	wstring ws = toUTF16(s);
	int sz = (ws.length + 1) * 2;
	wchar* p = cast(wchar*) CoTaskMemAlloc(sz);
	p[0 .. s.length] = ws[0 .. $];
	p[s.length] = 0;
	return p;
}

wchar* _toUTF16z(string s)
{
	// const for D2
	return cast(wchar*)toUTF16z(s);
}

string to_string(in wchar* pText, int iLength)
{
	if(!pText)
		return "";
	string text = toUTF8(pText[0 .. iLength]);
	return text;
}

string to_string(in wchar* pText)
{
	if(!pText)
		return "";
	int len = wcslen(pText);
	return to_string(pText, len);
}

wstring to_wstring(in wchar* pText, int iLength)
{
	if(!pText)
		return ""w;
version(D_Version2)
	wstring text = pText[0 .. iLength].idup;
else
	wstring text = pText[0 .. iLength].dup;

	return text;
}

wstring to_cwstring(in wchar* pText, int iLength)
{
	if(!pText)
		return ""w;
version(D_Version2)
	wstring text = pText[0 .. iLength].idup;
else
	wstring text = pText[0 .. iLength];

	return text;
}

wstring to_wstring(in wchar* pText)
{
	if(!pText)
		return ""w;
	int len = wcslen(pText);
	return to_wstring(pText, len);
}

wstring to_cwstring(in wchar* pText)
{
	if(!pText)
		return ""w;
	int len = wcslen(pText);
	return to_cwstring(pText, len);
}

wstring to_wstring(in char* pText)
{
	if(!pText)
		return ""w;
	int len = strlen(pText);
	return toUTF16(pText[0 .. len]);
}

///////////////////////////////////////////////////////////////////////
int array_find(T)(ref T[] arr, T x)
{
	for(int i = 0; i < arr.length; i++)
		if(arr[i] == x)
			return i;
	return -1;
}

