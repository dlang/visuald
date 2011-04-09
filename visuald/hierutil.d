// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.hierutil;

import visuald.windows;
import std.string;
import std.path;
import std.utf;
import std.stream;
import std.array;

import sdk.port.vsi;
import sdk.vsi.vsshell;
import sdk.vsi.objext;
import dte = sdk.vsi.dte80a;
import dte2 = sdk.vsi.dte80;
import visuald.comutil;
import visuald.fileutil;
import visuald.logutil;
import visuald.stringutil;
import visuald.dpackage;
import visuald.completion;
import visuald.chiernode;
import visuald.chiercontainer;
import visuald.hierarchy;
import visuald.config;

const uint _MAX_PATH = 260;

///////////////////////////////////////////////////////////////////////

T* contains(T)(T[] arr, bool delegate(ref T t) dg)
{
	foreach(ref T t; arr)
		if (dg(t))
			return &t;
	return null;
}

T* contains(T)(T[] arr, T val)
{
	foreach(ref T t; arr)
		if (t == val)
			return &t;
	return null;
}

int arrIndex(T)(in T[] arr, T val)
{
	for(int i = 0; i < arr.length; i++)
		if (arr[i] == val)
			return i;
	return -1;
}

int arrIndexPtr(T)(in T[] arr, T val)
{
	for(int i = 0; i < arr.length; i++)
		if (arr[i] is val)
			return i;
	return -1;
}

void addunique(T)(ref T[] arr, T val)
{
	if (!contains(arr, val))
		arr ~= val;
}

void addunique(T)(ref T[] arr, T[] vals)
{
	foreach(val; vals)
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

wstring UtilGetStringFromHGLOBAL(HGLOBAL h)
{
	LPVOID pv = .GlobalLock(h);
	if (!pv)
		return "";
	wstring ws = to_wstring(cast(wchar*) pv);
	.GlobalUnlock(h);
	return ws;
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

int ShowContextMenu(UINT iCntxtMenuID, in GUID* GroupGuid, IOleCommandTarget pIOleCmdTarg)
{
	auto srpUIManager = queryService!(IVsUIShell);
	if(!srpUIManager)
		return E_FAIL;
	scope(exit) release(srpUIManager);

	POINT  pnt;
	GetCursorPos(&pnt);
	POINTS pnts = { cast(short)pnt.x, cast(short)pnt.y };

	int hr = srpUIManager.ShowContextMenu(0, GroupGuid, iCntxtMenuID, &pnts, pIOleCmdTarg);

	return hr;
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
	IServiceProvider sp = visuald.dpackage.Package.s_instance.getServiceProvider();
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
IVsTextLines GetCurrentTextBuffer(IVsTextView* pview)
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return null;
	scope(exit) release(textmgr);

	IVsTextView view;
	if(textmgr.GetActiveView(false, null, &view) != S_OK)
		return null;
	scope(exit) release(view);
	if(pview)
		*pview = addref(view);
	
	IVsTextLines buffer;
	view.GetBuffer(&buffer);
	return buffer;
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

HRESULT FindFileInSolution(IVsUIShellOpenDocument pIVsUIShellOpenDocument, string filename, string srcfile, 
						   out BSTR bstrAbsPath)
{
	auto wstrPath = _toUTF16z(filename);
	
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
	}
	return hr;
}

HRESULT FindFileInSolution(string filename, string srcfile, out string absPath)
{
	// Get the IVsUIShellOpenDocument service so we can ask it to open a doc window
	IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
	if(!pIVsUIShellOpenDocument)
		return returnError(E_FAIL);
	scope(exit) release(pIVsUIShellOpenDocument);
	
	BSTR bstrAbsPath;
	HRESULT hr = FindFileInSolution(pIVsUIShellOpenDocument, filename, srcfile, bstrAbsPath);
	if(hr != S_OK)
		return returnError(hr);
	absPath = detachBSTR(bstrAbsPath);
	return S_OK;
}

HRESULT OpenFileInSolution(string filename, int line, string srcfile = "")
{
	// Get the IVsUIShellOpenDocument service so we can ask it to open a doc window
	IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
	if(!pIVsUIShellOpenDocument)
		return returnError(E_FAIL);
	scope(exit) release(pIVsUIShellOpenDocument);
	
	BSTR bstrAbsPath;
	HRESULT hr = FindFileInSolution(pIVsUIShellOpenDocument, filename, srcfile, bstrAbsPath);
	if(hr != S_OK)
		return returnError(hr);
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

	if(line < 0)
		return S_OK;
	return NavigateTo(textBuffer, line, 0, line, 0);
}

HRESULT NavigateTo(IVsTextBuffer textBuffer, int line1, int col1, int line2, int col2)
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return returnError(E_FAIL);
	scope(exit) release(textmgr);

	return textmgr.NavigateToLineAndColumn(textBuffer, &LOGVIEWID_Primary, line1, col1, line2, col2);
}

HRESULT OpenFileInSolutionWithScope(string fname, int line, string scop)
{
	HRESULT hr = OpenFileInSolution(fname, line);
	
	if(hr != S_OK && !isabs(fname) && scop.length)
	{
		// guess import path from filename (e.g. "src\core\mem.d") and 
		//  scope (e.g. "core.mem.gc.Proxy") to try opening
		// the file ("core\mem.d")
		string inScope = tolower(scop);
		string path = normalizeDir(getDirName(tolower(fname)));
		inScope = replace(inScope, ".", "\\");
		
		int i;
		for(i = 1; i < path.length; i++)
			if(startsWith(inScope, path[i .. $]))
				break;
		if(i < path.length)
		{
			fname = fname[i .. $];
			hr = OpenFileInSolution(fname, line);
		}
	}
	return hr;
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

///////////////////////////////////////////////////////////////
// returns addref'd Config
Config getProjectConfig(string file)
{
	if(file.length == 0)
		return null;
	
	auto srpSolution = queryService!(IVsSolution);
	scope(exit) release(srpSolution);
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	if(srpSolution && solutionBuildManager)
	{
		scope auto wfile = _toUTF16z(file);
		IEnumHierarchies pEnum;
		if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION|EPF_MATCHTYPE, &g_projectFactoryCLSID, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsHierarchy pHierarchy;
			while(pEnum.Next(1, &pHierarchy, null) == S_OK)
			{
				scope(exit) release(pHierarchy);
				VSITEMID itemid;
				if(pHierarchy.ParseCanonicalName(wfile, &itemid) == S_OK)
				{
					IVsProjectCfg activeCfg;
					if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
					{
						scope(exit) release(activeCfg);
						if(Config cfg = qi_cast!Config(activeCfg))
							return cfg;
					}
				}
			}
		}
	}
	return null;
}

Config getCurrentStartupConfig()
{
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);
	
	if(solutionBuildManager)
	{
		IVsHierarchy pHierarchy;
		if(solutionBuildManager.get_StartupProject(&pHierarchy) == S_OK)
		{
			scope(exit) release(pHierarchy);
			IVsProjectCfg activeCfg;
			if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
			{
				scope(exit) release(activeCfg);
				if(Config cfg = qi_cast!Config(activeCfg))
					return cfg;
			}
		}
	}
	return null;
}

////////////////////////////////////////////////////////////////////////

string[] GetImportPaths(string file)
{
	string[] imports;
	if(Config cfg = getProjectConfig(file))
	{
		scope(exit) release(cfg);
		ProjectOptions opt = cfg.GetProjectOptions();
		string imp = cfg.GetProjectOptions().imppath;
		imp = opt.replaceEnvironment(imp, cfg);
		imports = tokenizeArgs(imp);
		foreach(ref i; imports)
			i = normalizeDir(unquoteArgument(i));
		string projectpath = cfg.GetProjectDir();
		makeFilenamesAbsolute(imports, projectpath);
		addunique(imports, projectpath);
	}
	imports ~= Package.GetGlobalOptions().getImportPaths();
	return imports;
}
