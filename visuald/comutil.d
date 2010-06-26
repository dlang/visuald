// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module comutil;

import windows;
import std.c.string;
import std.c.stdlib;
import std.string;
import std.utf;
import std.traits;
//import variant;

public import sdk.port.base;
public import sdk.port.stdole2;

import sdk.win32.oleauto;
import sdk.win32.objbase;

version = GC_COM;
debug debug = COM;
//debug(COM) debug = COM_ADDREL;

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

///////////////////////////////////////////////////////////////////////////////

struct ComPtr(Interface)
{
	Interface ptr;

	this(Interface i = null, bool doref = true)
	{
		ptr = i;
		if(ptr && doref)
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

	Interface detach()
	{
		Interface p = ptr;
		ptr = null;
		return p;
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
	
	Interface opCast(T:Interface)() { return ptr; }
	Interface* opCast(T:Interface*)() { return &ptr; }
	bool opCast(T:bool)() { return ptr !is null; }
	
	alias ptr this;
}

///////////////////////////////////////////////////////////////////////
bool queryInterface2(I)(I obj, in IID iid, in IID* riid, void** pvObject)
{
	if(*riid == iid)
	{
		*pvObject = cast(void*)obj;
		obj.AddRef();
		return true;
	}
	return false;
}

bool queryInterface(I)(I obj, in IID* riid, void** pvObject)
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
	auto container = ComPtr!(IConnectionPointContainer)(pSource);
	if(container)
	{
		ComPtr!(IConnectionPoint) point;
		if(container.FindConnectionPoint(&Interface.iid, &point.ptr) == S_OK)
		{
			uint cookie;
			if(point.Advise(pSink, &cookie) == S_OK)
				return cookie;
		}
	}
	return 0;
}


uint Unadvise(Interface)(IUnknown pSource, uint cookie)
{
	auto container = ComPtr!(IConnectionPointContainer)(pSource);
	if(container)
	{
		ComPtr!(IConnectionPoint) point;
		if(container.FindConnectionPoint(&Interface.iid, &point.ptr) == S_OK)
		{
			if(point.Unadvise(cookie) == S_OK)
				return cookie;
		}
	}
	return 0;
}

///////////////////////////////////////////////////////////////////////////////

class DComObject : IUnknown
{
	__gshared static LONG sCountInstances;
	__gshared static LONG sCountReferenced;
	
version(GC_COM)
{
} else
{
	new(uint size)
	{
version(GC_COM)
{
		void* p = new char[size];
}
else version(D_Version2)
{
		void* p = std.c.stdlib.malloc(size);
		GC.addRange(p, size);
}
else
{
		void* p = std.c.stdlib.malloc(size);
		if(!p)
			_d_OutOfMemory();

		addRange(p, cast(char*) p + size);
}
		return p;
	}
}

debug
{
	this()
	{
		debug(COM) logCall("ctor %s this = %s", this, cast(void*)this);
		InterlockedIncrement(&sCountInstances);
	}
	~this()
	{
		debug(COM) logCall("dtor %s this = %s", this, cast(void*)this);
		InterlockedDecrement(&sCountInstances);
	}
	shared static ~this()
	{
		logCall("%d COM objects not fully dereferenced", sCountReferenced);
		logCall("%d COM objects never destroyed", sCountInstances);
	}
}

extern (System):
	override HRESULT QueryInterface(in IID* riid, void** ppv)
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

version(none) // copy for debugging
{
	override ULONG AddRef()
	{
		return super.AddRef();
	}
	override ULONG Release()
	{
		return super.Release();
	}
}

	override ULONG AddRef()
	{
		LONG lRef = InterlockedIncrement(&count);
version(GC_COM)
{
		debug(COM_ADDREL) logCall("addref  %s this = %s", this, cast(void*)this);
		
		if(lRef == 1)
		{
			debug InterlockedIncrement(&sCountReferenced);
			//uint sz = this.classinfo.init.length;
			GC.addRoot(cast(void*) this);
			debug(COM) logCall("addroot %s this = %s", this, cast(void*)this);
		}
}
		return lRef;
	}

	override ULONG Release()
	{
		LONG lRef = InterlockedDecrement(&count);

		debug(COM_ADDREL) logCall("release %s this = %s", this, cast(void*)this);
	
		if (lRef == 0)
		{
version(GC_COM)
{
			debug(COM) logCall("delroot %s this = %s", this, cast(void*)this);
			GC.removeRoot(cast(void*) this);
			debug InterlockedDecrement(&sCountReferenced);
}
else
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
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	override int GetContainingTypeLib( 
		/* [out] */ ITypeLib *ppTLib,
		/* [out] */ UINT *pIndex)
	{
		mixin(LogCallMix2);
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

static const size_t clsidLen  = 127;
static const size_t clsidSize = clsidLen + 1;

wstring GUID2wstring(in GUID clsid)
{
	//get clsid's as string
	wchar oleCLSID_arr[clsidLen+1];
	if (StringFromGUID2(clsid, oleCLSID_arr.ptr, clsidLen) == 0)
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

wchar* _toUTF16zw(wstring s)
{
	// const for D2
	wstring sz = s ~ "\0"w;
	return cast(wchar*)sz.ptr;
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
struct ScopedBSTR
{
	BSTR bstr;
	alias bstr this;
	
	this(string s)
	{
		bstr = allocBSTR(s);
	}
	this(wstring s)
	{
		bstr = allocwBSTR(s);
	}
	
	~this()
	{
		if(bstr)
		{
			freeBSTR(bstr);
			bstr = null;
		}
	}
	
	wstring wdetach()
	{
		return wdetachBSTR(bstr);
	}
	string detach()
	{
		return detachBSTR(bstr);
	}
}

///////////////////////////////////////////////////////////////////////
int array_find(T)(ref T[] arr, T x)
{
	for(int i = 0; i < arr.length; i++)
		if(arr[i] == x)
			return i;
	return -1;
}

