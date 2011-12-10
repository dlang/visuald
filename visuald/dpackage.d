// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.dpackage;

import visuald.windows;
import std.c.stdlib;
import std.windows.charset;
import std.string;
import std.utf;
import std.path;
import std.file;
import std.conv;
import std.array;

import stdext.path;
import stdext.array;
import stdext.file;
import stdext.string;

import visuald.comutil;
import visuald.hierutil;
import visuald.stringutil;
import visuald.fileutil;
import visuald.dproject;
import visuald.config;
import visuald.chiernode;
import visuald.dlangsvc;
import visuald.dimagelist;
import visuald.logutil;
import visuald.propertypage;
import visuald.winctrl;
import visuald.register;
import visuald.intellisense;
import visuald.searchsymbol;
import visuald.tokenreplacedialog;
import visuald.cppwizard;
import visuald.profiler;
import visuald.library;
import visuald.pkgutil;
import visuald.colorizer;

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
const GUID    g_searchWinCLSID           = uuid("002a2de9-8bb6-484d-9804-7e4ad4084715");
const GUID    g_debuggerLanguage         = uuid("002a2de9-8bb6-484d-9805-7e4ad4084715");
const GUID    g_expressionEvaluator      = uuid("002a2de9-8bb6-484d-9806-7e4ad4084715");
const GUID    g_profileWinCLSID          = uuid("002a2de9-8bb6-484d-9807-7e4ad4084715");
const GUID    g_tokenReplaceWinCLSID     = uuid("002a2de9-8bb6-484d-9808-7e4ad4084715");
const GUID    g_outputPaneCLSID          = uuid("002a2de9-8bb6-484d-9809-7e4ad4084715");
const GUID    g_CppWizardWinCLSID        = uuid("002a2de9-8bb6-484d-980a-7e4ad4084715");

const GUID    g_omLibraryManagerCLSID    = uuid("002a2de9-8bb6-484d-9810-7e4ad4084715");
const GUID    g_omLibraryCLSID           = uuid("002a2de9-8bb6-484d-9811-7e4ad4084715");

GUID g_unmarshalCLSID  = { 1, 1, 0, [ 0x1,0x1,0x1,0x1, 0x1,0x1,0x1,0x1 ] };

const LanguageProperty g_languageProperties[] =
[
  // see http://msdn.microsoft.com/en-us/library/bb166421.aspx
  { "RequestStockColors"w,           0 },
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

///////////////////////////////////////////////////////////////////////
void global_init()
{
	// avoid cyclic init dependencies
	initWinControls(g_hInst);
	LanguageService.shared_static_this();
	CHierNode.shared_static_this();
	CHierNode.shared_static_this_typeHolder();
	ExtProject.shared_static_this_typeHolder();
	Project.shared_static_this_typeHolder();
}

void global_exit()
{
	LanguageService.shared_static_dtor();
	CHierNode.shared_static_dtor_typeHolder();
	ExtProject.shared_static_dtor_typeHolder();
	Project.shared_static_dtor_typeHolder();
}

///////////////////////////////////////////////////////////////////////
__gshared int g_dllRefCount;

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

static const GUID SOleComponentManager_iid = { 0x000C060B,0x0000,0x0000,[ 0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46 ] }; 
			
///////////////////////////////////////////////////////////////////////
class Package : DisposingComObject,
		IVsPackage,
		IServiceProvider,
		IVsInstalledProduct,
		IOleCommandTarget,
		IOleComponent
{
	__gshared Package s_instance;

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
		if(queryInterface!(IOleComponent) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override void Dispose()
	{
		deleteBuildOutputPane();

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
			CloseLibraryManager();
			
			if(mLangServiceCookie)
			{
				IProfferService sc;
				if(mHostSP.QueryService(&IProfferService.iid, &IProfferService.iid, cast(void**)&sc) == S_OK)
				{
					if(mLangServiceCookie && sc.RevokeService(mLangServiceCookie) != S_OK)
					{
						OutputDebugLog("RevokeService(lang-service) failed");
					}
					sc.Release();
				}
				mLangServiceCookie = 0;
				mLangsvc = release(mLangsvc);
			}
			if(mProjFactoryCookie)
			{
				IVsRegisterProjectTypes projTypes;
				if(mHostSP.QueryService(&IVsRegisterProjectTypes.iid, &IVsRegisterProjectTypes.iid, cast(void**)&projTypes) == S_OK)
				{
					if(projTypes.UnregisterProjectType(mProjFactoryCookie) != S_OK)
					{
						OutputDebugLog("UnregisterProjectType() failed");
					}
					projTypes.Release();
				}
				mProjFactoryCookie = 0;
				mProjFactory = release(mProjFactory);
			}
			if (mComponentID != 0) 
			{
				IOleComponentManager componentManager;
				if(mHostSP.QueryService(&SOleComponentManager_iid, &IOleComponentManager.iid, cast(void**)&componentManager) == S_OK)
				{
					scope(exit) release(componentManager);
					componentManager.FRevokeComponent(mComponentID); 
				}
			}
			mHostSP = release(mHostSP);
		}
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
		if(*rguidPage != g_ToolsPropertyPage && 
		   *rguidPage != g_ToolsProperty2Page && 
		   *rguidPage != g_ColorizerPropertyPage)
			return E_NOTIMPL;

		GlobalPropertyPage tpp;
		if(*rguidPage == g_ToolsPropertyPage)
			tpp = new ToolsPropertyPage(mOptions);
		else if(*rguidPage == g_ToolsProperty2Page)
			tpp = new ToolsProperty2Page(mOptions);
		else
			tpp = new ColorizerPropertyPage(mOptions);
		
		PROPPAGEINFO pageInfo;
		pageInfo.cb = PROPPAGEINFO.sizeof;
		tpp.GetPageInfo(&pageInfo);
		*ppage = VSPROPSHEETPAGE.init;
		ppage.dwSize = VSPROPSHEETPAGE.sizeof;
		auto win = new Window(null, WS_OVERLAPPED, "Visual D Settings");
		win.setRect(0, 0, pageInfo.size.cx, pageInfo.size.cy);
		ppage.hwndDlg = win.hwnd;

		RECT r;
		GetWindowRect(win.hwnd, &r);
		tpp._Activate(win, &r, false);
		tpp.SetWindowSize(0, 0, pageInfo.size.cx, pageInfo.size.cy);
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
				OutputDebugLog("ProfferService(language-service) failed");
			}
			sc.Release();
		}
version(none)
{
	// getting the debugger here causes crashes when installing/uninstalling other plugins
	//  command line used by installer: devenv /setup /NoSetupVSTemplates
		IVsDebugger debugger;
		if(mHostSP.QueryService(&IVsDebugger.iid, &IVsDebugger.iid, cast(void**)&debugger) == S_OK)
		{
			mLangsvc.setDebugger(debugger);
			debugger.Release();
		}
}
		IVsRegisterProjectTypes projTypes;
		if(mHostSP.QueryService(&IVsRegisterProjectTypes.iid, &IVsRegisterProjectTypes.iid, cast(void**)&projTypes) == S_OK)
		{
			if(projTypes.RegisterProjectType(&g_projectFactoryCLSID, mProjFactory, &mProjFactoryCookie) != S_OK)
			{
				OutputDebugLog("RegisterProjectType() failed");
			}
			projTypes.Release();
		}
		
		mOptions.initFromRegistry();

		//register with ComponentManager for Idle processing
		IOleComponentManager componentManager;
		if(mHostSP.QueryService(&SOleComponentManager_iid, &IOleComponentManager.iid, cast(void**)&componentManager) == S_OK)
		{
			scope(exit) release(componentManager);
			if (mComponentID == 0) 
			{
				OLECRINFO crinfo;
				crinfo.cbSize = crinfo.sizeof;
				crinfo.grfcrf = olecrfNeedIdleTime | olecrfNeedPeriodicIdleTime | olecrfNeedAllActiveNotifs | olecrfNeedSpecActiveNotifs;
				crinfo.grfcadvf = olecadvfModal | olecadvfRedrawOff | olecadvfWarningsOff;
				crinfo.uIdleTimeInterval = 1000;
				if(!componentManager.FRegisterComponent(this, &crinfo, &mComponentID))
					OutputDebugLog("FRegisterComponent failed");
			}
		}
		InitLibraryManager();
		
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
				case CmdSearchTokNext:
				case CmdSearchTokPrev:
				case CmdReplaceTokens:
				case CmdConvWizard:
				case CmdBuildPhobos:
				case CmdShowProfile:
				case CmdShowWebsite:
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
		if(nCmdID == CmdSearchTokNext)
		{
			findNextTokenReplace(false);
			return S_OK;
		}
		if(nCmdID == CmdSearchTokPrev)
		{
			findNextTokenReplace(true);
			return S_OK;
		}
		if(nCmdID == CmdReplaceTokens)
		{
			showTokenReplaceWindow(true);
			return S_OK;
		}
		if(nCmdID == CmdConvWizard)
		{
			showCppWizardWindow();
			return S_OK;
		}
		if(nCmdID == CmdBuildPhobos)
		{
			mOptions.buildPhobosBrowseInfo();
			mLibInfos.updateDefinitions();
			return S_OK;
		}
		if(nCmdID == CmdShowProfile)
		{
			showProfilerWindow();
			return S_OK;
		}
		if(nCmdID == CmdShowWebsite)
		{
			if(dte2.DTE2 spvsDTE = GetDTE())
			{
				scope(exit) release(spvsDTE);
				spvsDTE.ExecuteCommand("View.WebBrowser"w.ptr, "http://www.dsource.org/projects/visuald"w.ptr);
			}
			return S_OK;
		}
		return OLECMDERR_E_NOTSUPPORTED;
	}

	// IOleComponent Methods
	BOOL FDoIdle(in OLEIDLEF grfidlef)
	{
		if(mWantsUpdateLibInfos)
		{
			mWantsUpdateLibInfos = false;
			Package.GetLibInfos().updateDefinitions();
		}
		mLangsvc.OnIdle();
		OutputPaneBuffer.flush();
		return false;
	}
	
	void Terminate() 
	{
	}
	BOOL FPreTranslateMessage(MSG* msg)
	{
		return FALSE;
	}
	void OnEnterState(in OLECSTATE uStateID, in BOOL fEnter)
	{
	}
	void OnAppActivate(in BOOL fActive, in DWORD dwOtherThreadID)
	{
	}
	void OnLoseActivation()
	{
	}
	void OnActivationChange(/+[in]+/ IOleComponent pic, 
							in BOOL fSameComponent,
							in const( OLECRINFO)*pcrinfo,
							in BOOL fHostIsActivating,
							in const( OLECHOSTINFO)*pchostinfo, 
							in DWORD dwReserved)
	{
	}
	BOOL FReserved1(in DWORD dwReserved, in UINT message, in WPARAM wParam, in LPARAM lParam)
	{
		return TRUE;
	}
	
	BOOL FContinueMessageLoop(in OLELOOP uReason, in void *pvLoopData, in MSG *pMsgPeeked)
	{
		return 1;
	}
	BOOL FQueryTerminate( in BOOL fPromptUser)
	{
		return 1;
	}
	HWND HwndGetWindow(in OLECWINDOW dwWhich, in DWORD dwReserved)
	{
		return null;
	}
	/////////////////////////////////////////////////////////////
	HRESULT InitLibraryManager()
	{
		if (mOmLibraryCookie != 0) // already init-ed 
			return E_UNEXPECTED;

		HRESULT hr = E_FAIL;
		if(auto om = queryService!(IVsObjectManager, IVsObjectManager2))
		{
			scope(exit) release(om);
			
			auto lib = new Library;
			hr = om.RegisterSimpleLibrary(lib, &mOmLibraryCookie);
			if(SUCCEEDED(hr))
				lib.Initialize();
		}
		return hr;
	}
	
	HRESULT CloseLibraryManager()
	{
		if (mOmLibraryCookie == 0) // already closed or not init-ed
			return S_OK;

		HRESULT hr = E_FAIL;
		if(auto om = queryService!(IVsObjectManager, IVsObjectManager2))
		{
			scope(exit) release(om);
			hr = om.UnregisterLibrary(mOmLibraryCookie);
		}
		mOmLibraryCookie = 0;
		return hr;
	}

	/////////////////////////////////////////////////////////////
	IServiceProvider getServiceProvider()
	{
		return mHostSP;
	}

	static LanguageService GetLanguageService()
	{
		assert(s_instance);
		return s_instance.mLangsvc;
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
	
	static void scheduleUpdateLibrary()
	{
		assert(s_instance);
		s_instance.mWantsUpdateLibInfos = true;
	}

private:
	IServiceProvider mHostSP;
	uint             mLangServiceCookie;
	uint             mProjFactoryCookie;
	
	uint             mComponentID;
	
	LanguageService  mLangsvc;
	ProjectFactory   mProjFactory;
	
	uint             mOmLibraryCookie;

	GlobalOptions    mOptions;
	LibraryInfos     mLibInfos;
	bool             mWantsUpdateLibInfos;
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

	string UserTypesSpec;
	int[wstring] UserTypes;

	// evaluated once at startup
	string WindowsSdkDir;
	string DevEnvDir;
	string VSInstallDir;
	string VisualDInstallDir;

	bool timeBuilds;
	bool sortProjects = true;
	bool demangleError = true;
	bool autoOutlining;
	bool parseSource;
	bool doSemantics;
	bool pasteIndent;
	
	bool ColorizeVersions = true;
	bool lastColorizeVersions;
	
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
			wstring defUserTypesSpec = "Object string wstring dstring ClassInfo\n"
			                           "hash_t ptrdiff_t size_t sizediff_t";
			// get defaults from global config
			scope RegKey keyToolOpts = new RegKey(hConfigKey, regConfigRoot ~ regPathToolsOptions, false);
			wstring wDMDInstallDir = keyToolOpts.GetString("DMDInstallDir");
			wstring wExeSearchPath = keyToolOpts.GetString("ExeSearchPath");
			wstring wLibSearchPath = keyToolOpts.GetString("LibSearchPath");
			wstring wImpSearchPath = keyToolOpts.GetString("ImpSearchPath");
			wstring wJSNSearchPath = keyToolOpts.GetString("JSNSearchPath");
			wstring wIncSearchPath = keyToolOpts.GetString("IncSearchPath");
			wstring wUserTypesSpec = keyToolOpts.GetString("UserTypesSpec", defUserTypesSpec);
			ColorizeVersions = keyToolOpts.GetDWORD("ColorizeVersions", 1) != 0;
			timeBuilds       = keyToolOpts.GetDWORD("timeBuilds", 0) != 0;
			sortProjects     = keyToolOpts.GetDWORD("sortProjects", 1) != 0;
			demangleError    = keyToolOpts.GetDWORD("demangleError", 1) != 0;
			autoOutlining    = keyToolOpts.GetDWORD("autoOutlining", 1) != 0;
			parseSource      = keyToolOpts.GetDWORD("parseSource", 1) != 0;
			doSemantics      = keyToolOpts.GetDWORD("doSemantics", 1) != 0;
			pasteIndent      = keyToolOpts.GetDWORD("pasteIndent", 1) != 0;

			// overwrite by user config
			scope RegKey keyUserOpts = new RegKey(hUserKey, regUserRoot ~ regPathToolsOptions, false);
			DMDInstallDir = toUTF8(keyUserOpts.GetString("DMDInstallDir", wDMDInstallDir));
			ExeSearchPath = toUTF8(keyUserOpts.GetString("ExeSearchPath", wExeSearchPath));
			LibSearchPath = toUTF8(keyUserOpts.GetString("LibSearchPath", wLibSearchPath));
			ImpSearchPath = toUTF8(keyUserOpts.GetString("ImpSearchPath", wImpSearchPath));
			JSNSearchPath = toUTF8(keyUserOpts.GetString("JSNSearchPath", wJSNSearchPath));
			IncSearchPath = toUTF8(keyUserOpts.GetString("IncSearchPath", wIncSearchPath));
			UserTypesSpec = toUTF8(keyUserOpts.GetString("UserTypesSpec", wUserTypesSpec));

			ColorizeVersions     = keyUserOpts.GetDWORD("ColorizeVersions", ColorizeVersions) != 0;
			timeBuilds           = keyUserOpts.GetDWORD("timeBuilds",       timeBuilds) != 0;
			sortProjects         = keyUserOpts.GetDWORD("sortProjects",     sortProjects) != 0;
			demangleError        = keyUserOpts.GetDWORD("demangleError",    demangleError) != 0;
			autoOutlining        = keyUserOpts.GetDWORD("autoOutlining",    autoOutlining) != 0;
			parseSource          = keyUserOpts.GetDWORD("parseSource",      parseSource) != 0;
			doSemantics          = keyUserOpts.GetDWORD("doSemantics",      doSemantics) != 0;
			pasteIndent          = keyUserOpts.GetDWORD("pasteIndent",      pasteIndent) != 0;
			lastColorizeVersions = ColorizeVersions;
			UserTypes = parseUserTypes(UserTypesSpec);

			CHierNode.setContainerIsSorted(sortProjects);
			
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
			writeToBuildOutputPane(e.msg);
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
			keyToolOpts.Set("UserTypesSpec", toUTF16(UserTypesSpec));
			
			keyToolOpts.Set("ColorizeVersions", ColorizeVersions);
			keyToolOpts.Set("timeBuilds", timeBuilds);
			keyToolOpts.Set("sortProjects", sortProjects);
			keyToolOpts.Set("demangleError", demangleError);
			keyToolOpts.Set("autoOutlining", autoOutlining);
			keyToolOpts.Set("parseSource", parseSource);
			keyToolOpts.Set("doSemantics", doSemantics);
			keyToolOpts.Set("pasteIndent", pasteIndent);

			CHierNode.setContainerIsSorted(sortProjects);
		}
		catch(Exception e)
		{
			writeToBuildOutputPane(e.msg);
			return false;
		}
		
		bool updateColorizer = false;
		int[wstring] types = parseUserTypes(UserTypesSpec);
		if(types != UserTypes)
		{
			UserTypes = types;
			updateColorizer = true;
		}
		if(lastColorizeVersions != ColorizeVersions)
		{
			lastColorizeVersions = ColorizeVersions;
			updateColorizer = true;
		}
		if(updateColorizer)
			if(auto svc = Package.s_instance.mLangsvc)
				svc.OnActiveProjectCfgChange(null);

		Package.scheduleUpdateLibrary();
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
	
	string findDmdBinDir()
	{
		string installdir = normalizeDir(DMDInstallDir);
		string bindir = installdir ~ "windows\\bin\\";
		if(std.file.exists(bindir ~ "dmd.exe"))
			return bindir;
		
		string[string] replacements;
		addReplacements(replacements);
		string searchpaths = replaceMacros(ExeSearchPath, replacements);
		string[] paths = tokenizeArgs(searchpaths, true, false);
		if(char* p = getenv("PATH"))
			paths ~= tokenizeArgs(to!string(p), true, false);
		
		foreach(path; paths)
		{
			path = unquoteArgument(path);
			path = normalizeDir(path);
			if(std.file.exists(path ~ "dmd.exe"))
				return path;
		}
		return installdir;
	}
	
	string[] getIniImportPaths()
	{
		string[] imports;
		string bindir = findDmdBinDir();
		string inifile = bindir ~ "sc.ini";
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
							imports ~= removeDotDotPath(normalizeDir(arg[2..$]));
					}
				}
		}
		return imports;
	}
	
	string[] getImportPaths()
	{
		string[] imports = getIniImportPaths();
		
		string[string] replacements;
		addReplacements(replacements);
		string searchpaths = replaceMacros(ImpSearchPath, replacements);
		string[] args = tokenizeArgs(searchpaths);
		foreach(arg; args)
			imports ~= removeDotDotPath(normalizeDir(unquoteArgument(arg)));
		
		return imports;
	}

	string[] getJSONPaths()
	{
		string[] jsonpaths;
		string[string] replacements;
		addReplacements(replacements);
		string searchpaths = replaceMacros(JSNSearchPath, replacements);
		string[] args = tokenizeArgs(searchpaths);
		foreach(arg; args)
			jsonpaths ~= normalizeDir(unquoteArgument(arg));
		return jsonpaths;
	}
	
	string[] getJSONFiles()
	{
		string[] jsonpaths = getJSONPaths();
		
		string[] jsonfiles;
		foreach(path; jsonpaths)
		{
			if(isExistingDir(path))
				foreach (string name; dirEntries(path, SpanMode.shallow))
					if (fnmatch(basename(name), "*.json"))
						addunique(jsonfiles, name);
		}
		return jsonfiles;
	}

	string[] findDFiles(string path, string sub)
	{
		string[] files;
		if(!isExistingDir(path ~ sub))
			return files;
		foreach(string file; dirEntries(path ~ sub, SpanMode.shallow))
		{
			if(_startsWith(file, path))
				file = file[path.length .. $];
			string bname = basename(file);
			if(fnmatch(bname, "openrj.d"))
				continue;
			if(fnmatch(bname, "*.d"))
				if(string* pfile = contains(files, file ~ "i"))
					*pfile = file;
				else
					files ~= file;
			else if(fnmatch(bname, "*.di"))
			{
				// use the d file instead if available
				string dfile = "..\\src\\" ~ file[0..$-1];
				if(std.file.exists(path ~ dfile))
					file = dfile;
				if(!contains(files, file[0..$-1]))
					files ~= file;
			}
		}
		return files;
	}

	bool buildPhobosBrowseInfo()
	{
		IVsOutputWindowPane pane = getBuildOutputPane();
		if(!pane)
			return false;
		scope(exit) release(pane);

		string[] jsonPaths = getJSONPaths();
		string jsonPath;
		if(jsonPaths.length)
			jsonPath = jsonPaths[0];
		if(jsonPath.length == 0)
		{
			JSNSearchPath ~= "\"$(APPDATA)\\VisualD\\json\\\"";
			jsonPath = getJSONPaths()[0];
		}
		
		pane.Clear();
		pane.Activate();
		string msg = "Building phobos JSON browse information files to " ~ jsonPath ~ "\n";
		pane.OutputString(toUTF16z(msg));
		
		if(!std.file.exists(jsonPath))
		{
			try
			{
				mkdirRecurse(jsonPath[0..$-1]); // normalized dir has trailing slash
			}
			catch(Exception)
			{
				msg = format("cannot create directory " ~ jsonPath);
				pane.OutputString(toUTF16z(msg));
				return false;
			}
		}
		
		string[] imports = getIniImportPaths();
		foreach(s; imports)
			pane.OutputString(toUTF16z("Using import " ~ s ~ "\n"));

		string cmdfile = jsonPath ~ "buildjson.bat";
		string dmdpath = findDmdBinDir() ~ "dmd.exe";
		foreach(s; imports)
		{
			string[] files;
			string cmdline = "@echo off\n";
			string jsonfile;
			
			if(std.file.exists(s ~ "std\\algorithm.d")) // D2
			{
				files ~= findDFiles(s, "std");
				files ~= findDFiles(s, "std\\c");
				files ~= findDFiles(s, "std\\c\\windows");
				files ~= findDFiles(s, "std\\internal\\math");
				files ~= findDFiles(s, "std\\windows");
				files ~= findDFiles(s, "etc\\c");
				jsonfile = jsonPath ~ "phobos.json";
			}
			if(std.file.exists(s ~ "std\\gc.d")) // D1
			{
				files ~= findDFiles(s, "std");
				files ~= findDFiles(s, "std\\c");
				files ~= findDFiles(s, "std\\c\\windows");
				files ~= findDFiles(s, "std\\windows");
				jsonfile = jsonPath ~ "phobos1.json";
			}
			if(std.file.exists(s ~ "object.di"))
			{
				files ~= "object.di";
				files ~= findDFiles(s, "core");
				files ~= findDFiles(s, "core\\stdc");
				files ~= findDFiles(s, "core\\sync");
				files ~= findDFiles(s, "core\\sys\\windows");
				files ~= findDFiles(s, "std");
				jsonfile = jsonPath ~ "druntime.json";
			}

			if(files.length)
			{
				string sfiles = std.string.join(files, " ");
				cmdline ~= quoteFilename(dmdpath) ~ " -d -c -Xf" ~ quoteFilename(jsonfile) ~ " -o- " ~ sfiles ~ "\n\n";
				pane.OutputString(toUTF16z("Building " ~ jsonfile ~ " from import " ~ s ~ "\n"));
				if(!launchBuildPhobosBrowseInfo(s, cmdfile, cmdline, pane))
					pane.OutputString(toUTF16z("Building " ~ jsonfile ~ " failed!\n"));
			}
		}
		return true;
	}
	
	bool launchBuildPhobosBrowseInfo(string workdir, string cmdfile, string cmdline, IVsOutputWindowPane pane)
	{
		/////////////
		auto srpIVsLaunchPadFactory = queryService!(IVsLaunchPadFactory);
		if (!srpIVsLaunchPadFactory)
			return false;
		scope(exit) release(srpIVsLaunchPadFactory);

		ComPtr!(IVsLaunchPad) srpIVsLaunchPad;
		HRESULT hr = srpIVsLaunchPadFactory.CreateLaunchPad(&srpIVsLaunchPad.ptr);
		if(FAILED(hr) || !srpIVsLaunchPad.ptr)
		{
			string msg = format("internal error: IVsLaunchPadFactory.CreateLaunchPad failed with rc=%x", hr);
			pane.OutputString(toUTF16z(msg));
			return false;
		}

		try
		{
			std.file.write(cmdfile, cmdline);
		}
		catch(FileException e)
		{
			string msg = format("internal error: cannot write file " ~ cmdfile ~ "\n");
			pane.OutputString(toUTF16z(msg));
			return false;
		}
		scope(exit) std.file.remove(cmdfile);
		
		BSTR bstrOutput;
		DWORD result;
		hr = srpIVsLaunchPad.ExecCommand(
			/* [in] LPCOLESTR pszApplicationName           */ _toUTF16z(getCmdPath()),
			/* [in] LPCOLESTR pszCommandLine               */ _toUTF16z("/Q /C " ~ quoteFilename(cmdfile)),
			/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(workdir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
			/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow,
			/* [in] IVsOutputWindowPane *pOutputWindowPane */ pane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
			/* [in] ULONG nTaskItemCategory                */ 0, // if LPF_PipeStdoutToTaskList is specified
			/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
			/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // "Build"w.ptr, // if LPF_PipeStdoutToTaskList is specified
			/* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ null, //pLaunchPadEvents,
			/* [out] DWORD *pdwProcessExitCode             */ &result,
			/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

		return hr == S_OK && result == 0;
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
