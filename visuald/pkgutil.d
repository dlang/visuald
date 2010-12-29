// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module pkgutil;

import hierutil;
import comutil;

import std.conv;
import sdk.vsi.vsshell;

void showStatusBarText(wstring txt)
{
	auto pIVsStatusbar = queryService!(IVsStatusbar);
	if(pIVsStatusbar)
	{
		scope(exit) release(pIVsStatusbar);
		pIVsStatusbar.SetText((txt ~ "\0"w).ptr);
	}
}

void showStatusBarText(string txt)
{
	showStatusBarText(to!wstring(txt));
}

// Hardware Breakpoint Functions

enum 
{
	HWBRK_TYPE_CODE,
	HWBRK_TYPE_READWRITE,
	HWBRK_TYPE_WRITE,
}
alias int HWBRK_TYPE;

enum
{
	HWBRK_SIZE_1,
	HWBRK_SIZE_2,
	HWBRK_SIZE_4,
	HWBRK_SIZE_8,
}
alias int HWBRK_SIZE;

struct HWBRK
{
public:
	void* a;
	HANDLE hT;
	HWBRK_TYPE Type;
	HWBRK_SIZE Size;
	HANDLE hEv;
	int iReg;
	int Opr;
	bool SUCC;
}

void SetBits(ref uint dw, int lowBit, int bits, int newValue)
{
	DWORD_PTR mask = (1 << bits) - 1; 
	dw = (dw & ~(mask << lowBit)) | (newValue << lowBit);
}

extern(Windows) DWORD thSuspend(LPVOID lpParameter)
{
	HWBRK* h = cast(HWBRK*)lpParameter;
	int j = 0;
	int y = 0;

	j = SuspendThread(h.hT);
    y = GetLastError();
	
	h.SUCC = th(h);

	j = ResumeThread(h.hT);
    y = GetLastError();

	SetEvent(h.hEv);
	return 0;
}

bool th(HWBRK* h)
{
	int j = 0;
	int y = 0;
	CONTEXT ct;
	ct.ContextFlags = CONTEXT_DEBUG_REGISTERS;
	j = GetThreadContext(h.hT,&ct);
	y = GetLastError();

	int FlagBit = 0;

	bool Dr0Busy = false;
	bool Dr1Busy = false;
	bool Dr2Busy = false;
	bool Dr3Busy = false;
	if (ct.Dr7 & 1)
		Dr0Busy = true;
	if (ct.Dr7 & 4)
		Dr1Busy = true;
	if (ct.Dr7 & 16)
		Dr2Busy = true;
	if (ct.Dr7 & 64)
		Dr3Busy = true;

	if (h.Opr == 1)
	{
		// Remove
		if (h.iReg == 0)
		{
			FlagBit = 0;
			ct.Dr0 = 0;
			Dr0Busy = false;
		}
		if (h.iReg == 1)
		{
			FlagBit = 2;
			ct.Dr1 = 0;
			Dr1Busy = false;
		}
		if (h.iReg == 2)
		{
			FlagBit = 4;
			ct.Dr2 = 0;
			Dr2Busy = false;
		}
		if (h.iReg == 3)
		{
			FlagBit = 6;
			ct.Dr3 = 0;
			Dr3Busy = false;
		}

		ct.Dr7 &= ~(1 << FlagBit);
	}
	else
	{
		if (!Dr0Busy)
		{
			h.iReg = 0;
			ct.Dr0 = cast(DWORD)h.a;
			Dr0Busy = true;
		}
		else if (!Dr1Busy)
		{
			h.iReg = 1;
			ct.Dr1 = cast(DWORD)h.a;
			Dr1Busy = true;
		}
		else if (!Dr2Busy)
		{
			h.iReg = 2;
			ct.Dr2 = cast(DWORD)h.a;
			Dr2Busy = true;
		}
		else if (!Dr3Busy)
		{
			h.iReg = 3;
			ct.Dr3 = cast(DWORD)h.a;
			Dr3Busy = true;
		}
		else
		{
			return false;
		}
		ct.Dr6 = 0;
		int st = 0;
		if (h.Type == HWBRK_TYPE_CODE)
			st = 0;
		if (h.Type == HWBRK_TYPE_READWRITE)
			st = 3;
		if (h.Type == HWBRK_TYPE_WRITE)
			st = 1;
		int le = 0;
		if (h.Size == HWBRK_SIZE_1)
			le = 0;
		if (h.Size == HWBRK_SIZE_2)
			le = 1;
		if (h.Size == HWBRK_SIZE_4)
			le = 3;
		if (h.Size == HWBRK_SIZE_8)
			le = 2;

		SetBits(ct.Dr7, 16 + h.iReg*4, 2, st);
		SetBits(ct.Dr7, 18 + h.iReg*4, 2, le);
		SetBits(ct.Dr7, h.iReg*2,1,1);
	}


	ct.ContextFlags = CONTEXT_DEBUG_REGISTERS;
	j = SetThreadContext(h.hT,&ct);
    y = GetLastError();

	ct.ContextFlags = CONTEXT_DEBUG_REGISTERS;
	j = GetThreadContext(h.hT,&ct);
    y = GetLastError();
	
	return true;
}

extern(C)
HANDLE SetHardwareBreakpoint(HANDLE hThread,HWBRK_TYPE Type,HWBRK_SIZE Size,void* s)
{
	//HWBRK* h = new HWBRK;
	HWBRK h;
	h.a = s;
	h.Size = Size;
	h.Type = Type;
	h.hT = hThread;

	if (hThread == GetCurrentThread())
	{
		DWORD pid = GetCurrentThreadId();
		h.hT = OpenThread(THREAD_SUSPEND_RESUME|THREAD_GET_CONTEXT|THREAD_SET_CONTEXT,0,pid);
	}

version(none)
{
	h.hEv = CreateEvent(null,0,0,null);
	h.Opr = 0; // Set Break
	HANDLE hY = CreateThread(null,0,&thSuspend,cast(LPVOID)&h,0,null);
	WaitForSingleObject(h.hEv,INFINITE);
	CloseHandle(h.hEv);
	h.hEv = null;
}
else
{
	th(&h);
}
	
	if (hThread == GetCurrentThread())
	{
		CloseHandle(h.hT);
	}
	h.hT = hThread;

//	if (!h.SUCC)
	{
//		delete h;
		return null;
	}

//	return cast(HANDLE)h;
}

extern(C)
bool RemoveHardwareBreakpoint(HANDLE hBrk)
{
	HWBRK* h = cast(HWBRK*)hBrk;
	if (!h)
		return false;

	bool C = false;
	if (h.hT == GetCurrentThread())
	{
		DWORD pid = GetCurrentThreadId();
		h.hT = OpenThread(THREAD_ALL_ACCESS,0,pid);
		C = true;
	}

	h.hEv = CreateEvent(null,0,0,null);
	h.Opr = 1; // Remove Break
	HANDLE hY = CreateThread(null,0,&thSuspend,cast(LPVOID)h,0,null);
	WaitForSingleObject(h.hEv,INFINITE);
	CloseHandle(h.hEv);
	h.hEv = null;

	if (C)
	{
		CloseHandle(h.hT);
	}

	delete h;
	return true;
}

//import pkgutil;
import sdk.port.base;
import dllmain;

void setHWBreakpopints()
{
	char[] data = new char[16];
	HANDLE hnd;
	void* addr1 = data.ptr - 0x71bffc0 + 0x71bf720; 
	void* addr2 = data.ptr - 0x71bffc0 + 0x71bf8a0; 
	void* addr3 = data.ptr - 0x71eff60 + 0x71e6420; 
	void* addr4 = data.ptr - 0x71eff60 + 0x71e6440; 
	hnd = SetHardwareBreakpoint(GetCurrentThread(), HWBRK_TYPE_WRITE, HWBRK_SIZE_4, addr1);
	//hnd = SetHardwareBreakpoint(GetCurrentThread(), HWBRK_TYPE_READWRITE, HWBRK_SIZE_4, addr2);
	//hnd = SetHardwareBreakpoint(GetCurrentThread(), HWBRK_TYPE_WRITE, HWBRK_SIZE_4, addr3);
	//hnd = SetHardwareBreakpoint(GetCurrentThread(), HWBRK_TYPE_WRITE, HWBRK_SIZE_4, addr4);
	addr1 = null;
	addr2 = null;
	addr3 = null;
	addr4 = null;
}
	