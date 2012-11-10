// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.comutil;

import visuald.windows;
import std.c.string;
import std.c.stdlib;
import std.string;
import std.utf;
import std.traits;
//import variant;

public import sdk.port.base;
public import sdk.port.stdole2;
public import stdext.com;

import sdk.win32.oleauto;
import sdk.win32.objbase;

debug debug = COM;
// debug(COM) debug = COM_DTOR; // causes crashes because logCall needs GC, but finalizer called from within GC
 debug(COM) debug = COM_ADDREL;

import core.runtime;
//debug(COM_ADDREL) debug static import rsgc.gc;
import core.memory;

import visuald.logutil;

extern (C) void _d_callfinalizer(void *p);

///////////////////////////////////////////////////////////////////////////////

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

class DComObject : ComObject
{
	debug
	{
		__gshared LONG sCountCreated;
		__gshared LONG sCountInstances;
		__gshared LONG sCountReferenced;
		debug(COM_ADDREL) __gshared int[LONG] sReferencedObjects;
		enum size_t WEAK_PTR_XOR = 0x80000000;
        alias AssociativeArray!(LONG, int) _wa1; // fully instantiate type info

	}

debug
{
	this()
	{
		void* vthis = cast(void*) this;
		debug(COM) logCall("ctor %s this = %s", this, vthis);
		debug(COM_ADDREL) synchronized(DComObject.classinfo) sReferencedObjects[cast(size_t)vthis^WEAK_PTR_XOR] = 0;
		InterlockedIncrement(&sCountInstances);
		InterlockedIncrement(&sCountCreated);
	}
	~this()
	{
		// logCall needs GC, but finalizer called from within GC
		void* vthis = cast(void*) this;
		debug(COM_DTOR) logCall("dtor %s this = %s", this, vthis);
		debug(COM_ADDREL) 
			synchronized(DComObject.classinfo) 
				if(auto p = (cast(size_t)vthis^WEAK_PTR_XOR) in sReferencedObjects)
					*p = -1,
		InterlockedDecrement(&sCountInstances);
	}

	import core.stdc.stdio;

	static void showCOMleaks()
	{
		alias OutputDebugStringA ods;

		char[1024] sbuf;
		sprintf(sbuf.ptr, "%d COM objects created\n", sCountCreated); ods(sbuf.ptr);
		sprintf(sbuf.ptr, "%d COM objects never destroyed (no final collection run yet!)\n", sCountInstances); ods(sbuf.ptr);
		sprintf(sbuf.ptr, "%d COM objects not fully dereferenced\n", sCountReferenced); ods(sbuf.ptr);
		debug(COM_ADDREL) 
			foreach(p, b; sReferencedObjects)
			{
				void* q = cast(void*)(p^WEAK_PTR_XOR);
				if(b > 0)
				{
					sprintf(sbuf.ptr, "   leaked COM object: %p %s\n", q, (cast(Object)q).classinfo.name.ptr); ods(sbuf.ptr);
				}
				else if(b == 0)
				{
					sprintf(sbuf.ptr, "   not collected:     %p %s\n", q, (cast(Object)q).classinfo.name.ptr); ods(sbuf.ptr);
				}

				version(none)
				if(b >= 0)
				{
					auto r = rsgc.gc.gc_findReference(q, (cast(Object)q).classinfo.init.length);
					auto base = rsgc.gc.gc_addrOf(r);
					string type = "unknown";
					if(base)
					{
						int attr = rsgc.gc.gc_getAttr(base);
						if(attr & 1)
							type = (cast(Object)base).classinfo.name;
					}

					sprintf(sbuf.ptr, "   referenced by %p inside %p %s\n", r, base, type.ptr); ods(sbuf.ptr);
				}
			}
	}
}

extern (System):
	override HRESULT QueryInterface(in IID* riid, void** ppv)
	{
		HRESULT hr = super.QueryInterface(riid, ppv);
		if (hr != S_OK)
			logCall("%s.QueryInterface(this=%s,riid=%s) no interface!", this, cast(void*)this, _toLog(riid));
		return hr;
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
		LONG lRef = super.AddRef();
		debug(COM_ADDREL) logCall("addref  %s this = %s ref = %d", this, cast(void*)this, lRef);
		
		if(lRef == 1)
		{
			debug InterlockedIncrement(&sCountReferenced);
			//uint sz = this.classinfo.init.length;
			debug void* vthis = cast(void*) this;
			debug(COM) logCall("addroot %s this = %s", this, vthis);
			debug(COM_ADDREL) 
				synchronized(DComObject.classinfo) sReferencedObjects[cast(size_t)vthis^WEAK_PTR_XOR] = 1;
		}
		return lRef;
	}

	override ULONG Release()
	{
		ULONG lRef = super.Release();

		debug(COM_ADDREL) logCall("release %s this = %s ref = %d", this, cast(void*)this, lRef);
	
		if (lRef == 0)
		{
			debug void* vthis = cast(void*) this;
			debug(COM) logCall("delroot %s this = %s", this, vthis);
			debug InterlockedDecrement(&sCountReferenced);
			debug(COM_ADDREL) 
				synchronized(DComObject.classinfo) sReferencedObjects[cast(size_t)vthis^WEAK_PTR_XOR] = 0;
		}
		return lRef;
	}
}

class DisposingComObject : DComObject
{
	override ULONG Release()
	{
		assert(count > 0);
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

/+
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
+/

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
		/* [size_is][in] */ in LPOLESTR *rgszNames,
		/* [range][in] */ in UINT cNames,
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
		/* [size_is][in] */ in LPOLESTR *rgszNames,
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
		//return returnError(E_NOTIMPL);
	}

	/* [local] */ void ReleaseFuncDesc( 
		/* [in] */ in FUNCDESC *pFuncDesc)
	{
		mixin(LogCallMix);
		//return returnError(E_NOTIMPL);
	}

	/* [local] */ void ReleaseVarDesc( 
		/* [in] */ in VARDESC *pVarDesc)
	{
		mixin(LogCallMix);
		//return returnError(E_NOTIMPL);
	}
}

