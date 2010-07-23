// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module dpackage;

import windows;
import std.c.stdlib;
import std.windows.charset;
import std.string;
import std.utf;
import std.path;
import std.file;

import comutil;
import hierutil;
import stringutil;
import fileutil;
import dproject;
import config;
import dlangsvc;
import dimagelist;
import logutil;
import propertypage;
import winctrl;
import register;
import intellisense;
import searchsymbol;

import sdk.win32.winreg;

import sdk.vsi.vsshell;
import sdk.vsi.vssplash;
import sdk.vsi.proffserv;
import sdk.vsi.vsshell90;
import sdk.vsi.objext;
import dte = sdk.vsi.dte80a;
import dte2 = sdk.vsi.dte80;

///////////////////////////////////////////////////////////////////////

struct LanguageProperty
{
	wstring name;
	DWORD value;
}

const string plk_version = extractDefine(import("version"), "VERSION_MAJOR") ~ "." ~
                           extractDefine(import("version"), "VERSION_MINOR");
const string full_version = plk_version  ~ "." ~
                           extractDefine(import("version"), "VERSION_REVISION");

/*---------------------------------------------------------
 * Globals
 *---------------------------------------------------------*/
const wstring g_languageName             = "D"w;
const wstring g_packageName              = "Visual D"w;
const  string g_packageVersion           = plk_version;
const wstring g_packageCompany           = "Rainer Schuetze"w;
const wstring g_languageFileExtensions[] = [ ".d"w, ".di"w, ".mixin"w ];
const wstring g_projectFileExtensions    = "visualdproj"w;

// CLSID registered in extensibility center (PLK)
const GUID    g_packageCLSID             = uuid("002a2de9-8bb6-484d-987f-7e4ad4084715");

const GUID    g_languageCLSID            = uuid("002a2de9-8bb6-484d-9800-7e4ad4084715");
const GUID    g_projectFactoryCLSID      = uuid("002a2de9-8bb6-484d-9802-7e4ad4084715");
const GUID    g_intellisenseCLSID        = uuid("002a2de9-8bb6-484d-9801-7e4ad4084715");
const GUID    g_commandSetCLSID          = uuid("002a2de9-8bb6-484d-9803-7e4ad4084715");
const GUID    g_toolWinCLSID             = uuid("002a2de9-8bb6-484d-9804-7e4ad4084715");
const GUID    g_debuggerLanguage         = uuid("002a2de9-8bb6-484d-9805-7e4ad4084715");
const GUID    g_expressionEvaluator      = uuid("002a2de9-8bb6-484d-9806-7e4ad4084715");

GUID g_unmarshalCLSID  = { 1, 1, 0, [ 0x1,0x1,0x1,0x1, 0x1,0x1,0x1,0x1 ] };

const LanguageProperty g_languageProperties[] =
[
  // see http://msdn.microsoft.com/en-us/library/bb166421.aspx
  { "RequestStockColors"w,           1 },
  { "ShowCompletion"w,               1 },
  { "ShowSmartIndent"w,              1 },
  { "ShowHotURLs"w,                  1 },
  { "Default to Non Hot URLs"w,      1 },
  { "DefaultToInsertSpaces"w,        0 },
  { "ShowDropdownBarOption "w,       1 },
  { "Single Code Window Only"w,      1 },
  { "EnableAdvancedMembersOption"w,  1 },
  { "Support CF_HTML"w,              0 },
  { "EnableLineNumbersOption"w,      1 },
  { "HideAdvancedMembersByDefault"w, 0 },
];

mixin(d2_shared ~  " int g_dllRefCount;");

///////////////////////////////////////////////////////////////////////
extern(Windows)
HRESULT DllCanUnloadNow()
{
	return (g_dllRefCount == 0) ? S_OK : S_FALSE;
}

extern(Windows)
HRESULT DllGetClassObject(CLSID* rclsid, IID* riid, LPVOID* ppv)
{
	logCall("DllGetClassObject(rclsid=%s, riid=%s)", _toLog(rclsid), _toLog(riid));

	if(*rclsid == g_packageCLSID)
	{
		auto factory = new ClassFactory;
		return factory.QueryInterface(riid, ppv);
	}
	if(*rclsid == g_unmarshalCLSID)
	{
		DEnumOutFactory eof = new DEnumOutFactory;
		return eof.QueryInterface(riid, ppv);
	}
	if(PropertyPageFactory factory = PropertyPageFactory.create(rclsid))
		return factory.QueryInterface(riid, ppv);

	return E_NOINTERFACE;
}

///////////////////////////////////////////////////////////////////////
class ClassFactory : DComObject, IClassFactory
{
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		logCall("%s.CreateInstance(riid=%s)", this, _toLog(riid));

		if(*riid == g_languageCLSID)
		{
			assert(!UnkOuter);
			LanguageService service = new LanguageService(null);
			return service.QueryInterface(riid, pvObject);
		}
		if(*riid == IVsPackage.iid)
		{
			assert(!UnkOuter);
			Package pkg = new Package;
			return pkg.QueryInterface(riid, pvObject);
		}
		if(*riid == g_unmarshalCLSID)
		{
			assert(!UnkOuter);
			DEnumOutputs eo = new DEnumOutputs(null, 0);
			return eo.QueryInterface(riid, pvObject);
		}
		return S_FALSE;
	}

	override HRESULT LockServer(in BOOL fLock)
	{
		if(fLock)
			InterlockedIncrement(&g_dllRefCount);
		else
			InterlockedDecrement(&g_dllRefCount);
		return S_OK;
	}

	int lockCount;
}

///////////////////////////////////////////////////////////////////////
class Package : DisposingComObject,
		IVsPackage,
		IServiceProvider,
		IVsInstalledProduct,
		IOleCommandTarget
{
	mixin(d2_shared ~ " static Package s_instance;");

	this()
	{
		s_instance = this;
		mLangsvc = addref(new LanguageService(this));
		mProjFactory = addref(new ProjectFactory(this));
		mOptions = new GlobalOptions();
		mLibInfos = new LibraryInfos();
	}

	~this()
	{
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsPackage) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IServiceProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsInstalledProduct) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IOleCommandTarget) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override void Dispose()
	{
		Close();
		mLangsvc = release(mLangsvc);
		mProjFactory = release(mProjFactory);
		if(s_instance == this)
			s_instance = null;
	}

	// IVsPackage
	override int Close()
	{
		mixin(LogCallMix);

		if(mHostSP)
		{
			if(mLangServiceCookie)
			{
				IProfferService sc;
				if(mHostSP.QueryService(&IProfferService.iid, &IProfferService.iid, cast(void**)&sc) == S_OK)
				{
					if(mLangServiceCookie && sc.RevokeService(mLangServiceCookie) != S_OK)
					{
						OutputLog("RevokeService(lang-service) failed");
					}
					sc.Release();
				}
				mLangServiceCookie = 0;
			}
			if(mProjFactoryCookie)
			{
				IVsRegisterProjectTypes projTypes;
				if(mHostSP.QueryService(&IVsRegisterProjectTypes.iid, &IVsRegisterProjectTypes.iid, cast(void**)&projTypes) == S_OK)
				{
					if(projTypes.UnregisterProjectType(mProjFactoryCookie) != S_OK)
					{
						OutputLog("UnregisterProjectType() failed");
					}
					projTypes.Release();
				}
				mProjFactoryCookie = 0;
			}
			mHostSP = release(mHostSP);
		}

		mLangsvc.setDebugger(null);

		return S_OK;
	}

	override int CreateTool(in GUID* rguidPersistenceSlot)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}
	override int GetAutomationObject(in wchar* pszPropName, IDispatch* ppDisp)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	override int GetPropertyPage(in GUID* rguidPage, VSPROPSHEETPAGE* ppage)
	{
		mixin(LogCallMix2);
		if(*rguidPage != g_ToolsPropertyPage)
			return E_NOTIMPL;

		*ppage = VSPROPSHEETPAGE.init;
		ppage.dwSize = VSPROPSHEETPAGE.sizeof;
		auto win = new Window(null, "");
		ppage.hwndDlg = win.hwnd;

		ToolsPropertyPage tpp = new ToolsPropertyPage(mOptions);
		tpp.Activate(win.hwnd, null, false);
		tpp.SetWindowSize(0, 0, 400, 300);
		addref(tpp);

		win.destroyDelegate = delegate (Widget)
		{
			tpp.Deactivate();
			release(tpp);
		};
		win.applyDelegate = delegate (Widget)
		{
			tpp.Apply();
		};
		return S_OK;
	}

	override int QueryClose(int* pfCanClose)
	{
		mixin(LogCallMix2);
		*pfCanClose = 1;
		return S_OK;
	}
	override int ResetDefaults(in uint grfFlags)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}
	override int SetSite(IServiceProvider psp)
	{
		mixin(LogCallMix);
		
		mHostSP = release(mHostSP);
		mHostSP = addref(psp);

		IProfferService sc;
		if(mHostSP.QueryService(&IProfferService.iid, &IProfferService.iid, cast(void**)&sc) == S_OK)
		{
			if(sc.ProfferService(&g_languageCLSID, this, &mLangServiceCookie) != S_OK)
			{
				OutputLog("ProfferService(language-service) failed");
			}
			sc.Release();
		}
		IVsDebugger debugger;
		if(mHostSP.QueryService(&IVsDebugger.iid, &IVsDebugger.iid, cast(void**)&debugger) == S_OK)
		{
			mLangsvc.setDebugger(debugger);
			debugger.Release();
		}
		IVsRegisterProjectTypes projTypes;
		if(mHostSP.QueryService(&IVsRegisterProjectTypes.iid, &IVsRegisterProjectTypes.iid, cast(void**)&projTypes) == S_OK)
		{
			if(projTypes.RegisterProjectType(&g_projectFactoryCLSID, mProjFactory, &mProjFactoryCookie) != S_OK)
			{
				OutputLog("RegisterProjectType() failed");
			}
			projTypes.Release();
		}
		if(mHostSP)
		{
			mOptions.initFromRegistry();
		}
		return S_OK; // E_NOTIMPL;
	}

	// IServiceProvider
	override int QueryService(in GUID* guidService, in IID* riid, void ** ppvObject)
	{
		mixin(LogCallMix);
		
		if(mLangsvc && *guidService == g_languageCLSID)
			return mLangsvc.QueryInterface(riid, ppvObject);
		if(mProjFactory && *guidService == g_projectFactoryCLSID)
			return mProjFactory.QueryInterface(riid, ppvObject);

		return E_NOTIMPL;
	}

	// IVsInstalledProduct
	override int IdBmpSplash(uint* pIdBmp)
	{
		mixin(LogCallMix);
		*pIdBmp = BMP_SPLASHSCRN;
		return S_OK;
	}

	override int OfficialName(BSTR* pbstrName)
	{
		logCall("%s.ProductID(pbstrName=%s)", this, pbstrName);
		*pbstrName = allocwBSTR(g_packageName);
		return S_OK;
	}
	override int ProductID(BSTR* pbstrPID)
	{
		logCall("%s.ProductID(pbstrPID=%s)", this, pbstrPID);
		*pbstrPID = allocBSTR(full_version);
		return S_OK;
	}
	override int ProductDetails(BSTR* pbstrProductDetails)
	{
		logCall("%s.ProductDetails(pbstrPID=%s)", this, pbstrProductDetails);
		*pbstrProductDetails = allocBSTR ("Integration of the D Programming Language into Visual Studio");
		return S_OK;
	}

	override int IdIcoLogoForAboutbox(uint* pIdIco)
	{
		logCall("%s.IdIcoLogoForAboutbox(pIdIco=%s)", this, pIdIco);
		*pIdIco = ICON_ABOUTBOX;
		return S_OK;
	}

	// IOleCommandTarget //////////////////////////////////////
	override int QueryStatus(in GUID *pguidCmdGroup, in uint cCmds,
	                         OLECMD *prgCmds, OLECMDTEXT *pCmdText)
	{
		mixin(LogCallMix);

		for (uint i = 0; i < cCmds; i++) 
		{
			if(g_commandSetCLSID == *pguidCmdGroup)
			{
				switch(prgCmds[i].cmdID)
				{
				case CmdSearchFile:
				case CmdSearchSymbol:
					prgCmds[i].cmdf = OLECMDF_SUPPORTED | OLECMDF_ENABLED;
					break;
				default:
					break;
				}
			}
		}
		return S_OK;
	}

	override int Exec( /* [unique][in] */ in GUID *pguidCmdGroup,
	          /* [in] */ in uint nCmdID,
	          /* [in] */ in uint nCmdexecopt,
	          /* [unique][in] */ in VARIANT *pvaIn,
	          /* [unique][out][in] */ VARIANT *pvaOut)
	{
		if(g_commandSetCLSID != *pguidCmdGroup)
			return OLECMDERR_E_NOTSUPPORTED;
		
		if(nCmdID == CmdSearchSymbol)
		{
			showSearchWindow(false);
			return S_OK;
		}
		if(nCmdID == CmdSearchFile)
		{
			showSearchWindow(true);
			return S_OK;
		}
		return OLECMDERR_E_NOTSUPPORTED;
	}

	/////////////////////////////////////////////////////////////
	IServiceProvider getServiceProvider()
	{
		return mHostSP;
	}

	static GlobalOptions GetGlobalOptions()
	{
		assert(s_instance);
		return s_instance.mOptions;
	}

	static LibraryInfos GetLibInfos()
	{
		assert(s_instance);
		return s_instance.mLibInfos;
	}

private:
	void OutputLog(string msg)
	{
		OutputDebugStringA(toStringz(msg));
	}

	IServiceProvider mHostSP;
	uint             mLangServiceCookie;
	uint             mProjFactoryCookie;
	
	LanguageService  mLangsvc;
	ProjectFactory   mProjFactory;

	GlobalOptions    mOptions;
	LibraryInfos     mLibInfos;
}

class GlobalOptions
{
	HKEY hConfigKey;
	HKEY hUserKey;
	wstring regConfigRoot;
	wstring regUserRoot;

	string DMDInstallDir;
	string ExeSearchPath;
	string ImpSearchPath;
	string LibSearchPath;
	string IncSearchPath;
	string JSNSearchPath;

	// evaluated once at startup
	string WindowsSdkDir;
	string DevEnvDir;
	string VSInstallDir;
	string VisualDInstallDir;

	this()
	{
	}

	bool getRegistryRoot()
	{
		if(hConfigKey)
			return true;
		
		BSTR bstrRoot;
		ILocalRegistry4 registry4 = queryService!(ILocalRegistry, ILocalRegistry4);
		if(registry4)
		{
			scope(exit) release(registry4);
			if(registry4.GetLocalRegistryRootEx(RegType_Configuration, cast(uint*)&hConfigKey, &bstrRoot) == S_OK)
			{
				regConfigRoot = wdetachBSTR(bstrRoot);
				if(registry4.GetLocalRegistryRootEx(RegType_UserSettings, cast(uint*)&hUserKey, &bstrRoot) == S_OK)
					regUserRoot = wdetachBSTR(bstrRoot);
				else
				{
					regUserRoot = regConfigRoot;
					hUserKey = HKEY_CURRENT_USER;
				}
				return true;
			}
		}
		ILocalRegistry2 registry = queryService!(ILocalRegistry, ILocalRegistry2);
		if(registry)
		{
			scope(exit) release(registry);
			if(registry.GetLocalRegistryRoot(&bstrRoot) == S_OK)
			{
				regConfigRoot = wdetachBSTR(bstrRoot);
				hConfigKey = HKEY_LOCAL_MACHINE;
				
				regUserRoot = regConfigRoot;
				hUserKey = HKEY_CURRENT_USER;
				return true;
			}
		}
		return false;
	}

	bool initFromRegistry()
	{
		if(!getRegistryRoot())
			return false;

		bool rc = true;
		try
		{
			// get defaults from global config
			scope RegKey keyToolOpts = new RegKey(hConfigKey, regConfigRoot ~ regPathToolsOptions, false);
			wstring wDMDInstallDir = keyToolOpts.GetString("DMDInstallDir");
			wstring wExeSearchPath = keyToolOpts.GetString("ExeSearchPath");
			wstring wLibSearchPath = keyToolOpts.GetString("LibSearchPath");
			wstring wImpSearchPath = keyToolOpts.GetString("ImpSearchPath");
			wstring wJSNSearchPath = keyToolOpts.GetString("JSNSearchPath");
			wstring wIncSearchPath = keyToolOpts.GetString("IncSearchPath");

			// overwrite by user config
			scope RegKey keyUserOpts = new RegKey(hUserKey, regUserRoot ~ regPathToolsOptions, false);
			DMDInstallDir = toUTF8(keyUserOpts.GetString("DMDInstallDir", wDMDInstallDir));
			ExeSearchPath = toUTF8(keyUserOpts.GetString("ExeSearchPath", wExeSearchPath));
			LibSearchPath = toUTF8(keyUserOpts.GetString("LibSearchPath", wLibSearchPath));
			ImpSearchPath = toUTF8(keyUserOpts.GetString("ImpSearchPath", wImpSearchPath));
			JSNSearchPath = toUTF8(keyUserOpts.GetString("JSNSearchPath", wJSNSearchPath));
			IncSearchPath = toUTF8(keyUserOpts.GetString("IncSearchPath", wIncSearchPath));

			scope RegKey keySdk = new RegKey(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Microsoft SDKs\\Windows"w, false);
			WindowsSdkDir = normalizeDir(toUTF8(keySdk.GetString("CurrentInstallFolder")));

			if(char* pe = getenv("VSINSTALLDIR"))
				VSInstallDir = fromMBSz(cast(immutable)pe);
			else
			{
				scope RegKey keyVS = new RegKey(hConfigKey, regConfigRoot, false);
				VSInstallDir = toUTF8(keyVS.GetString("InstallDir"));
				// InstallDir is ../Common7/IDE/
				VSInstallDir = normalizeDir(VSInstallDir);
				VSInstallDir = getDirName(getDirName(getDirName(VSInstallDir)));
			}
			VSInstallDir = normalizeDir(VSInstallDir);
		}
		catch(Exception e)
		{
			rc = false;
		}

		wstring dllPath = GetDLLName(g_hInst);
		VisualDInstallDir = normalizeDir(getDirName(toUTF8(dllPath)));

		wstring idePath = GetDLLName(null);
		DevEnvDir = normalizeDir(getDirName(toUTF8(idePath)));

		return rc;
	}

	bool saveToRegistry()
	{
		if(!getRegistryRoot())
			return false;

		try
		{
			scope RegKey keyToolOpts = new RegKey(hUserKey, regUserRoot ~ regPathToolsOptions);
			keyToolOpts.Set("DMDInstallDir", toUTF16(DMDInstallDir));
			keyToolOpts.Set("ExeSearchPath", toUTF16(ExeSearchPath));
			keyToolOpts.Set("LibSearchPath", toUTF16(LibSearchPath));
			keyToolOpts.Set("ImpSearchPath", toUTF16(ImpSearchPath));
			keyToolOpts.Set("JSNSearchPath", toUTF16(JSNSearchPath));
			keyToolOpts.Set("IncSearchPath", toUTF16(IncSearchPath));
		}
		catch(Exception e)
		{
			return false;
		}
		return true;
	}

	void addReplacements(ref string[string] replacements)
	{
		replacements["DMDINSTALLDIR"] = normalizeDir(DMDInstallDir);
		replacements["WINDOWSSDKDIR"] = WindowsSdkDir;
		replacements["DEVENVDIR"] = DevEnvDir;
		replacements["VSINSTALLDIR"] = VSInstallDir;
		replacements["VISUALDINSTALLDIR"] = VisualDInstallDir;
	}
	
	string[] getImportPaths()
	{
		string[] imports;
		string bindir = normalizeDir(DMDInstallDir) ~ "windows\\bin";
		string inifile = bindir ~ "\\sc.ini";
		if(std.file.exists(inifile))
		{
			string[string][string] ini = parseIni(inifile);
			if(auto pEnv = "Environment" in ini)
				if(string* pFlags = "DFLAGS" in *pEnv)
				{
					string opts = replace(*pFlags, "%@P%", bindir);
					string[] args = tokenizeArgs(opts);
					foreach(arg; args)
					{
						arg = unquoteArgument(arg);
						if(arg.startsWith("-I"))
							imports ~= normalizeDir(arg[2..$]);
					}
				}
		}
		
		string[string] replacements;
		addReplacements(replacements);
		string searchpaths = replaceMacros(ImpSearchPath, replacements);
		string[] args = tokenizeArgs(searchpaths);
		foreach(arg; args)
			imports ~= normalizeDir(unquoteArgument(arg));
		
		return imports;
	}

	string[] getJSONFiles()
	{
		string[] jsonpaths;
		string[string] replacements;
		addReplacements(replacements);
		string searchpaths = replaceMacros(JSNSearchPath, replacements);
		string[] args = tokenizeArgs(searchpaths);
		foreach(arg; args)
			jsonpaths ~= normalizeDir(unquoteArgument(arg));
		
		string[] jsonfiles;
		foreach(path; jsonpaths)
		{
			foreach (string name; dirEntries(path, SpanMode.shallow))
				if (fnmatch(basename(name), "*.json"))
					addunique(jsonfiles, name);
		}
		return jsonfiles;
	}
}

// not used:
class CommandManager
{
	HRESULT AddCommand(string name)
	{
		dte2.DTE2 spvsDTE = GetDTE();
		if(!spvsDTE)
			return E_FAIL;
		scope(exit) release(spvsDTE);
		
		HRESULT hr = S_OK;

		ComPtr!(dte.Commands) spvsCmds;
		hr = spvsDTE.Commands(&spvsCmds.ptr);
		if (SUCCEEDED(hr))
		{
			// See if the command already exists
			VARIANT svarCmdID;
			svarCmdID.bstrVal = _toUTF16z(name);
			svarCmdID.vt = VT_BSTR;
			ComPtr!(dte.Command) spvsCmd;
			hr = spvsCmds.Item(svarCmdID, -1, &spvsCmd.ptr);
			if (FAILED(hr))
			{
				// Command is not present.  Add it to the pool of commands.
				auto spvsCmds2 = ComPtr!(dte2.Commands2)(spvsCmds.ptr);
				if (spvsCmds2)
				{
/+
                    hr = spvsCmds2->AddNamedCommand2(_spvsAddin, sbstrCmdID, sbstrCmdName, sbstrCmdDescription, VARIANT_FALSE, CComVariant(IDB_FSECMD),
                                                     NULL, vsCommandStatusSupported+vsCommandStatusEnabled, vsCommandStylePictAndText,
                                                     vsCommandControlTypeButton, &spvsCmd);
                    hr = (SUCCEEDED(hr) && spvsCmd) ? S_OK : E_FAIL;
                    //if (SUCCEEDED(hr))
                    //   hr = _AddCommandToViewMenu(spvsCmd);

                    hr = sbstrCmdID.Append(L"ViewFlatSolutionExplorer");
                    if (SUCCEEDED(hr))
                    {
                        CComBSTR sbstrCmdName;
                        hr = sbstrCmdName.LoadString(IDS_COMMANDNAME) ? S_OK : E_OUTOFMEMORY;
                        if (SUCCEEDED(hr))
                        {
                            CComBSTR sbstrCmdDescription;
                            hr = sbstrCmdDescription.LoadString(IDS_COMMANDDESCRIPTION) ? S_OK : E_OUTOFMEMORY;
                            if (SUCCEEDED(hr))
                            {
                                hr = spvsCmds2->AddNamedCommand2(_spvsAddin, sbstrCmdID, sbstrCmdName, sbstrCmdDescription, VARIANT_FALSE, CComVariant(IDB_FSECMD),
                                                                 NULL, vsCommandStatusSupported+vsCommandStatusEnabled, vsCommandStylePictAndText,
                                                                 vsCommandControlTypeButton, &spvsCmd);
                                hr = (SUCCEEDED(hr) && spvsCmd) ? S_OK : E_FAIL;
                                //if (SUCCEEDED(hr))
                                //   hr = _AddCommandToViewMenu(spvsCmd);
                            }
                        }
					}
		+/
				}
			}
		}
		return hr;
	}
}
