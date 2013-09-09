// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.vdserverfactory;

import vdc.ivdserver;
import vdc.vdserver;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import stdext.com;

///////////////////////////////////////////////////////////////

// -9A0n- for debug
// server object: 002a2de9-8bb6-484d-9901-7e4ad4084715
// class factory: 002a2de9-8bb6-484d-9902-7e4ad4084715
// type library : 002a2de9-8bb6-484d-9903-7e4ad4084715

///////////////////////////////////////////////////////////////

alias object.AssociativeArray!(string, int) _wa1; // fully instantiate type info for string[Tid]

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

class VDServerClassFactory : ComObject, IClassFactory
{
	debug static GUID iid = uuid("002a2de9-8bb6-484d-9A02-7e4ad4084715");
	else  static GUID iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");

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
			VDServer srv = newCom!VDServer;
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

int vdserver_main(string[] argv)
{
	HRESULT hr;

	// Create the MyCar class object.
	VDServerClassFactory cf = newCom!VDServerClassFactory;

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

import std.compiler;
import std.conv;

static if(version_minor < 64)
{
	// dmd 2.064 implicitely adds C main with D main
	int main(string[] argv)
	{
		return vdserver_main(argv);
	}
}
else
{
	extern(C) int _d_run_main(int argc, char **argv, void* mainFunc);

	extern (Windows)
	int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
	{
		char*[2] argv;
		argv[0] = lpCmdLine;
		argv[1] = null;
		return _d_run_main(1, argv.ptr, &vdserver_main);
	}
}
