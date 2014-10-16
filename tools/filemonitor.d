// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module filemonitor;

//import std.c.windows.windows;
import core.sys.windows.windows;
//import core.sys.windows.dll;
import core.stdc.stdio;
import core.stdc.string;

// version = msgbox;
// check for @nogc support
static if(!__traits(compiles, () { @nogc void fn(); }))
	struct nogc {};

__gshared HINSTANCE g_hInst;
extern(C) __gshared int _acrtused_dll;

export __gshared char[260] dumpFile = [ 0 ];
__gshared HANDLE hndDumpFile = INVALID_HANDLE_VALUE;
__gshared HANDLE hndMutex = INVALID_HANDLE_VALUE;

extern(Windows) HANDLE CreateMutexA(LPSECURITY_ATTRIBUTES lpMutexAttributes, BOOL bInitialOwner, LPCSTR lpName) nothrow @nogc;
extern(Windows) BOOL ReleaseMutex(HANDLE hMutex) nothrow @nogc;

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
	version(msgbox)
	{
		if(ulReason == DLL_PROCESS_ATTACH)
			MessageBoxA(null, "DLL_PROCESS_ATTACH", "filemonitor", MB_OK);
		if(ulReason == DLL_PROCESS_DETACH)
			MessageBoxA(null, "DLL_PROCESS_DETACH", "filemonitor", MB_OK);
		if(ulReason == DLL_THREAD_ATTACH)
			MessageBoxA(null, "DLL_THREAD_ATTACH", "filemonitor", MB_OK);
		if(ulReason == DLL_THREAD_DETACH)
			MessageBoxA(null, "DLL_THREAD_DETACH", "filemonitor", MB_OK);
	}
	g_hInst = hInstance;
	if(ulReason == DLL_PROCESS_ATTACH || ulReason == DLL_THREAD_ATTACH)
	{
		if (dumpFile[0]) // only execute if it was injected by pipedmd
		{
			origWriteFile = getWriteFileFunc();
			if(!origCreateFileA)
				RedirectCreateFileA();
			if(!origCreateFileW)
				RedirectCreateFileW();
		}
	}
	return true;
}

alias typeof(&CreateFileA) fnCreateFileA;
alias typeof(&CreateFileW) fnCreateFileW;
alias typeof(&WriteFile) fnWriteFile;
__gshared fnCreateFileA origCreateFileA;
__gshared fnCreateFileW origCreateFileW;
__gshared fnWriteFile origWriteFile;

__gshared fnCreateFileA myCF = &MyCreateFileA;

alias typeof(&VirtualProtect) fnVirtualProtect;

fnVirtualProtect getVirtualProtectFunc()
{
	version(all)
	{
		HANDLE krnl = GetModuleHandleA("kernel32.dll");
		return cast(fnVirtualProtect) GetProcAddress(krnl, "VirtualProtect");
	}
	else
	{
		return &VirtualProtect;
	}
}

fnWriteFile getWriteFileFunc()
{
	version(all)
	{
		HANDLE krnl = GetModuleHandleA("kernel32.dll");
		return cast(fnWriteFile) GetProcAddress(krnl, "WriteFile");
	}
	else
	{
		return &WriteFile;
	}
}

void RedirectCreateFileA()
{
	version(msgbox) MessageBoxA(null, "RedirectCreateFileA", "filemonitor", MB_OK);
	ubyte* jmpAdr = cast(ubyte*)&CreateFileA;
	auto impTableEntry = cast(fnCreateFileA*) (*cast(void**)(jmpAdr + 2));
	origCreateFileA = *impTableEntry;

	DWORD oldProtect, newProtect;
	auto pfnVirtualProtect = getVirtualProtectFunc();
	pfnVirtualProtect(impTableEntry, (*impTableEntry).sizeof, PAGE_READWRITE, &oldProtect);
	*impTableEntry = &MyCreateFileA;
	pfnVirtualProtect(impTableEntry, (*impTableEntry).sizeof, oldProtect, &newProtect);
}

void RedirectCreateFileW()
{
	version(msgbox) MessageBoxA(null, "RedirectCreateFileW", "filemonitor", MB_OK);
	ubyte* jmpAdr = cast(ubyte*)&CreateFileW;
	auto impTableEntry = cast(fnCreateFileW*) (*cast(void**)(jmpAdr + 2));
	origCreateFileW = *impTableEntry;

	DWORD oldProtect, newProtect;
	auto pfnVirtualProtect = getVirtualProtectFunc();
	pfnVirtualProtect(impTableEntry, (*impTableEntry).sizeof, PAGE_READWRITE, &oldProtect);
	*impTableEntry = &MyCreateFileW;
	pfnVirtualProtect(impTableEntry, (*impTableEntry).sizeof, oldProtect, &newProtect);
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
			) nothrow @nogc
{
	version(msgbox) MessageBoxA(null, lpFileName, dumpFile.ptr/*"CreateFile"*/, MB_OK);
	//	printf("CreateFileA(%s)\n", lpFileName);
	auto hnd = origCreateFileA(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, 
							   dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
	if(hnd != INVALID_HANDLE_VALUE && isLoggableOpen(dwDesiredAccess, dwCreationDisposition, dwFlagsAndAttributes))
	{
		if(dumpFile[0] && hndDumpFile == INVALID_HANDLE_VALUE)
		{
			hndDumpFile = origCreateFileA(dumpFile.ptr, GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
			hndMutex = CreateMutexA(null, false, null);
		}
		if(hndDumpFile != INVALID_HANDLE_VALUE)
		{
			// combine writes to "atomic" write to avoid wrong placing of newlines
			if(hndMutex != INVALID_HANDLE_VALUE)
				WaitForSingleObject(hndMutex, INFINITE);

			size_t length = mystrlen(lpFileName);
			origWriteFile(hndDumpFile, lpFileName, length, &length, null);
			origWriteFile(hndDumpFile, "\n".ptr, 1, &length, null);

			if(hndMutex != INVALID_HANDLE_VALUE)
				ReleaseMutex(hndMutex);
		}
	}
	return hnd;
}

extern(Windows) HANDLE
MyCreateFileW(
			/*__in*/     LPCWSTR lpFileName,
			/*__in*/     DWORD dwDesiredAccess,
			/*__in*/     DWORD dwShareMode,
			/*__in_opt*/ LPSECURITY_ATTRIBUTES lpSecurityAttributes,
			/*__in*/     DWORD dwCreationDisposition,
			/*__in*/     DWORD dwFlagsAndAttributes,
			/*__in_opt*/ HANDLE hTemplateFile
			) nothrow @nogc
{
	version(msgbox) MessageBoxW(null, lpFileName, "CreateFileW", MB_OK);
	//	printf("CreateFileA(%s)\n", lpFileName);
	auto hnd = origCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, 
							   dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
	if(hnd != INVALID_HANDLE_VALUE && isLoggableOpen(dwDesiredAccess, dwCreationDisposition, dwFlagsAndAttributes))
	{
		if(dumpFile[0] && hndDumpFile == INVALID_HANDLE_VALUE)
		{
			hndMutex = CreateMutexA(null, false, null);
			if(hndMutex != INVALID_HANDLE_VALUE)
				WaitForSingleObject(hndMutex, INFINITE);
			
			if(hndDumpFile == INVALID_HANDLE_VALUE)
				hndDumpFile = origCreateFileA(dumpFile.ptr, GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);

			ushort bom = 0xFEFF;
			size_t written;
			if(hndDumpFile != INVALID_HANDLE_VALUE)
				origWriteFile(hndDumpFile, &bom, 2, &written, null);

			if(hndMutex != INVALID_HANDLE_VALUE)
				ReleaseMutex(hndMutex);
		}
		if(hndDumpFile != INVALID_HANDLE_VALUE)
		{
			// combine writes to "atomic" write to avoid wrong placing of newlines
			if(hndMutex != INVALID_HANDLE_VALUE)
				WaitForSingleObject(hndMutex, INFINITE);

			size_t length = mystrlen(lpFileName);
			origWriteFile(hndDumpFile, lpFileName, 2*length, &length, null);
			origWriteFile(hndDumpFile, "\n".ptr, 2, &length, null);

			if(hndMutex != INVALID_HANDLE_VALUE)
				ReleaseMutex(hndMutex);
		}
	}
	return hnd;
}

bool isLoggableOpen(DWORD dwDesiredAccess, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes) nothrow @nogc
{
	if(!(dwDesiredAccess & GENERIC_READ))
		return false;
	if(!(dwDesiredAccess & GENERIC_WRITE))
		return true;
	if(dwCreationDisposition == CREATE_ALWAYS || dwCreationDisposition == TRUNCATE_EXISTING)
		return false;
	if(dwFlagsAndAttributes & FILE_ATTRIBUTE_TEMPORARY)
		return false;
	return true;
}

size_t mystrlen(const(char)* str) nothrow @nogc
{
	size_t len = 0;
	while(*str++)
		len++;
	return len;
}

size_t mystrlen(const(wchar)* str) nothrow @nogc
{
	size_t len = 0;
	while(*str++)
		len++;
	return len;
}

///////// shut up compiler generated GC info failing to link
extern(C)
{
	__gshared int D10TypeInfo_i6__initZ;
	__gshared int D10TypeInfo_v6__initZ;
	__gshared int D16TypeInfo_Pointer6__vtblZ;
	__gshared int D17TypeInfo_Function6__vtblZ;
	__gshared int D15TypeInfo_Struct6__vtblZ;
}
