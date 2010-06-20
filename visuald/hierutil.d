// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module hierutil;

import windows;
import std.string;
import std.path;
import std.utf;
import std.stream;

import sdk.port.vsi;
import sdk.vsi.vsshell;
import sdk.vsi.objext;
import dte = sdk.vsi.dte80a;
import dte2 = sdk.vsi.dte80;
import comutil;
import fileutil;
import logutil;
import dpackage;
import completion;
import chiernode;
import chiercontainer;
import hierarchy;

const uint _MAX_PATH = 260;

///////////////////////////////////////////////////////////////////////
version(D_Version2)
{} else
	int indexOf(string s, dchar ch) { return find(s, ch); }

///////////////////////////////////////////////////////////////////////

bool contains(T)(in T[] arr, bool delegate(ref T t) dg)
{
	foreach(ref T t; arr)
		if (dg(t))
			return true;
	return false;
}

bool contains(T)(in T[] arr, T val)
{
	foreach(ref T t; arr)
		if (t == val)
			return true;
	return false;
}

int arrIndex(T)(in T[] arr, T val)
{
	for(int i = 0; i < arr.length; i++)
		if (arr[i] == val)
			return i;
	return -1;
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
	
	string base = getBaseName(fileName);
	if(base.length == 0)
		return false;
	if(ContainsInvalidFileChars(base))
		return false;
	base = getNameWithoutExt(base);
	if(base.length == 0)
		return true; // file starts with '.'

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

struct DROPFILES
{
	DWORD pFiles; // offset of file list
	POINT pt;     // drop point (coordinates depend on fNC)
	BOOL fNC;     // see below
	BOOL fWide;   // TRUE if file contains wide characters, FALSE otherwise
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
	auto pIVsShell = ComPtr!(IVsShell)(queryService!(IVsShell), false);
	if(pIVsShell)
	{
		VARIANT var;
		if(SUCCEEDED(pIVsShell.GetProperty(VSSPROPID_IsInCommandLineMode, &var)))
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
	if(hr != OLE_E_PROMPTSAVECANCELLED)
	{
		BOOL fInExt = FALSE;
		if(dte.IVsExtensibility ext = queryService!(dte.IVsExtensibility))
		{
			scope(exit) release(ext);
			ext.IsInAutomationFunction(&fInExt);
			if(fInExt || UtilShellInCmdLineMode())
				return;

			auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
			if(pIVsUIShell)
				pIVsUIShell.ReportErrorInfo(hr);
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

///////////////////////////////////////////////////////////////////////////////
// VsLocalCreateInstance	
///////////////////////////////////////////////////////////////////////////////
I VsLocalCreateInstance(I)(const GUID* clsid, DWORD dwFlags)
{
	if(ILocalRegistry srpLocalReg = queryService!ILocalRegistry())
	{
		scope(exit) release(srpLocalReg);
		IUnknown punkOuter = null;
		I inst;
		if(FAILED(srpLocalReg.CreateInstance(*clsid, punkOuter, &I.iid, dwFlags, 
		                                     cast(void**) &inst)))
			return null;
		return inst;
	}
	return null;
}
	
///////////////////////////////////////////////////////////////////////////////
dte2.DTE2 GetDTE()
{
	dte._DTE _dte = queryService!(dte._DTE);
	if(!_dte)
		return null;
	scope(exit) release(_dte);
		
	dte2.DTE2 spvsDTE = qi_cast!(dte2.DTE2)(_dte);
	return spvsDTE;
}

////////////////////////////////////////////////////////////////////////
string GetSolutionFilename()
{
	IVsSolution srpSolution = queryService!(IVsSolution);
	if(srpSolution)
	{
		scope(exit) srpSolution.Release();
		
		BSTR pbstrSolutionFile;
		if(srpSolution.GetSolutionInfo(null, &pbstrSolutionFile, null) == S_OK)
			return detachBSTR(pbstrSolutionFile);

	}
	return "";
}

////////////////////////////////////////////////////////////////////////

HRESULT OpenFileInSolution(string filename, int line, string srcfile = "")
{
	// Get the IVsUIShellOpenDocument service so we can ask it to open a doc window
	IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
	if(!pIVsUIShellOpenDocument)
		return returnError(E_FAIL);
	scope(exit) release(pIVsUIShellOpenDocument);
	
	auto wstrPath = _toUTF16z(filename);
	BSTR bstrAbsPath;
	
	HRESULT hr;
	hr = pIVsUIShellOpenDocument.SearchProjectsForRelativePath(RPS_UseAllSearchStrategies, wstrPath, &bstrAbsPath);
	if(hr != S_OK)
	{
		// search import paths
		string[] imps = GetImportPaths(srcfile);
		foreach(imp; imps)
		{
			string file = normalizeDir(imp) ~ filename;
			if(std.file.exists(file))
			{
				bstrAbsPath = allocBSTR(file);
				hr = S_OK;
				break;
			}
		}
		if(hr != S_OK)
			return returnError(hr);
	}
	scope(exit) detachBSTR(bstrAbsPath);
	
	IVsWindowFrame srpIVsWindowFrame;

	hr = pIVsUIShellOpenDocument.OpenDocumentViaProject(bstrAbsPath, &LOGVIEWID_Primary, null, null, null,
	                                                    &srpIVsWindowFrame);
	if(FAILED(hr))
		hr = pIVsUIShellOpenDocument.OpenStandardEditor(
				/* [in]  VSOSEFLAGS   grfOpenStandard           */ OSE_ChooseBestStdEditor,
				/* [in]  LPCOLESTR    pszMkDocument             */ bstrAbsPath,
				/* [in]  REFGUID      rguidLogicalView          */ &LOGVIEWID_Primary,
				/* [in]  LPCOLESTR    pszOwnerCaption           */ _toUTF16z("%3"),
				/* [in]  IVsUIHierarchy  *pHier                 */ null,
				/* [in]  VSITEMID     itemid                    */ 0,
				/* [in]  IUnknown    *punkDocDataExisting       */ DOCDATAEXISTING_UNKNOWN,
				/* [in]  IServiceProvider *pSP                  */ null,
				/* [out, retval] IVsWindowFrame **ppWindowFrame */ &srpIVsWindowFrame);

	if(FAILED(hr) || !srpIVsWindowFrame)
		return returnError(hr);
	scope(exit) release(srpIVsWindowFrame);
	
	srpIVsWindowFrame.Show();
	
	VARIANT var;
	hr = srpIVsWindowFrame.GetProperty(VSFPROPID_DocData, &var);
	if(FAILED(hr) || var.vt != VT_UNKNOWN || !var.punkVal)
		return returnError(E_FAIL);
	scope(exit) release(var.punkVal);

	IVsTextLines textBuffer = qi_cast!IVsTextLines(var.punkVal);
	if(!textBuffer)
		if(auto bufferProvider = qi_cast!IVsTextBufferProvider(var.punkVal))
		{
			bufferProvider.GetTextBuffer(&textBuffer);
			release(bufferProvider);
		}
	if(!textBuffer)
		return returnError(E_FAIL);
	scope(exit) release(textBuffer);

	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return returnError(E_FAIL);
	scope(exit) release(textmgr);

	if(line < 0)
		return S_OK;
	return textmgr.NavigateToLineAndColumn(textBuffer, &LOGVIEWID_Primary, line, 0, line, 0);
}

////////////////////////////////////////////////////////////////////////
string GetFolderPath(CFolderNode folder)
{
	string path;
	while(folder && !cast(CProjectNode) folder)
	{
		path = "\\" ~ folder.GetName() ~ path;
		folder = cast(CFolderNode) folder.GetParent();
	}
	return path;
}
