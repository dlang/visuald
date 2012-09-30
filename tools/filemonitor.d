// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module filemonitor;

//import std.c.windows.windows;
import core.sys.windows.windows;
//import core.sys.windows.dll;
import core.stdc.stdio;
import core.stdc.string;

__gshared HINSTANCE g_hInst;
extern(C) __gshared int _acrtused_dll;

__gshared char[260] dumpFile = [ 0 ];
__gshared HANDLE hndDumpFile = INVALID_HANDLE_VALUE;
__gshared HANDLE hndMutex = INVALID_HANDLE_VALUE;

extern(Windows) HANDLE CreateMutexA(LPSECURITY_ATTRIBUTES lpMutexAttributes, BOOL bInitialOwner, LPCSTR lpName) nothrow;
extern(Windows) BOOL ReleaseMutex(HANDLE hMutex) nothrow;

version(TEST)
{
	void main(string[]argv)
	{
		RedirectCreateFileA();
		auto hnd = CreateFileA("test.abc", GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, 0, null);
	}
} else
extern (Windows)
BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
{
	g_hInst = hInstance;
	if(ulReason == DLL_PROCESS_ATTACH)
		RedirectCreateFileA();
	return true;
}

alias typeof(&CreateFileA) fnCreateFileA;
__gshared fnCreateFileA origCreateFileA;

void RedirectCreateFileA()
{
	//MessageBoxA(null, "A", "B", MB_OK);
	ubyte* jmpAdr = cast(ubyte*)&CreateFileA;
	auto impTableEntry = cast(fnCreateFileA*) (*cast(void**)(jmpAdr + 2));
	origCreateFileA = *impTableEntry;

	DWORD oldProtect, newProtect;
	VirtualProtect(impTableEntry, (*impTableEntry).sizeof, PAGE_READWRITE, &oldProtect);
	*impTableEntry = &MyCreateFileA;
	VirtualProtect(impTableEntry, (*impTableEntry).sizeof, oldProtect, &newProtect);
}

extern(Windows) HANDLE
MyCreateFileA(
			/*__in*/     in char* lpFileName,
			/*__in*/     DWORD dwDesiredAccess,
			/*__in*/     DWORD dwShareMode,
			/*__in_opt*/ LPSECURITY_ATTRIBUTES lpSecurityAttributes,
			/*__in*/     DWORD dwCreationDisposition,
			/*__in*/     DWORD dwFlagsAndAttributes,
			/*__in_opt*/ HANDLE hTemplateFile
			) nothrow
{
	//MessageBoxA(null, lpFileName, dumpFile.ptr/*"CreateFile"*/, MB_OK);
	//	printf("CreateFileA(%s)\n", lpFileName);
	auto hnd = origCreateFileA(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, 
							   dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
	if(hnd != INVALID_HANDLE_VALUE && (dwDesiredAccess & GENERIC_READ))
	{
		if(dumpFile[0] && hndDumpFile == INVALID_HANDLE_VALUE)
		{
			hndDumpFile = origCreateFileA(dumpFile.ptr, GENERIC_WRITE, 0, null, CREATE_ALWAYS|TRUNCATE_EXISTING, 0, null);
			hndMutex = CreateMutexA(null, false, null);
		}
		if(hndDumpFile != INVALID_HANDLE_VALUE)
		{
			// combine writes to "atomic" write to avoid wrong placing of newlines
			if(hndMutex != INVALID_HANDLE_VALUE)
				WaitForSingleObject(hndMutex, INFINITE);

			size_t length = mystrlen(lpFileName);
			WriteFile(hndDumpFile, lpFileName, length, &length, null);
			WriteFile(hndDumpFile, "\n".ptr, 1, &length, null);

			if(hndMutex != INVALID_HANDLE_VALUE)
				ReleaseMutex(hndMutex);
		}
	}
	return hnd;
}

size_t mystrlen(const(char)* str) nothrow
{
	size_t len = 0;
	while(*str++)
		len++;
	return len;
}

///////// shut up compiler generated GC info failing to link
extern(C)
{
	int D10TypeInfo_v6__initZ;
	int D16TypeInfo_Pointer6__vtblZ;
	int D17TypeInfo_Function6__vtblZ;
}
