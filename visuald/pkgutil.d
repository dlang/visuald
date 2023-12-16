// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.pkgutil;

import visuald.hierutil;
import visuald.comutil;
import visuald.logutil;
import visuald.dpackage;

import std.algorithm;
import std.conv;
import std.utf;
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

void deleteVisualDOutputPane()
{
	auto win = queryService!(IVsOutputWindow)();
	if(!win)
		return;
	scope(exit) release(win);

	win.DeletePane(&g_outputPaneCLSID);
}

void clearOutputPane()
{
	auto win = queryService!(IVsOutputWindow)();
	if(!win)
		return;
	scope(exit) release(win);

	IVsOutputWindowPane pane;
	if(win.GetPane(&g_outputPaneCLSID, &pane) == S_OK && pane)
		pane.Clear();
	release(pane);
}

IVsOutputWindowPane getVisualDOutputPane()
{
	auto win = queryService!(IVsOutputWindow)();
	if(!win)
		return null;
	scope(exit) release(win);

	IVsOutputWindowPane pane;
	if(win.GetPane(&g_outputPaneCLSID, &pane) == S_OK && pane)
		return pane;
	if(win.CreatePane(&g_outputPaneCLSID, "Visual D", false, true) == S_OK)
		if(win.GetPane(&g_outputPaneCLSID, &pane) == S_OK && pane)
			return pane;

	if(win.GetPane(&GUID_BuildOutputWindowPane, &pane) != S_OK || !pane)
		return null;
	return pane;
}

IVsOutputWindowPane getBuildOutputPane()
{
	auto win = queryService!(IVsOutputWindow)();
	if(!win)
		return null;
	scope(exit) release(win);

	IVsOutputWindowPane pane;
	if(win.GetPane(&GUID_BuildOutputWindowPane, &pane) != S_OK || !pane)
		return null;
	return pane;
}

void openSettingsPage(in GUID clsid)
{
	auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
	if (!pIVsUIShell)
		return;
	wstring pageGuid = GUID2wstring(clsid);
	VARIANT var;
	var.vt = VT_BSTR;
	var.bstrVal = allocwBSTR(pageGuid);
	pIVsUIShell.PostExecCommand(&CMDSETID_StandardCommandSet97, cmdidToolsOptions, OLECMDEXECOPT_DODEFAULT, &var);
	freeBSTR(var.bstrVal);
}

class OutputPaneBuffer
{
	static shared(string) buffer;
	static shared(Object) syncOut = new shared(Object);

	static void push(string msg)
	{
		synchronized(OutputPaneBuffer.syncOut)
			buffer ~= msg;
	}

	static string pop()
	{
		string msg;
		synchronized(OutputPaneBuffer.syncOut)
		{
			msg = buffer;
			buffer = buffer.init;
		}
		return msg;
	}

	static void flush()
	{
		if(buffer.length)
		{
			string msg = pop();
			writeToBuildOutputPane(msg);
		}
	}
}

void writeToBuildOutputPane(string msg)
{
	if(IVsOutputWindowPane pane = getVisualDOutputPane())
	{
		scope(exit) release(pane);
		pane.Activate();
		pane.OutputString(_toUTF16z(msg));
	}
	else
		OutputPaneBuffer.push(msg);
}

bool OutputErrorString(string msg)
{
	if (IVsOutputWindowPane pane = getVisualDOutputPane())
	{
		scope(exit) release(pane);
		pane.OutputString(toUTF16z(msg));
	}
	return false;
}

bool tryWithExceptionToBuildOutputPane(T)(T dg, string errInfo = "")
{
	try
	{
		dg();
		return true;
	}
	catch(Exception e)
	{
		string msg = e.toString();
		if(errInfo.length)
			msg = errInfo ~ ": " ~ msg;
		writeToBuildOutputPane(msg);
		logCall("EXCEPTION: " ~ msg);
	}
	return false;
}

string _browseFile(T)(HWND parentHwnd, string title, string filter, string initdir)
{
	if (auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false))
	{
		wchar[260] fileName;
		fileName[0] = 0;
		T ofn;
		ofn.lStructSize = ofn.sizeof;
		ofn.hwndOwner = parentHwnd;
		ofn.pwzDlgTitle = toUTF16z(title);
		ofn.pwzFileName = fileName.ptr;
		ofn.nMaxFileName = fileName.length;
		ofn.pwzInitialDir = toUTF16z(initdir);
		ofn.pwzFilter = toUTF16z(filter);
		static if(is(T == VSOPENFILENAMEW))
			auto rc = pIVsUIShell.GetOpenFileNameViaDlg(&ofn);
		else
			auto rc = pIVsUIShell.GetSaveFileNameViaDlg(&ofn);

		if (rc == S_OK)
			return to_string(fileName.ptr);
	}
	return null;
}
string browseFile(HWND parentHwnd, string title, string filter, string initdir = null)
{
	return _browseFile!(VSOPENFILENAMEW)(parentHwnd, title, filter, initdir);
}

string browseSaveFile(HWND parentHwnd, string title, string filter, string initdir = null)
{
	return _browseFile!(VSSAVEFILENAMEW)(parentHwnd, title, filter, initdir);
}

string browseDirectory(HWND parentHwnd, string title, string initdir = null)
{
	if (auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false))
	{
		wchar[260] dirName;
		dirName[0] = 0;
		VSBROWSEINFOW bi;
		bi.lStructSize = bi.sizeof;
		bi.hwndOwner = parentHwnd;
		bi.pwzDlgTitle = toUTF16z(title);
		bi.pwzDirName = dirName.ptr;
		bi.nMaxDirName = dirName.length;
		bi.pwzInitialDir = toUTF16z(initdir);
		if (pIVsUIShell.GetDirectoryViaBrowseDlg(&bi) == S_OK)
			return to_string(dirName.ptr);
	}
	return null;
}

///////////////////////////////////////////////////////////////////////
// version = DEBUG_GC;
version(DEBUG_GC)
{
import rsgc.gc;
import rsgc.gcx;
import rsgc.gcstats;
import std.string;

void writeGCStatsToOutputPane()
{
	GCStats stats =	gc_stats();
	writeToBuildOutputPane(format("numpools = %s, poolsize = %s, usedsize = %s, freelistsize = %s\n",
		   stats.numpools, stats.poolsize, stats.usedsize, stats.freelistsize));
    writeToBuildOutputPane(format("pool[B_16]    = %s\n", stats.numpool[Bins.B_16]   ));
    writeToBuildOutputPane(format("pool[B_32]    = %s\n", stats.numpool[Bins.B_32]   ));
    writeToBuildOutputPane(format("pool[B_64]    = %s\n", stats.numpool[Bins.B_64]   ));
    writeToBuildOutputPane(format("pool[B_128]   = %s\n", stats.numpool[Bins.B_128]  ));
    writeToBuildOutputPane(format("pool[B_256]   = %s\n", stats.numpool[Bins.B_256]  ));
    writeToBuildOutputPane(format("pool[B_512]   = %s\n", stats.numpool[Bins.B_512]  ));
    writeToBuildOutputPane(format("pool[B_1024]  = %s\n", stats.numpool[Bins.B_1024] ));
    writeToBuildOutputPane(format("pool[B_2048]  = %s\n", stats.numpool[Bins.B_2048] ));
    writeToBuildOutputPane(format("pool[B_PAGE]  = %s\n", stats.numpool[Bins.B_PAGE] ));
    writeToBuildOutputPane(format("pool[B_PAGE+] = %s\n", stats.numpool[Bins.B_PAGEPLUS]));
    writeToBuildOutputPane(format("pool[B_FREE]  = %s\n", stats.numpool[Bins.B_FREE] ));
    writeToBuildOutputPane(format("pool[B_UNCOM] = %s\n", stats.numpool[Bins.B_UNCOMMITTED]));
	writeClasses();
}

extern extern(C) __gshared ModuleInfo*[] _moduleinfo_array;

void writeClasses()
{
	foreach(mi; _moduleinfo_array)
	{
		auto classes = mi.localClasses();
		foreach(c; classes)
		{
			string flags;
			if(c.m_flags & 1) flags ~= " IUnknown";
			if(c.m_flags & 2) flags ~= " NoGC";
			if(c.m_flags & 4) flags ~= " OffTI";
			if(c.m_flags & 8) flags ~= " Constr";
			if(c.m_flags & 16) flags ~= " xgetM";
			if(c.m_flags & 32) flags ~= " tinfo";
			if(c.m_flags & 64) flags ~= " abstract";
			writeToBuildOutputPane(text(c.name, ": ", c.init.length, " bytes, flags: ", flags, "\n"));

			foreach(m; c.getMembers([]))
			{
				auto cm = cast() m;
				writeToBuildOutputPane(text("    ", cm.name(), "\n"));
			}
		}
	}
}
}

///////////////////////////////////////////////////////////////////////
HRESULT GetSelectionForward(IVsTextView view, int*startLine, int*startCol, int*endLine, int*endCol)
{
	HRESULT hr = view.GetSelection(startLine, startCol, endLine, endCol);
	if(FAILED(hr))
		return hr;
	if(*startLine > *endLine)
	{
		std.algorithm.swap(*startLine, *endLine);
		std.algorithm.swap(*startCol, *endCol);
	}
	else if(*startLine == *endLine && *startCol > *endCol)
		std.algorithm.swap(*startCol, *endCol);
	return hr;
}

///////////////////////////////////////////////////////////////////////
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

	//delete h;
	return true;
}

//import pkgutil;
import sdk.port.base;

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

////////////////////////////////////////////////////////////////////////////////
import sdk.vsi.vsshell140;

class VDInfoBarTextSpan : ComObject, IVsInfoBarTextSpan
{
	string message;

	this(string msg)
	{
		message = msg;
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBarTextSpan) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    // the text for the span
	HRESULT get_Text(BSTR* text)
	{
		*text = allocBSTR(message);
		return S_OK;
	}

    // formatting options for the text
	HRESULT get_Bold(VARIANT_BOOL* bold)
	{
		*bold = FALSE;
		return S_OK;
	}
	HRESULT get_Italic(VARIANT_BOOL* italic)
	{
		*italic = FALSE;
		return S_OK;
	}
	HRESULT get_Underline(VARIANT_BOOL* underline)
	{
		*underline = FALSE;
		return S_OK;
	}
}

class VDInfoBarTextSpanCollection : ComObject, IVsInfoBarTextSpanCollection
{
	VDInfoBarTextSpan textSpan;

	this(string msg)
	{
		textSpan = newCom!VDInfoBarTextSpan(msg);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBarTextSpanCollection) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    // Gets the number of spans stored in the collection.
	HRESULT get_Count(int* count)
	{
		*count = 1;
		return S_OK;
	}

    // Gets the span stored at a specific index in the collection.
    HRESULT GetSpan(const int index, IVsInfoBarTextSpan * span)
	{
		if (index != 0)
			return E_FAIL;
		*span = addref(textSpan);
		return S_OK;
	}
}

class VDInfoBarActionItem : VDInfoBarTextSpan, IVsInfoBarActionItem
{
	int index;

	this(int idx, string msg)
	{
		index = idx;
		super(msg);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBarActionItem) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    // Gets the user-provided context associated with the hyperlink.
    // This contextual data can be used to identify the hyperlink when it's clicked.
	HRESULT get_ActionContext(VARIANT* context)
	{
		context.vt = VT_INT;
		context.intVal = index;
		return S_OK;
	}

    // Gets whether or not this action item should be rendered as a button.
    // By default, action items are rendered as a hyperlink.
	HRESULT get_IsButton(VARIANT_BOOL* isButton)
	{
		*isButton = FALSE;
		return S_OK;
	}
}

class VDInfoBarActionItemCollection : ComObject, IVsInfoBarActionItemCollection
{
	VDInfoBarActionItem action;

	this(string msg)
	{
		action = newCom!VDInfoBarActionItem(0, msg);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBarActionItemCollection) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    // Gets the number of spans stored in the collection.
	HRESULT get_Count(int* count)
	{
		*count = 1;
		return S_OK;
	}

    // Gets the span stored at a specific index in the collection.
    HRESULT GetItem(const int index, IVsInfoBarActionItem * item)
	{
		if (index != 0)
			return S_FALSE;
		*item = addref(action);
		return S_OK;
	}
}

class VDInfoBar : ComObject, IVsInfoBar
{
	VDInfoBarTextSpanCollection spans;
	VDInfoBarActionItemCollection actions;

	this(string msg, string action)
	{
		spans = newCom!VDInfoBarTextSpanCollection(msg);
		if(action)
			actions = newCom!VDInfoBarActionItemCollection(action);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBar) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// Gets the moniker for the image to display in the info bar
    /+[ propget]+/
	HRESULT get_Image(/+[out, retval]+/ ImageMoniker* moniker)
	{
		*moniker = ImageMoniker.init;
		return S_FALSE;
	}

    // Gets whether or not the InfoBar supports closing
	HRESULT get_IsCloseButtonVisible(/+[out, retval]+/ VARIANT_BOOL* closeButtonVisible)
	{
		*closeButtonVisible = TRUE;
		return S_OK;
	}

    // Gets the collection of text spans displayed in the info bar.  Any
    // IVsInfoBarActionItem spans in this collection will be rendered as a hyperlink.
	HRESULT get_TextSpans(IVsInfoBarTextSpanCollection * textSpans)
	{
		*textSpans = addref(spans);
		return S_OK;
	}

    // Gets the collection of action items displayed in the info bar
	HRESULT get_ActionItems(IVsInfoBarActionItemCollection * actionItems)
	{
		*actionItems = addref(actions);
		return S_FALSE;
	}
}

class VDInfoBarUIEvents : ComObject, IVsInfoBarUIEvents
{
	extern(D) bool delegate(int) onAction;
	IVsInfoBarUIElement uiElement;

	this(typeof(onAction) dg, IVsInfoBarUIElement ui)
	{
		onAction = dg;
		uiElement = ui;
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsInfoBarUIEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    // Callback invoked when the close button on an info bar is clicked
    HRESULT OnClosed(/+[in]+/ IVsInfoBarUIElement infoBarUIElement)
	{
		return S_OK;
	}

    // Callback invoked when an action item on an info bar is clicked
    HRESULT OnActionItemClicked(/+[in]+/ IVsInfoBarUIElement infoBarUIElement, /+[in]+/ IVsInfoBarActionItem actionItem)
	{
		VARIANT var;
		if(auto hr = actionItem.get_ActionContext(&var))
			return hr;
		if (onAction(var.intVal) && uiElement)
		{
			if (auto barHost = getInfoBarHost())
			{
				scope(exit) release(barHost);
				barHost.RemoveInfoBar(uiElement);
			}
		}
		return S_OK;
	}
}

IVsInfoBarHost getInfoBarHost()
{
	auto pIVsShell = ComPtr!(IVsShell)(queryService!(IVsShell), false);
	if(!pIVsShell)
		return null;

	VARIANT var;
	if(!SUCCEEDED(pIVsShell.GetProperty(VSSPROPID_MainWindowInfoBarHost, &var)))
		return null;
	if(var.vt != VT_UNKNOWN)
		return null;
	scope(exit) release(var.punkVal);

	auto barHost = qi_cast!IVsInfoBarHost(var.punkVal);
	return barHost;
}

bool showInfoBar(string msg, string action, bool delegate(int) dg)
{
	import sdk.vsi.vsplatformui;
	auto pUIFactory = ComPtr!(IVsInfoBarUIFactory)(queryService!(SVsInfoBarUIFactory, IVsInfoBarUIFactory), false);
	if(!pUIFactory)
		return false;

	auto barHost = getInfoBarHost();
	if (!barHost)
		return false;
	scope(exit) release(barHost);

	auto info = newCom!VDInfoBar(msg, action);
	IVsInfoBarUIElement pUIElement;
	if (!SUCCEEDED(pUIFactory.CreateInfoBar(info, &pUIElement)))
		return false;
	scope(exit) release(pUIElement);

	if(dg)
	{
		DWORD cookie;
		pUIElement.Advise(newCom!VDInfoBarUIEvents(dg, pUIElement), &cookie);
	}

	barHost.AddInfoBar(pUIElement);
	return true;
}

///////////////////////////////////////////////////////////////////////
interface ISetupInstance : IUnknown
{
	// static const GUID iid = uuid("B41463C3-8866-43B5-BC33-2B0676F7F42E");
	static const GUID iid = { 0xB41463C3, 0x8866, 0x43B5, [ 0xBC, 0x33, 0x2B, 0x06, 0x76, 0xF7, 0xF4, 0x2E ] };

    int GetInstanceId(BSTR* pbstrInstanceId);
    int GetInstallDate(LPFILETIME pInstallDate);
    int GetInstallationName(BSTR* pbstrInstallationName);
    int GetInstallationPath(BSTR* pbstrInstallationPath);
    int GetInstallationVersion(BSTR* pbstrInstallationVersion);
    int GetDisplayName(LCID lcid, BSTR* pbstrDisplayName);
    int GetDescription(LCID lcid, BSTR* pbstrDescription);
    int ResolvePath(LPCOLESTR pwszRelativePath, BSTR* pbstrAbsolutePath);
}

interface IEnumSetupInstances : IUnknown
{
	// static const GUID iid = uuid("6380BCFF-41D3-4B2E-8B2E-BF8A6810C848");

    int Next(ULONG celt, ISetupInstance* rgelt, ULONG* pceltFetched);
    int Skip(ULONG celt);
    int Reset();
    int Clone(IEnumSetupInstances* ppenum);
}

interface ISetupConfiguration : IUnknown
{
	// static const GUID iid = uuid("42843719-DB4C-46C2-8E7C-64F1816EFD5B");
	static const GUID iid = { 0x42843719, 0xDB4C, 0x46C2, [ 0x8E, 0x7C, 0x64, 0xF1, 0x81, 0x6E, 0xFD, 0x5B ] };

    int EnumInstances(IEnumSetupInstances* ppEnumInstances) ;
	int GetInstanceForCurrentProcess(ISetupInstance* ppInstance);
	int GetInstanceForPath(LPCWSTR wzPath, ISetupInstance* ppInstance);
};

const GUID iid_SetupConfiguration = { 0x177F0C4A, 0x1CD3, 0x4DE7, [ 0xA3, 0x2C, 0x71, 0xDB, 0xBB, 0x9F, 0xA3, 0x6D ] };

string findVCInstallDirViaCOM(bool delegate(string) verify)
{
	import sdk.win32.objbase;

	CoInitialize(null);
	scope(exit) CoUninitialize();

	ISetupConfiguration setup;
	IEnumSetupInstances instances;
	ISetupInstance instance;
	DWORD fetched;

	GUID clsid = iid_SetupConfiguration;
	GUID iid = ISetupConfiguration.iid;
	HRESULT hr = CoCreateInstance(clsid, null, CLSCTX_ALL, iid, cast(void**) &setup);
	if (hr != S_OK || !setup)
		return null;
	scope(exit) setup.Release();

	if (setup.EnumInstances(&instances) != S_OK)
		return null;
	scope(exit) instances.Release();

	while (instances.Next(1, &instance, &fetched) == S_OK && fetched)
	{
		BSTR installDir;
		if (instance.GetInstallationPath(&installDir) != S_OK)
			continue;

		string path = detachBSTR(installDir);
		if (!verify || verify(path))
			return path;
	}

	return null;
}

