// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.vdserver;

import std.stdio;
import stdext.com;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import vdc.semantic;

///////////////////////////////////////////////////////////////

// server object: 002a2de9-8bb6-484d-9901-7e4ad4084715
// class factory: 002a2de9-8bb6-484d-9902-7e4ad4084715
// type library : 002a2de9-8bb6-484d-9903-7e4ad4084715

///////////////////////////////////////////////////////////////

static this()
{
	CoInitialize(null);
}

static ~this()
{
	CoUninitialize();
}

///////////////////////////////////////////////////////////////

interface IVDServer : IUnknown
{
	static GUID iid = uuid("002a2de9-8bb6-484d-9901-7e4ad4084715");

public:
	HRESULT ExecCommand(in BSTR cmd, BSTR* answer);
	HRESULT ExecCommandAsync(in BSTR cmd, ULONG* cmdID);
}

class VDServer : ComObject, IVDServer
{
	this()
	{
		mSemanticProject = new vdc.semantic.Project;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
//		MessageBoxW(null, "Object1.QueryInterface"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
		if(queryInterface!(IVDServer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT ExecCommand(in BSTR cmd, BSTR* answer)
	{
		*answer = SysAllocString("Answer"w.ptr);
		return S_OK;
	}

	HRESULT ExecCommandAsync(in BSTR cmd, ULONG* cmdID)
	{
		return E_NOTIMPL;
	}

	HRESULT ConfigureSemanticProject(in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags)
	{
		return E_NOTIMPL;
	}
	HRESULT ClearSemanticProject()
	{
		return E_NOTIMPL;
	}
	HRESULT UpdateModule(in BSTR filename, in BSTR srcText)
	{
		return E_NOTIMPL;
	}
	HRESULT GetType(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BSTR* answer)
	{
		return E_NOTIMPL;
	}
	HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, BSTR* stringList)
	{
		return E_NOTIMPL;
	}
	HRESULT isBinaryOperator(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp)
	{
		return S_FALSE;
	}
private:
	vdc.semantic.Project mSemanticProject;
}

///////////////////////////////////////////////////////////////

class VDServerClassFactory : ComObject, IClassFactory
{
	static GUID iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IClassFactory) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		if(*riid == IVDServer.iid)
		{
			//MessageBoxW(null, "CreateInstance IVDServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			assert(!UnkOuter);
			VDServer srv = new VDServer;
			return srv.QueryInterface(riid, pvObject);
		}
		return E_NOINTERFACE;
	}
	override HRESULT LockServer(in BOOL fLock)
	{
		if(fLock)
		{
			//MessageBoxW(null, "LockServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			lockCount++;
		}
		else
		{
			//MessageBoxW(null, "UnlockServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			lockCount--;
		}
		if(lockCount == 0)
			PostQuitMessage(0);
		return S_OK;
	}

	int lockCount;
}

///////////////////////////////////////////////////////////////

int main(string[] argv)
{
	HRESULT hr;

	// Create the MyCar class object.
	VDServerClassFactory cf = new VDServerClassFactory;

	// Register the Factory.
	DWORD regID = 0;
	hr = CoRegisterClassObject(VDServerClassFactory.iid, cf, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &regID);
	if(FAILED(hr))
	{
		ShowErrorMessage("CoRegisterClassObject()", hr);
		return 1;
	}

	//MessageBoxW(null, "comserverd registered"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);

	// Now just run until a quit message is sent,
	// in responce to the final release.
	MSG ms;
	while(GetMessage(&ms, null, 0, 0))
	{
		TranslateMessage(&ms);
		DispatchMessage(&ms);
	}

	// All done, so remove class object.
	CoRevokeClassObject(regID);	
	return 0;
}

int MAKELANGID(int p, int s) { return ((cast(WORD)s) << 10) | cast(WORD)p; }

void ShowErrorMessage(LPCTSTR header, HRESULT hr)
{
	wchar* pMsg;

	FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,null,hr,
		           MAKELANGID(LANG_NEUTRAL,SUBLANG_DEFAULT),cast(LPTSTR)&pMsg,0,null);

	MessageBoxW(null, pMsg, "[LOCAL] error", MB_OK|MB_SETFOREGROUND);

	LocalFree(pMsg);
}

