// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.dllmain;

import stdwin = std.c.windows.windows;
import visuald.windows;
import visuald.comutil;
import visuald.logutil;
import visuald.register;
import visuald.dpackage;

import std.parallelism;

import core.runtime;
import core.memory;
version(dmd_2_052)
{
	import core.dll_helper;
	import threadaux = core.thread_helper;
}
else
{
	import core.sys.windows.dll;
	import threadaux = core.sys.windows.threadaux;
}

import std.conv;

__gshared HINSTANCE g_hInst;

///////////////////////////////////////////////////////////////////////
version(MAIN)
{
	int main()
	{
		VSDllRegisterServer(("Software\\Microsoft\\VisualStudio\\9.0D"w).ptr);
		//VSDllUnregisterServerUser(("Software\\Microsoft\\VisualStudio\\9.0D"w).ptr);
		return 0;
	}
}
else // !version(MAIN)
{
} // !version(D_Version2)

extern extern(C) __gshared ModuleInfo D4core3sys7windows10stacktrace12__ModuleInfoZ;

void disableStacktrace()
{
	ModuleInfo* info = &D4core3sys7windows10stacktrace12__ModuleInfoZ;
	if (info.isNew)
	{
		enum
		{
			MItlsctor    = 8,
			MItlsdtor    = 0x10,
			MIctor       = 0x20,
			MIdtor       = 0x40,
			MIxgetMembers = 0x80,
		}
		if (info.n.flags & MIctor)
		{
			size_t off = info.New.sizeof;
			if (info.n.flags & MItlsctor)
				off += info.o.tlsctor.sizeof;
			if (info.n.flags & MItlsdtor)
				off += info.o.tlsdtor.sizeof;
			if (info.n.flags & MIxgetMembers)
				off += info.o.xgetMembers.sizeof;
			*cast(typeof(info.o.ctor)*)(cast(void*)info + off) = null;
		}
	}
	else
		info.o.ctor = null;
}

void clearStack()
{
	// fill stack with zeroes, so the chance of having false pointers is reduced
	int[1000] arr;
}

extern (Windows)
BOOL DllMain(stdwin.HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
{
	switch (ulReason)
	{
		case DLL_PROCESS_ATTACH:
			disableStacktrace();
			if(!dll_process_attach(hInstance, true))
				return false;
			g_hInst = cast(HINSTANCE) hInstance;
//	GC.disable();
			global_init();
			//MessageBoxA(cast(HANDLE)0, "Hi", "there", 0);

			logCall("DllMain(DLL_PROCESS_ATTACH, tid=%x)", GetCurrentThreadId());
			break;

		case DLL_PROCESS_DETACH:
			logCall("DllMain(DLL_PROCESS_DETACH, tid=%x)", GetCurrentThreadId());
			global_exit();
			debug clearStack();
			debug GC.collect();
			debug DComObject.showCOMleaks();
			dll_process_detach( hInstance, true );
			
			debug if(DComObject.sCountReferenced != 0 || DComObject.sCountInstances != 0)
				asm { int 3; } // use continue, not terminate in the debugger
			break;

debug // allow std 2.052 in debug builds
	enum isPatchedLib = __traits(compiles, { bool b = dll_thread_attach( true, true ); });
else // ensure patched runtime in release
	enum isPatchedLib = true;
		
	static if(isPatchedLib)
	{
		case DLL_THREAD_ATTACH:
			if(!dll_thread_attach( true, true ))
				return false;
			logCall("DllMain(DLL_THREAD_ATTACH, id=%x)", GetCurrentThreadId());
			break;

		case DLL_THREAD_DETACH:
			if(threadaux.GetTlsDataAddress(GetCurrentThreadId())) //, _tls_index))
				logCall("DllMain(DLL_THREAD_DETACH, id=%x)", GetCurrentThreadId());
			dll_thread_detach( true, true );
			break;
	}
	else
	{
		pragma(msg, text(__FILE__, "(", __LINE__, "): DllMain uses compatibility mode, this can cause crashes on a 64-bit OS"));
		case DLL_THREAD_ATTACH:
			dll_thread_attach( true, true );
			break;

		case DLL_THREAD_DETACH:
			dll_thread_detach( true, true );
			break;
	}
			
		default:
			assert(_false);
			return false;
	
	}
	return true;
}

extern (Windows)
void RunDLLRegister(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllRegisterServer(ws.ptr);
}

extern (Windows)
void RunDLLUnregister(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllUnregisterServer(ws.ptr);
}

extern (Windows)
void RunDLLRegisterUser(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllRegisterServerUser(ws.ptr);
}

extern (Windows)
void RunDLLUnregisterUser(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllUnregisterServerUser(ws.ptr);
}

///////////////////////////////////////////////////////////////////////
// only the first export has a '_' prefix
//extern(C) export void dummy () { }

