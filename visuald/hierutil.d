// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.hierutil;

import visuald.windows;
import std.string;
import std.file;
import std.path;
import std.utf;
import std.array;
import std.conv;
import core.stdc.wchar_ : wcslen;

import stdext.path;
import stdext.array;
import stdext.string;

import sdk.port.vsi;
import sdk.vsi.vsshell;
import sdk.vsi.objext;
import sdk.vsi.uilocale;
import dte = sdk.vsi.dte80a;
import dte2 = sdk.vsi.dte80;
import visuald.comutil;
import visuald.fileutil;
import visuald.logutil;
import visuald.stringutil;
import visuald.dpackage;
import visuald.dproject;
import visuald.completion;
import visuald.chiernode;
import visuald.chiercontainer;
import visuald.hierarchy;
import visuald.config;
import visuald.winctrl;
import visuald.vdextensions;

const uint _MAX_PATH = 260;

///////////////////////////////////////////////////////////////////////
int CompareFilenames(string f1, string f2)
{
	return icmp(f1, f2);
/+
	if(f1 == f2)
		return 0;
	if(f1 < f2)
		return -1;
	return 1;
+/
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

	string base = baseName(fileName);
	if(base.length == 0)
		return false;
	if(ContainsInvalidFileChars(base))
		return false;
	base = getNameWithoutExt(base);
	if(base.length == 0)
		return true; // file starts with '.'

	static string[] reservedNames =
	[
		"CON", "PRN", "AUX", "CLOCK$", "NUL",
		"COM1","COM2", "COM3","COM4","COM5", "COM6", "COM7","COM8", "COM9",
		"LPT1","LPT2", "LPT3","LPT4","LPT5", "LPT6", "LPT7","LPT8", "LPT9"
	];

	base = toUpper(base);
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
			//assert(false);
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
	POINTS pnts = POINTS(cast(short)pnt.x, cast(short)pnt.y);

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
@property I queryService(SVC,I)()
{
	if(!visuald.dpackage.Package.s_instance)
		return null;

	IServiceProvider sp = visuald.dpackage.Package.s_instance.getServiceProvider();
	if(!sp)
		return null;

	I svc;
	if(FAILED(sp.QueryService(&SVC.iid, &I.iid, cast(void **)&svc)))
		return null;
	return svc;
}

@property I queryService(I)()
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

int GetDTE(dte.DTE *lppaReturn)
{
	dte._DTE _dte = queryService!(dte._DTE);
	if(!_dte)
		return returnError(E_NOINTERFACE);
	scope(exit) _dte.Release();
	return _dte.get_DTE(lppaReturn);
}


string getStringProperty(dte.Properties props, string propName, string def = null)
{
	VARIANT index;
	dte.Property prop;
	index.vt = VT_BSTR;
	index.bstrVal = allocBSTR(propName);
	HRESULT hr = props.Item(index, &prop);
	detachBSTR(index.bstrVal);
	if(FAILED(hr) || !prop)
		return def;
	scope(exit) release(prop);

	VARIANT var;
	hr = prop.get_Value(&var);
	if(var.vt != VT_BSTR)
		return def;
	if(FAILED(hr))
		return def;
	return detachBSTR(var.bstrVal);
}

int getIntProperty(dte.Properties props, string propName, int def = -1)
{
	VARIANT index;
	dte.Property prop;
	index.vt = VT_BSTR;
	index.bstrVal = allocBSTR(propName);
	HRESULT hr = props.Item(index, &prop);
	detachBSTR(index.bstrVal);
	if(FAILED(hr) || !prop)
		return def;
	scope(exit) release(prop);

	VARIANT var;
	hr = prop.get_Value(&var);
	if(FAILED(hr))
		return def;
	if(var.vt == VT_I2 || var.vt == VT_UI2)
		return var.iVal;
	if(var.vt == VT_INT || var.vt == VT_I4 || var.vt == VT_UI4 || var.vt == VT_UINT)
		return var.intVal;
	return def;
}

string getEnvironmentFont(out int fontSize, out int charSet)
{
	dte._DTE _dte = queryService!(dte._DTE);
	if(!_dte)
		return null;
	scope(exit) release(_dte);

	dte.Properties props;
	BSTR bprop = allocBSTR("FontsAndColors");
	BSTR bpage = allocBSTR("Dialogs and Tool Windows");
	HRESULT hr = _dte.get_Properties(bprop, bpage, &props);
	detachBSTR(bprop);
	detachBSTR(bpage);
	if(FAILED(hr) || !props)
		return null;
	scope(exit) release(props);

	string family = getStringProperty(props, "FontFamily");
	fontSize = getIntProperty(props, "FontSize", 10);
	charSet = getIntProperty(props, "FontCharacterSet", 1);

/+
	IDispatch obj;
	hr = prop.Object(&obj);
	if(FAILED(hr) || !obj)
		return null;
	scope(exit) release(obj);

	dte.FontsAndColorsItems faci = qi_cast!(dte.FontsAndColorsItems)(obj);
	if(!faci)
		return null;
	scope(exit) release(faci);

	dte.ColorableItems ci;
	index.bstrVal = allocBSTR("Plain Text");
	hr = faci.Item(index, &ci);
	detachBSTR(index.bstrVal);
	if(FAILED(hr) || !ci)
		return null;

	BSTR wname;
	ci.Name(&wname);
	string name = detachBSTR(wname);

	dte._FontsAndColors fac = qi_cast!(dte._FontsAndColors)(ci);
	fac = release(fac);

	fac = qi_cast!(dte._FontsAndColors)(faci);
	fac = release(fac);
+/
	return family;
}

void updateEnvironmentFont()
{
	IUIHostLocale locale = queryService!(IUIHostLocale);
	if(locale)
	{
		scope(exit) release(locale);
		if(SUCCEEDED(locale.GetDialogFont(&dialogLogFont)))
			return;
	}

	int size;
	int charset;
	string font = getEnvironmentFont(size, charset);
	if(font.length)
	{
		HDC hDDC = GetDC(GetDesktopWindow());
		int nHeight = -MulDiv(size, GetDeviceCaps(hDDC, LOGPIXELSY), 72);

		dialogLogFont.lfHeight = nHeight;
		dialogLogFont.lfCharSet = cast(ubyte)charset;
		dialogLogFont.lfFaceName[] = to!wstring(font)[];
	}
}

////////////////////////////////////////////////////////////////////////
IVsTextView GetActiveView()
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return null;
	scope(exit) release(textmgr);

	IVsTextView view;
	if(textmgr.GetActiveView(false, null, &view) != S_OK)
		return null;
	return view;
}

////////////////////////////////////////////////////////////////////////
IVsTextLines GetCurrentTextBuffer(IVsTextView* pview)
{
	IVsTextView view = GetActiveView();
	if (!view)
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
	if(hr != S_OK || !bstrAbsPath || !isAbsolute(to_string(bstrAbsPath)))
	{
		// search import paths
		string[] imps = GetImportPaths(srcfile);
		foreach(imp; imps)
		{
			string file = makeFilenameCanonical(filename, imp);
			if(std.file.exists(file))
			{
				detachBSTR(bstrAbsPath);
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

HRESULT OpenFileInSolution(string filename, int line, int col = 0, string srcfile = "", bool adjustLineToChanges = false)
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
	if(adjustLineToChanges)
		if(auto src = Package.GetLanguageService().GetSource(textBuffer))
			line = src.adjustLineNumberSinceLastBuild(line, false);

	return NavigateTo(textBuffer, line, col, line, col);
}

HRESULT NavigateTo(IVsTextBuffer textBuffer, int line1, int col1, int line2, int col2)
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return returnError(E_FAIL);
	scope(exit) release(textmgr);

	return textmgr.NavigateToLineAndColumn(textBuffer, &LOGVIEWID_Primary, line1, col1, line2, col2);
}

HRESULT OpenFileInSolutionWithScope(string fname, int line, int col, string scop, bool adjustLineToChanges = false)
{
	HRESULT hr = OpenFileInSolution(fname, line, col, "", adjustLineToChanges);

	if(hr != S_OK && !isAbsolute(fname) && scop.length)
	{
		// guess import path from filename (e.g. "src\core\mem.d") and
		//  scope (e.g. "core.mem.gc.Proxy") to try opening
		// the file ("core\mem.d")
		string inScope = toLower(scop);
		string path = normalizeDir(dirName(toLower(fname)));
		inScope = replace(inScope, ".", "\\");

		int i;
		for(i = 1; i < path.length; i++)
			if(startsWith(inScope, path[i .. $]))
				break;
		if(i < path.length)
		{
			fname = fname[i .. $];
			hr = OpenFileInSolution(fname, line, col, "", adjustLineToChanges);
		}
	}
	return hr;
}

////////////////////////////////////////////////////////////////////////
string commonProjectFolder(Project proj)
{
	string workdir = normalizeDir(dirName(proj.GetFilename()));
	string path = workdir;
	searchNode(proj.GetRootNode(), delegate (CHierNode n)
	{
		if(CFileNode file = cast(CFileNode) n)
			path = commonParentDir(path, makeFilenameAbsolute(file.GetFilename(), workdir));
		return false;
	});
	return path;
}

////////////////////////////////////////////////////////////////////////
string copyProjectFolder(Project proj, string ncommonpath)
{
	string path = commonProjectFolder(proj);
	if (path.length == 0)
		return null;
	string npath = normalizeDir(ncommonpath);
	string workdir = normalizeDir(dirName(proj.GetFilename()));

	searchNode(proj.GetRootNode(), delegate (CHierNode n)
	{
		if(CFileNode file = cast(CFileNode) n)
		{
			string fname = makeFilenameAbsolute(file.GetFilename(), workdir);
			string nname = npath ~ fname[path.length .. $];
			mkdirRecurse(dirName(nname));
			copy(fname, nname);
		}
		return false;
	});
	return npath;
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
Config getProjectConfig(string file, bool genCmdLine = false)
{
	if(file.length == 0)
		return null;

	auto srpSolution = queryService!(IVsSolution);
	scope(exit) release(srpSolution);
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	if(srpSolution && solutionBuildManager)
	{
		bool isJSON = toLower(extension(file)) == ".json";
		auto wfile = _toUTF16z(file);
		IEnumHierarchies pEnum;
		if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION|EPF_MATCHTYPE, &g_projectFactoryCLSID, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsHierarchy pHierarchy;
			while(pEnum.Next(1, &pHierarchy, null) == S_OK)
			{
				scope(exit) release(pHierarchy);
				IVsProjectCfg activeCfg;
				scope(exit) release(activeCfg);

				if(isJSON)
				{
					if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
					{
						if(Config cfg = qi_cast!Config(activeCfg))
						{
							string[] files;
							if(cfg.addJSONFiles(files))
								foreach(f; files)
									if(CompareFilenames(f, file) == 0)
										return cfg;
							release(cfg);
						}
					}
				}
				else
				{
					VSITEMID itemid;
					if(pHierarchy.ParseCanonicalName(wfile, &itemid) == S_OK)
					{
						if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
						{
							if(Config cfg = qi_cast!Config(activeCfg))
								return cfg;
						}
					}
				}
			}
		}
	}
	return getVisualCppConfig(file, genCmdLine);
}

///////////////////////////////////////////////////////////////
class VCConfig : Config
{
	string mCmdLine;

	this(string projectfile, string projectname, string platform, string config)
	{
		Project prj = newCom!Project(Package.GetProjectFactory(), projectname, projectfile, platform, config);
		super(prj.GetConfigProvider(), config, platform);
	}

	this(IVsHierarchy pHierarchy)
	{
		string projectFile;
		string projectName;
		VARIANT var;
		BSTR name;
		if(pHierarchy.GetCanonicalName(VSITEMID_ROOT, &name) == S_OK)
			projectFile = detachBSTR(name);

		if(pHierarchy.GetProperty(VSITEMID_ROOT, VSHPROPID_EditLabel, &var) == S_OK && var.vt == VT_BSTR)
			projectName = detachBSTR(var.bstrVal);

		Project prj = newCom!Project(Package.GetProjectFactory(), projectName, projectFile, null, null);
		super(prj.GetConfigProvider(), "Debug", "Win32");
	}

	override string GetOutputFile(CFileNode file, string tool = null)
	{
		if (file)
			return super.GetOutputFile(file, tool);
		return null;
	}
	override string GetCompileCommand(CFileNode file, bool syntaxOnly = false, string tool = null, string addopt = null)
	{
		if (file)
			return super.GetCompileCommand(file, syntaxOnly, tool, addopt);
		return addopt && mCmdLine ? mCmdLine ~ " " ~ addopt : mCmdLine ~ addopt;
	}

	override string GetCppCompiler() { return "cl"; }
}

// cache a configuration for each file
struct VCFile
{
	IVsHierarchy pHierarchy;
	VSITEMID itemid;
	bool opEquals(ref const VCFile other) const
	{
		return pHierarchy is other.pHierarchy && itemid == other.itemid;
	}
	hash_t toHash() @trusted nothrow const
	{
		// hash the pointer, not the interface (crashes anyway)
		import core.internal.traits : externDFunc;
		alias hashOf = externDFunc!("rt.util.hash.hashOf",
									size_t function(const(void)*, size_t, size_t) @trusted pure nothrow);
		return hashOf(&this, VCFile.sizeof, 0);
	}
}
__gshared VCConfig[VCFile] vcFileConfigs;

Config getVisualCppConfig(string file, bool genCmdLine = false)
{
	auto srpSolution = queryService!(IVsSolution);
	scope(exit) release(srpSolution);
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	if(srpSolution && solutionBuildManager)
	{
		auto wfile = _toUTF16z(file);
		IEnumHierarchies pEnum;
		const GUID vcxprojCLSID = uuid("8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942");

		if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION|EPF_MATCHTYPE, &vcxprojCLSID, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsHierarchy pHierarchy;
			while(pEnum.Next(1, &pHierarchy, null) == S_OK)
			{
				scope(exit) release(pHierarchy);

				VSITEMID itemid;
				if(pHierarchy.ParseCanonicalName(wfile, &itemid) == S_OK)
				{
					VCConfig cfg;
					if (auto pcfg = VCFile(pHierarchy, itemid) in vcFileConfigs)
						cfg = *pcfg;
					else
					{
						cfg = newCom!VCConfig(pHierarchy);
						cfg.GetProject().GetRootNode().AddTail(newCom!CFileNode(file));
						vcFileConfigs[VCFile(pHierarchy, itemid)] = cfg;
					}

					ProjectOptions opts = cfg.GetProjectOptions();
					ProjectOptions cmpopts = clone(opts);
					if (vdhelper_GetDCompileOptions(pHierarchy, itemid, opts) == S_OK)
					{
						if (genCmdLine)
						{
							string cmd;
							if (vdhelper_GetDCommandLine(pHierarchy, itemid, cmd) == S_OK)
								cfg.mCmdLine = cmd;
						}
						if (opts != cmpopts)
							cfg.SetDirty();
						return addref(cfg);
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

// returns reference counted config
Config GetActiveConfig(IVsHierarchy pHierarchy)
{
	if(!pHierarchy)
		return null;

	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	IVsProjectCfg activeCfg;
	if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
	{
		scope(exit) release(activeCfg);
		if(Config cfg = qi_cast!Config(activeCfg))
			return cfg;
	}
	return null;
}

// return current config and platform of the startup
string GetActiveSolutionConfig(string* platform = null)
{
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	IVsHierarchy pHierarchy;
    if (solutionBuildManager.get_StartupProject(&pHierarchy) != S_OK)
		return null;
	scope(exit) release(pHierarchy);

	IVsProjectCfg activeCfg;
	if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) != S_OK)
		return null;
	scope(exit) release(activeCfg);

	BSTR bstrName;
	if (activeCfg.get_DisplayName(&bstrName) != S_OK)
		return null;

	string config = detachBSTR(bstrName);
	auto parts = split(config, '|');
	if (parts.length == 2)
	{
		if (platform)
			*platform = parts[1];
		config = parts[0];
	}
	return config;
}

////////////////////////////////////////////////////////////////////////

string[] GetImportPaths(Config cfg)
{
	string[] imports;
	if (!cfg)
		return null;

	ProjectOptions opt = cfg.GetProjectOptions();
	string projectpath = cfg.GetProjectDir();

	string imp = opt.imppath;
	imp = opt.replaceEnvironment(imp, cfg);
	imports = tokenizeArgs(imp);

	string addopts = opt.replaceEnvironment(opt.additionalOptions, cfg);
	addunique(imports, GlobalOptions.getOptionImportPaths(addopts, projectpath));

	foreach(ref i; imports)
		i = makeDirnameCanonical(unquoteArgument(i), projectpath);

	addunique(imports, projectpath);
	return imports;
}

string[] GetImportPaths(string file)
{
	string[] imports;
	if(Config cfg = getProjectConfig(file))
	{
		scope(exit) release(cfg);
		imports = GetImportPaths(cfg);
	}
	imports ~= Package.GetGlobalOptions().getImportPaths();
	return imports;
}

////////////////////////////////////////////////////////////////////////

const(wchar)* _toFilter(string filter)
{
	wchar* s = _toUTF16z(filter);
	for(wchar*p = s; *p; p++)
		if(*p == '|')
			*p = 0;
	return s;
}

string getOpenFileDialog(HWND hwnd, string title, string dir, string filter)
{
	string file;
	auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell));
	if(pIVsUIShell)
	{
		wchar[260] filename;
		VSOPENFILENAMEW ofn;
		ofn.lStructSize = ofn.sizeof;
		ofn.hwndOwner = hwnd;
		ofn.pwzDlgTitle = _toUTF16z(title);
		ofn.pwzFileName = filename.ptr;
		ofn.nMaxFileName = 260;
		ofn.pwzInitialDir = _toUTF16z(dir);
		ofn.pwzFilter = _toFilter(filter);

		HRESULT hr = pIVsUIShell.GetOpenFileNameViaDlg(&ofn);
		if(hr != S_OK)
			return "";

		file = to!string(filename);
	}
	return file;
}

string getSaveFileDialog(HWND hwnd, string title, string dir, string filter)
{
	string file;
	auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell));
	if(pIVsUIShell)
	{
		wchar[260] filename;
		VSSAVEFILENAMEW ofn;
		ofn.lStructSize = ofn.sizeof;
		ofn.hwndOwner = hwnd;
		ofn.pwzDlgTitle = _toUTF16z(title);
		ofn.pwzFileName = filename.ptr;
		ofn.nMaxFileName = 260;
		ofn.pwzInitialDir = _toUTF16z(dir);
		ofn.pwzFilter = _toFilter(filter);

		HRESULT hr = pIVsUIShell.GetSaveFileNameViaDlg(&ofn);
		if(hr != S_OK)
			return "";

		file = to!string(filename);
	}
	return file;
}
