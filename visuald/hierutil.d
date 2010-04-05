module hierutil;

import std.c.windows.windows;
import std.c.windows.com;
import std.string;
import std.path;
import std.utf;
import std.stream;

import sdk.vsi.vsshell;
import dte = sdk.vsi.dte80a;
import comutil;
import dpackage;
import chiernode;
import chiercontainer;

const uint _MAX_PATH = 260;

extern(Windows)
{
	HWND GetActiveWindow();
	BOOL IsWindowEnabled(HWND hWnd);
	BOOL EnableWindow(HWND hWnd, BOOL bEnable);
	int MessageBoxW(HWND hWnd, in wchar* lpText, in wchar* lpCaption, uint uType);

	void* GlobalLock(HANDLE hMem);
	int GlobalUnlock(HANDLE hMem);
}

///////////////////////////////////////////////////////////////////////
I queryService(SVC,I)()
{
	IServiceProvider sp = dpackage.Package.s_instance.getServiceProvider();
	if(!sp)
		return null;

	I svc;
	if(FAILED(sp.QueryService(&SVC.iid, &I.iid, cast(void **)&svc)))
		return null;
	return svc;
}

I queryService(I)()
{
	return queryService!(I,I);
}

///////////////////////////////////////////////////////////////////////
version(D_Version2)
{} else
	int indexOf(string s, dchar ch) { return find(s, ch); }

///////////////////////////////////////////////////////////////////////

bool contains(T)(ref T[] arr, T val)
{
	foreach(T t; arr)
		if (t == val)
			return true;
	return false;
}

void addunique(T)(ref T[] arr, T val)
{
	if (!contains(arr, val))
		arr ~= val;
}

///////////////////////////////////////////////////////////////////////
int CompareFilenamesForSort(string f1, string f2)
{
	if(f1 == f2)
		return 0;
	if(f1 < f2)
		return -1;
	return 1;
}

bool ContainsInvalidFileChars(string name)
{
	string invalid = "\\/:*?\"<>|";
	foreach(dchar ch; name)
		if(indexOf(invalid, ch) >= 0)
			return true;
	return false;
}

bool CheckFileName(string fileName)
{
	if (fileName.length == 0 || fileName.length >= _MAX_PATH)
		return false;
	
	string base = getName(getBaseName(fileName));
	if(base.length == 0 || ContainsInvalidFileChars(base))
		return false;

	static string reservedNames[] = 
	[
		"CON", "PRN", "AUX", "CLOCK$", "NUL", 
		"COM1","COM2", "COM3","COM4","COM5", "COM6", "COM7","COM8", "COM9",
		"LPT1","LPT2", "LPT3","LPT4","LPT5", "LPT6", "LPT7","LPT8", "LPT9" 
	];

	base = toupper(base);
	foreach(rsvd; reservedNames)
		if(base == rsvd)
			return false;
	return true;
}

//---------------------------------------------------------------------------
// Class: CVsModalState
//      Manage Modal State
//---------------------------------------------------------------------------
class CVsModalState 
{
public:
	this(bool bDisableDlgOwnerHwnd = false)
	{
		m_hwnd = null;
		m_bDisabledHwnd = false;

		// Need to get dialog owner hwnd prior to enabling modeless false
		auto srpUIManager = queryService!(IVsUIShell);
		if(srpUIManager)
		{
			srpUIManager.GetDialogOwnerHwnd(&m_hwnd);
			srpUIManager.Release();
		}
		if(m_hwnd == null)
		{
			assert(false);
			m_hwnd = GetActiveWindow();
		}
		EnableModeless(false);
		if(bDisableDlgOwnerHwnd && IsWindowEnabled(m_hwnd))
		{
			EnableWindow(m_hwnd, FALSE);
			m_bDisabledHwnd = true;
		}
	}
	~this()
	{
		if(m_bDisabledHwnd)
			EnableWindow(m_hwnd, TRUE);
		EnableModeless(TRUE);
	}

	HWND GetDialogOwnerHwnd()
	{
		return m_hwnd;
	}

protected:
	HRESULT EnableModeless(bool fEnable)
	{
		HRESULT hr = S_OK;
		auto srpUIManager = queryService!(IVsUIShell);
		if(srpUIManager)
		{
			hr = srpUIManager.EnableModeless(fEnable);
			srpUIManager.Release();
		}
		return hr;
	}

	HWND    m_hwnd;          // owner window
	bool    m_bDisabledHwnd; // TRUE if we disabled m_hwnd;
}

int UtilMessageBox(string text, uint nType, string caption)
{
	auto wtext = toUTF16z(text);
	auto wcaption = toUTF16z(caption);
	scope CVsModalState modalstate = new CVsModalState;
	return MessageBoxW(modalstate.GetDialogOwnerHwnd(), wtext, wcaption, nType);
}

//-----------------------------------------------------------------------------
// Returns a cstring array populated with the files from a PROJREF drop. Note that 
// we can't use the systems DragQueryFile() functions because they will NOT work 
// on win9x with unicode strings. Returns the count of files. The format looks like 
// the following: DROPFILES structure with pFiles member containing the offset to 
// the list of files:
//   ----------------------------------------------------------------------------
//  |{DROPFILES structure}|ProjRefItem1|0|ProjRefItem2|0|.......|ProjRefItemN|0|0|
//   ----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
int UtilGetFilesFromPROJITEMDrop(HGLOBAL h, ref string[] rgFiles)
{
	LPVOID pv = .GlobalLock(h);
	if (!pv)
		return 0;

	struct DROPFILES
	{
		DWORD pFiles; // offset of file list
		POINT pt;     // drop point (coordinates depend on fNC)
		BOOL fNC;     // see below
		BOOL fWide;   // TRUE if file contains wide characters, FALSE otherwise
	}

	DROPFILES* pszDropFiles = cast(DROPFILES*)pv;

	// It better be marked unicode
	assert(pszDropFiles.fWide);
	if (pszDropFiles.fWide)
	{
		// The first member of the structure contains the offset to the files
		wchar* wzBuffer = cast(wchar*)(cast(byte*)pszDropFiles + pszDropFiles.pFiles);
		
		// We go until *wzBuffer is null since we don't allow empty strings.
		while(*wzBuffer)
		{
			int len = wcslen(wzBuffer);
			assert(len);
			string file = toUTF8(wzBuffer[0..len]);
			rgFiles ~= file;
			wzBuffer += len + 1;
		}
	}

	.GlobalUnlock(h);

    return rgFiles.length;
}

//----------------------------------------------------------------------------
// Returns TRUE if Shell is in command line (non-interactive) mode
//----------------------------------------------------------------------------
bool UtilShellInCmdLineMode()
{
	scope auto pIVsShell = new ComPtr!(IVsShell)(queryService!(IVsShell));
	if(pIVsShell.ptr)
	{
		VARIANT var;
		if(SUCCEEDED(pIVsShell.ptr.GetProperty(VSSPROPID_IsInCommandLineMode, &var)))
			return var.boolVal != 0;
	}
	return false;
}


//-----------------------------------------------------------------------------
// Displays the last error set in the shell
//-----------------------------------------------------------------------------
void UtilReportErrorInfo(HRESULT hr)
{
	// Filter out bogus hr's where we shouldn't be displaying an error.
	if(hr != OLEERR.E_PROMPTSAVECANCELLED)
	{
		BOOL fInExt = FALSE;
		if(dte.IVsExtensibility ext = queryService!(dte.IVsExtensibility))
		{
			scope(exit) release(ext);
			ext.IsInAutomationFunction(&fInExt);
			if(fInExt || UtilShellInCmdLineMode())
				return;

			scope auto pIVsUIShell = new ComPtr!(IVsUIShell)(queryService!(IVsUIShell));
			if(pIVsUIShell.ptr)
				pIVsUIShell.ptr.ReportErrorInfo(hr);
		}
	}
}

//-----------------------------------------------------------------------------
CHierNode searchNode(CHierNode root, bool delegate(CHierNode) pred, bool fDisplayOnly = true)
{
	if(!root)
		return null;
	if(pred(root))
		return root;

	for(CHierNode node = root.GetHeadEx(fDisplayOnly); node; node = node.GetNext(fDisplayOnly))
		if(CHierNode n = searchNode(node, pred, fDisplayOnly))
			return n;
	return null;
}


