// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module propertypage;

import windows;
import std.string;
import std.conv;

//import minwin.all;
//import minwin.mswindows;

import sdk.win32.objbase;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;

import comutil;
import logutil;
import dpackage;
import dproject;
import dllmain;
import config;
import winctrl;
import hierarchy;

abstract class PropertyPage : DisposingComObject, IPropertyPage, IVsPropertyPage, IVsPropertyPage2
{
	const int kPageWidth = 400;
	const int kPageHeight = 200;
	const int kMargin = 4;
	const int kLabelWidth = 100;
	const int kTextHeight = 18;
	const int kLineHeight = 22;
	const int kLineSpacing = 2;

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IPropertyPage) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsPropertyPage) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsPropertyPage2) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void Dispose()
	{
		mSite = release(mSite);

		foreach(obj; mObjects)
			release(obj);
		mObjects.length = 0;
	}

	override int SetPageSite( 
		/* [in] */ IPropertyPageSite pPageSite)
	{
		mixin(LogCallMix);
		mSite = release(mSite);
		mSite = addref(pPageSite);
		return S_OK;
	}

	override int Activate( 
		/* [in] */ in HWND hWndParent,
		/* [in] */ in RECT *pRect,
		/* [in] */ in BOOL bModal)
	{
		mixin(LogCallMix);

		if(mWindow)
			return returnError(E_FAIL);

		RECT r; 
		mWindow = new Window(hWndParent);
		mCanvas = new Window(mWindow);
		DWORD color = GetSysColor(COLOR_BTNFACE);
		mCanvas.setBackground(color);
		mCanvas.setRect(kMargin, kMargin, kPageWidth - 2 * kMargin, kPageHeight - 2 * kMargin);
		
		// avoid closing canvas (but not dialog) if pressing esc in MultiLineEdit controls
		//mCanvas.cancelCloseDelegate ~= delegate bool(Widget c) { return true; };
		
		class DelegateWrapper
		{
			void OnCommand(Widget w, int cmd)
			{
				UpdateDirty(true);
			}
		}

		CreateControls();
		UpdateControls();

		DelegateWrapper delegateWrapper = new DelegateWrapper;
		mCanvas.commandDelegate = &delegateWrapper.OnCommand;
		mEnableUpdateDirty = true;

		return S_OK;
	}

	override int Deactivate()
	{
		mixin(LogCallMix);
		if(mWindow)
		{
			mWindow.Dispose();
			mWindow = null;
			mCanvas = null;
		}

		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override int GetPageInfo( 
		/* [out] */ PROPPAGEINFO *pPageInfo)
	{
//		mixin(LogCallMix);

		if(pPageInfo.cb < PROPPAGEINFO.sizeof)
			return E_INVALIDARG;
		pPageInfo.cb = PROPPAGEINFO.sizeof;
		pPageInfo.pszTitle = string2OLESTR("Title");
		pPageInfo.size = comutil.SIZE(kPageWidth, kPageHeight);
		pPageInfo.pszHelpFile = string2OLESTR("HelpFile");
		pPageInfo.pszDocString = string2OLESTR("DocString");
		pPageInfo.dwHelpContext = 0;

		return S_OK;
	}

	override int SetObjects( 
		/* [in] */ in ULONG cObjects,
		/* [size_is][in] */ IUnknown *ppUnk)
	{
		mixin(LogCallMix);

		foreach(obj; mObjects)
			release(obj);
		mObjects.length = 0;
		for(uint i = 0; i < cObjects; i++)
			mObjects ~= addref(ppUnk[i]);

		if(mWindow)
		{
			mEnableUpdateDirty = false;
			UpdateControls();
			mEnableUpdateDirty = true;
		}

		return S_OK;
	}

	override int Show( 
		/* [in] */ in UINT nCmdShow)
	{
		logCall("%s.Show(nCmdShow=%s)", this, _toLog(nCmdShow));
		if(mWindow)
			mWindow.setVisible(true);
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override int Move( 
		/* [in] */ in RECT *pRect)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Help( 
		/* [in] */ in wchar* pszHelpDir)
	{
		logCall("%s.Help(pszHelpDir=%s)", this, _toLog(pszHelpDir));
		return returnError(E_NOTIMPL);
	}

	override int TranslateAccelerator( 
		/* [in] */ in MSG *pMsg)
	{
		mixin(LogCallMix2);
		if(mSite)
			return mSite.TranslateAccelerator(pMsg);
		return returnError(E_NOTIMPL);
	}

	// IVsPropertyPage
	override int CategoryTitle( 
		/* [in] */ in UINT iLevel,
		/* [retval][out] */ BSTR *pbstrCategory)
	{
		logCall("%s.get_CategoryTitle(iLevel=%s, pbstrCategory=%s)", this, _toLog(iLevel), _toLog(pbstrCategory));
		switch(iLevel)
		{
		case 0:
			if(GetCategoryName().length == 0)
				return S_FALSE;
			*pbstrCategory = allocBSTR(GetCategoryName());
			break;
		case 1:
			return S_FALSE;
			//*pbstrCategory = allocBSTR("CategoryTitle1");
			break;
		}
		return S_OK;
	}

	// IVsPropertyPage2
	override int GetProperty( 
		/* [in] */ in VSPPPID propid,
		/* [out] */ VARIANT *pvar)
	{
		mixin(LogCallMix);
		switch(propid)
		{
		case VSPPPID_PAGENAME:
			pvar.vt = VT_BSTR;
			pvar.bstrVal = allocBSTR(GetPageName());
			return S_OK;
		default:
			break;
		}
		return returnError(DISP_E_MEMBERNOTFOUND);
	}

	override int SetProperty( 
		/* [in] */ in VSPPPID propid,
		/* [in] */ in VARIANT var)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	///////////////////////////////////////
	void UpdateDirty(bool bDirty)
	{
		if(mEnableUpdateDirty && mSite)
			mSite.OnStatusChange(PROPPAGESTATUS_DIRTY | PROPPAGESTATUS_VALIDATE);
	}

	void AddControl(string label, Widget w)
	{
		int x = kLabelWidth;
		CheckBox cb = cast(CheckBox) w;
		//if(cb)
		//	cb.cmd = 1; // enable actionDelegate

		int lines = 1;
		if(MultiLineText mt = cast(MultiLineText) w)
		{
			lines = mLinesPerMultiLine;
		}
		if(label.length)
		{
			Label lab = new Label(mCanvas, label);
			int off = ((kLineHeight - kLineSpacing) - 16) / 2;
			lab.setRect(0, mLines*kLineHeight + off, kLabelWidth, kLineHeight - kLineSpacing); 
		} 
		else if (cb)
		{
			x -= mUnindentCheckBox;
		}
		int h = lines * kLineHeight - kLineSpacing;
		if(cast(Text) w && lines == 1)
		{
			h = kTextHeight;
		}
		int y = mLines*kLineHeight + (lines * kLineHeight - kLineSpacing - h) / 2;
		w.setRect(x, y, kPageWidth - 2*kMargin - kLabelWidth, h); 
		mLines += lines;
	}

	int changeOption(V)(V val, ref V optval, ref V refval)
	{
		if(refval == val)
			return 0;
		optval = val;
		return 1;
	}
	int changeOptionDg(V)(V val, void delegate (V optval) setdg, V refval)
	{
		if(refval == val)
			return 0;
		setdg(val);
		return 1;
	}

	abstract void CreateControls();
	abstract void UpdateControls();
	abstract string GetCategoryName();
	abstract string GetPageName();

	IUnknown[] mObjects;
	IPropertyPageSite mSite;
	Window mWindow;
	Window mCanvas;
	bool mEnableUpdateDirty;
	int mLines;
	int mLinesPerMultiLine = 4;
	int mUnindentCheckBox = 16;
}

///////////////////////////////////////////////////////////////////////////////
class ProjectPropertyPage : PropertyPage
{
	abstract void SetControls(ProjectOptions options);
	abstract int  DoApply(ProjectOptions options, ProjectOptions refoptions);

	override void UpdateControls()
	{
		if(ProjectOptions options = GetProjectOptions())
			SetControls(options);
	}

	ProjectOptions GetProjectOptions()
	{
		if(mObjects.length > 0)
		{
			auto config = ComPtr!(Config)(mObjects[0]);
			if(config)
				return config.GetProjectOptions();
		}
		return null;
	}

	/*override*/ int IsPageDirty()
	{
		mixin(LogCallMix);
		if(mWindow)
			if(ProjectOptions options = GetProjectOptions())
			{
				scope ProjectOptions opt = new ProjectOptions(false);
				return DoApply(opt, options) > 0 ? S_OK : S_FALSE;
			}
		return S_FALSE;
	}

	/*override*/ int Apply()
	{
		mixin(LogCallMix);

		if(ProjectOptions refoptions = GetProjectOptions())
		{
			for(int i = 0; i < mObjects.length; i++)
			{
				auto config = ComPtr!(Config)(mObjects[i]);
				if(config)
				{
					DoApply(config.ptr.GetProjectOptions(), refoptions);
					config.SetDirty();
				}
			}
			return S_OK;
		}
		return returnError(E_FAIL);
	}
}

class NodePropertyPage : PropertyPage
{
	abstract void SetControls(CFileNode node);
	abstract int  DoApply(CFileNode node, CFileNode refnode);

	override void UpdateControls()
	{
		if(CFileNode node = GetNode())
			SetControls(node);
	}

	CFileNode GetNode()
	{
		if(mObjects.length > 0)
		{
			auto node = ComPtr!(CFileNode)(mObjects[0]);
			if(node)
				return node;
		}
		return null;
	}

	/*override*/ int IsPageDirty()
	{
		mixin(LogCallMix);
		if(mWindow)
			if(CFileNode node = GetNode())
			{
				scope CFileNode n = new CFileNode("");
				return DoApply(n, node) > 0 ? S_OK : S_FALSE;
			}
		return S_FALSE;
	}

	/*override*/ int Apply()
	{
		mixin(LogCallMix);

		if(CFileNode refnode = GetNode())
		{
			for(int i = 0; i < mObjects.length; i++)
			{
				auto node = ComPtr!(CFileNode)(mObjects[i]);
				if(node)
				{
					DoApply(node, refnode);
					if(CProjectNode pn = cast(CProjectNode) node.GetRootNode())
						pn.SetProjectFileDirty(true);
				}
			}
			return S_OK;
		}
		return returnError(E_FAIL);
	}
}

class GlobalPropertyPage : PropertyPage
{
	abstract void SetControls(GlobalOptions options);
	abstract int  DoApply(GlobalOptions options, GlobalOptions refoptions);

	this(GlobalOptions options)
	{
		mOptions = options;
	}

	override void UpdateControls()
	{
		if(GlobalOptions options = GetGlobalOptions())
			SetControls(options);
	}

	GlobalOptions GetGlobalOptions()
	{
		return mOptions;
	}

	void SetWindowSize(int x, int y, int w, int h)
	{
		if(mCanvas)
			mCanvas.setRect(x, y, w, h);
	}

	/*override*/ int IsPageDirty()
	{
		mixin(LogCallMix);
		if(mWindow)
			if(GlobalOptions options = GetGlobalOptions())
			{
				scope GlobalOptions opt = new GlobalOptions;
				return DoApply(opt, options) > 0 ? S_OK : S_FALSE;
			}
		return S_FALSE;
	}

	/*override*/ int Apply()
	{
		mixin(LogCallMix);

		if(GlobalOptions options = GetGlobalOptions())
		{
			DoApply(options, options);
			options.saveToRegistry();
			return S_OK;
		}
		return returnError(E_FAIL);
	}

	GlobalOptions mOptions;
}

///////////////////////////////////////////////////////////////////////////////
class CommonPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "General"; }

	override void CreateControls() 
	{
		AddControl("Build System",  mCbBuildSystem = new ComboBox(mCanvas, [ "DMD", "dsss", "rebuild" ], false));
		mCbBuildSystem.setSelection(0);
		mCbBuildSystem.setEnabled(false);
	}
	override void SetControls(ProjectOptions options) 
	{
	}
	override int DoApply(ProjectOptions options, ProjectOptions refoptions) 
	{
		return 0; 
	}

	ComboBox mCbBuildSystem;
}

class GeneralPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "General"; }

	const float[] selectableVersions = [ 1, 2, 2.043 ];
	
	override void CreateControls()
	{
		string[] versions;
		foreach(ver; selectableVersions)
			versions ~= "D" ~ to!(string)(ver);
		
		AddControl("D-Version",     mDVersion = new ComboBox(mCanvas, versions, false));
		AddControl("Output Type",   mCbOutputType = new ComboBox(mCanvas, [ "Executable", "Library" ], false));
		AddControl("Output Path",   mOutputPath = new Text(mCanvas));
		AddControl("Intermediate Path", mIntermediatePath = new Text(mCanvas));
		AddControl("Files to clean", mFilesToClean = new Text(mCanvas));
		AddControl("",              mOtherDMD = new CheckBox(mCanvas, "Use other compiler"));
		AddControl("DMD Path",      mDmdPath = new Text(mCanvas));
	}

	void UpdateDirty(bool bDirty)
	{
		super.UpdateDirty(bDirty);
		EnableControls();
	}
	
	void EnableControls()
	{
		mDmdPath.setEnabled(mOtherDMD.isChecked());
	}

	override void SetControls(ProjectOptions options)
	{
		int ver = 0;
		while(ver < selectableVersions.length - 1 && selectableVersions[ver+1] <= options.Dversion)
			ver++;
		mDVersion.setSelection(ver);
		
		mOtherDMD.setChecked(options.otherDMD);
		mCbOutputType.setSelection(options.lib);
		mDmdPath.setText(options.program);
		mOutputPath.setText(options.outdir);
		mIntermediatePath.setText(options.objdir);
		mFilesToClean.setText(options.filesToClean);
		
		EnableControls();
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		float ver = selectableVersions[mDVersion.getSelection()];
		int changes = 0;
		changes += changeOption(mOtherDMD.isChecked(), options.otherDMD, refoptions.otherDMD);
		changes += changeOption(mCbOutputType.getSelection() != 0, options.lib, refoptions.lib);
		changes += changeOption(mDmdPath.getText(), options.program, refoptions.program);
		changes += changeOption(ver, options.Dversion, refoptions.Dversion);
		changes += changeOption(mOutputPath.getText(), options.outdir, refoptions.outdir);
		changes += changeOption(mIntermediatePath.getText(), options.objdir, refoptions.objdir);
		changes += changeOption(mFilesToClean.getText(), options.filesToClean, refoptions.filesToClean);
		return changes;
	}

	CheckBox mOtherDMD;
	Text mDmdPath;
	ComboBox mCbOutputType;
	ComboBox mDVersion;
	Text mOutputPath;
	Text mIntermediatePath;
	Text mFilesToClean;
}

class DebuggingPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "Debugging"; }

	override void CreateControls()
	{
		AddControl("Command",           mCommand = new Text(mCanvas));
		AddControl("Command Arguments", mArguments = new Text(mCanvas));
		AddControl("Working Directory", mWorkingDir = new Text(mCanvas));
		AddControl("",                  mAttach = new CheckBox(mCanvas, "Attach to runnng process"));
		AddControl("Remote Machine",    mRemote = new Text(mCanvas));
	}

	override void SetControls(ProjectOptions options)
	{
		mCommand.setText(options.debugtarget);
		mArguments.setText(options.debugarguments);
		mWorkingDir.setText(options.debugworkingdir);
		mAttach.setChecked(options.debugattach);
		mRemote.setText(options.debugremote);
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mCommand.getText(), options.debugtarget, refoptions.debugtarget);
		changes += changeOption(mArguments.getText(), options.debugarguments, refoptions.debugarguments);
		changes += changeOption(mWorkingDir.getText(), options.debugworkingdir, refoptions.debugworkingdir);
		changes += changeOption(mAttach.isChecked(), options.debugattach, options.debugattach);
		changes += changeOption(mRemote.getText(), options.debugremote, refoptions.debugremote);
		return changes;
	}

	Text mCommand;
	Text mArguments;
	Text mWorkingDir;
	Text mRemote;
	CheckBox mAttach;
}

class DmdGeneralPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "General"; }

	override void CreateControls()
	{
		AddControl("",                    mUseStandard = new CheckBox(mCanvas, "Use Standard Import Paths"));
		AddControl("Additional Imports",  mAddImports = new Text(mCanvas));
		AddControl("String Imports",      mStringImports = new Text(mCanvas));
		AddControl("Version Identifiers", mVersionIdentifiers = new Text(mCanvas));
		AddControl("Debug Identifiers",   mDebugIdentifiers = new Text(mCanvas));
	}

	override void SetControls(ProjectOptions options)
	{
		mUseStandard.setChecked(true);
		mUseStandard.setEnabled(false);

		mAddImports.setText(options.imppath);
		mStringImports.setText(options.fileImppath);
		mVersionIdentifiers.setText(options.versionids);
		mDebugIdentifiers.setText(options.debugids);
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mAddImports.getText(), options.imppath, refoptions.imppath);
		changes += changeOption(mStringImports.getText(), options.fileImppath, refoptions.fileImppath);
		changes += changeOption(mVersionIdentifiers.getText(), options.versionids, refoptions.versionids);
		changes += changeOption(mDebugIdentifiers.getText(), options.debugids, refoptions.debugids);
		return changes;
	}

	CheckBox mUseStandard;
	Text mAddImports;
	Text mStringImports;
	Text mVersionIdentifiers;
	Text mDebugIdentifiers;
}

class DmdDebugPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "Debug"; }

	override void CreateControls()
	{
		AddControl("Debug Mode", mDebugMode = new ComboBox(mCanvas, [ "Off (release)", "On" ], false));
		AddControl("Debug Info", mDebugInfo = new ComboBox(mCanvas, [ "None", "Symbolic", "Symbolic (pretend to be C)" ], false));
		AddControl("",           mRunCv2pdb = new CheckBox(mCanvas, "Run cv2pdb to Convert Debug Info"));
		AddControl("Path to cv2pdb", mPathCv2pdb = new Text(mCanvas));
	}

	void UpdateDirty(bool bDirty)
	{
		super.UpdateDirty(bDirty);
		EnableControls();
	}
	
	void EnableControls()
	{
		mPathCv2pdb.setEnabled(mRunCv2pdb.isChecked());
	}

	override void SetControls(ProjectOptions options)
	{
		mDebugMode.setSelection(options.release ? 0 : 1);
		mDebugInfo.setSelection(options.symdebug);
		mRunCv2pdb.setChecked(options.runCv2pdb);
		mPathCv2pdb.setText(options.pathCv2pdb);
		
		EnableControls();
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mDebugMode.getSelection() == 0, options.release, refoptions.release);
		changes += changeOption(cast(ubyte) mDebugInfo.getSelection(), options.symdebug, refoptions.symdebug);
		changes += changeOption(mRunCv2pdb.isChecked(), options.runCv2pdb, refoptions.runCv2pdb);
		changes += changeOption(mPathCv2pdb.getText(), options.pathCv2pdb, refoptions.pathCv2pdb);
		return changes;
	}

	ComboBox mDebugMode;
	ComboBox mDebugInfo;
	CheckBox mRunCv2pdb;
	Text mPathCv2pdb;
}

class DmdCodeGenPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "Code Generation"; }

	override void CreateControls()
	{
		mUnindentCheckBox = kLabelWidth;
		AddControl("", mProfiling     = new CheckBox(mCanvas, "Insert Profiling Hooks"));
		AddControl("", mCodeCov       = new CheckBox(mCanvas, "Generate Code Coverage"));
		AddControl("", mOptimizer     = new CheckBox(mCanvas, "Run Optimizer"));
		AddControl("", mNoboundscheck = new CheckBox(mCanvas, "No Array Bounds Checking"));
		AddControl("", mUnitTests     = new CheckBox(mCanvas, "Generate Unittest Code"));
		AddControl("", mInline        = new CheckBox(mCanvas, "Expand Inline Functions"));
		AddControl("", mNoFloat       = new CheckBox(mCanvas, "No Floating Point Support"));
	}

	override void SetControls(ProjectOptions options)
	{
		mProfiling.setChecked(options.trace); 
		mCodeCov.setChecked(options.cov); 
		mOptimizer.setChecked(options.optimize);
		mNoboundscheck.setChecked(options.noboundscheck); 
		mUnitTests.setChecked(options.useUnitTests);
		mInline.setChecked(options.useInline);
		mNoFloat.setChecked(options.nofloat);

		mNoboundscheck.setEnabled(options.Dversion > 1);
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mCodeCov.isChecked(), options.cov, refoptions.cov);
		changes += changeOption(mProfiling.isChecked(), options.trace, refoptions.trace);
		changes += changeOption(mOptimizer.isChecked(), options.optimize, refoptions.optimize);
		changes += changeOption(mNoboundscheck.isChecked(), options.noboundscheck, refoptions.noboundscheck);
		changes += changeOption(mUnitTests.isChecked(), options.useUnitTests, refoptions.useUnitTests);
		changes += changeOption(mInline.isChecked(), options.useInline, refoptions.useInline);
		changes += changeOption(mNoFloat.isChecked(), options.nofloat, refoptions.nofloat);
		return changes;
	}

	CheckBox mCodeCov;
	CheckBox mProfiling;
	CheckBox mOptimizer;
	CheckBox mNoboundscheck;
	CheckBox mUnitTests;
	CheckBox mInline;
	CheckBox mNoFloat;
}

class DmdMessagesPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "Messages"; }

	override void CreateControls()
	{
		mUnindentCheckBox = kLabelWidth;
		AddControl("", mWarnings      = new CheckBox(mCanvas, "Enable Warnings"));
		AddControl("", mInfoWarnings  = new CheckBox(mCanvas, "Enable Informational Warnings (DMD 2.041+)"));
		AddControl("", mQuiet         = new CheckBox(mCanvas, "Suppress Non-Error Messages"));
		AddControl("", mVerbose       = new CheckBox(mCanvas, "Verbose Compile"));
		AddControl("", mVtls          = new CheckBox(mCanvas, "Show TLS Variables"));
		AddControl("", mUseDeprecated = new CheckBox(mCanvas, "Allow Deprecated Features"));
		AddControl("", mIgnorePragmas = new CheckBox(mCanvas, "Ignore Unsupported Pragmas"));
	}

	override void SetControls(ProjectOptions options)
	{
		mWarnings.setChecked(options.warnings);
		mInfoWarnings.setChecked(options.infowarnings);
		mQuiet.setChecked(options.quiet);
		mVerbose.setChecked(options.verbose);
		mVtls.setChecked(options.vtls);
		mUseDeprecated.setChecked(options.useDeprecated);
		mIgnorePragmas.setChecked(options.ignoreUnsupportedPragmas);

		mVtls.setEnabled(options.Dversion > 1);
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mWarnings.isChecked(), options.warnings, refoptions.warnings);
		changes += changeOption(mInfoWarnings.isChecked(), options.infowarnings, refoptions.infowarnings);
		changes += changeOption(mQuiet.isChecked(), options.quiet, refoptions.quiet);
		changes += changeOption(mVerbose.isChecked(), options.verbose, refoptions.verbose);
		changes += changeOption(mVtls.isChecked(), options.vtls, refoptions.vtls);
		changes += changeOption(mUseDeprecated.isChecked(), options.useDeprecated, refoptions.useDeprecated);
		changes += changeOption(mIgnorePragmas.isChecked(), options.ignoreUnsupportedPragmas, refoptions.ignoreUnsupportedPragmas);
		return changes;
	}

	CheckBox mWarnings;
	CheckBox mInfoWarnings;
	CheckBox mQuiet;
	CheckBox mVerbose;
	CheckBox mVtls;
	CheckBox mUseDeprecated;
	CheckBox mIgnorePragmas;
}

class DmdDocPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "Documentation"; }

	override void CreateControls()
	{
		AddControl("", mGenDoc = new CheckBox(mCanvas, "Generate documentation"));
		AddControl("Documentation file", mDocFile = new Text(mCanvas));
		AddControl("Documentation dir", mDocDir = new Text(mCanvas));
		
		AddControl("", mGenHdr = new CheckBox(mCanvas, "Generate interface headers"));
		AddControl("Header file",  mHdrFile = new Text(mCanvas));
		AddControl("Header directory",  mHdrDir = new Text(mCanvas));

		AddControl("", mGenJSON = new CheckBox(mCanvas, "Generate JSON file"));
		AddControl("JSON file",  mJSONFile = new Text(mCanvas));
	}

	void UpdateDirty(bool bDirty)
	{
		super.UpdateDirty(bDirty);
		EnableControls();
	}
	
	void EnableControls()
	{
		mDocDir.setEnabled(mGenDoc.isChecked());
		mDocFile.setEnabled(mGenDoc.isChecked());

		mHdrDir.setEnabled(mGenHdr.isChecked());
		mHdrFile.setEnabled(mGenHdr.isChecked());

		mJSONFile.setEnabled(mGenJSON.isChecked());
	}

	override void SetControls(ProjectOptions options)
	{
		mGenDoc.setChecked(options.doDocComments);
		mDocDir.setText(options.docdir);
		mDocFile.setText(options.docname);
		mGenHdr.setChecked(options.doHdrGeneration);
		mHdrDir.setText(options.hdrdir);
		mHdrFile.setText(options.hdrname);
		mGenJSON.setChecked(options.doXGeneration);
		mJSONFile.setText(options.xfilename);
		
		EnableControls();
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mGenDoc.isChecked(), options.doDocComments, refoptions.doDocComments);
		changes += changeOption(mDocDir.getText(), options.docdir, refoptions.docdir);
		changes += changeOption(mDocFile.getText(), options.docname, refoptions.docname);
		changes += changeOption(mGenHdr.isChecked(), options.doHdrGeneration, refoptions.doHdrGeneration);
		changes += changeOption(mHdrDir.getText(), options.hdrdir, refoptions.hdrdir);
		changes += changeOption(mHdrFile.getText(), options.hdrname, refoptions.hdrname);
		changes += changeOption(mGenJSON.isChecked(), options.doXGeneration, refoptions.doXGeneration);
		changes += changeOption(mJSONFile.getText(), options.xfilename, refoptions.xfilename);
		return changes;
	}

	CheckBox mGenDoc;
	Text mDocDir;
	Text mDocFile;
	CheckBox mGenHdr;
	Text mHdrDir;
	Text mHdrFile;
	CheckBox mGenJSON;
	Text mJSONFile;
}

class DmdOutputPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "DMD"; }
	string GetPageName() { return "Output"; }

	override void CreateControls()
	{
		mUnindentCheckBox = kLabelWidth;
		AddControl("", mMultiObj = new CheckBox(mCanvas, "Multiple Object Files"));
		AddControl("", mPreservePaths = new CheckBox(mCanvas, "Keep Path From Source File"));
	}

	override void SetControls(ProjectOptions options)
	{
		mMultiObj.setChecked(options.multiobj); 
		mPreservePaths.setChecked(options.preservePaths); 
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mMultiObj.isChecked(), options.multiobj, refoptions.multiobj); 
		changes += changeOption(mPreservePaths.isChecked(), options.preservePaths, refoptions.preservePaths); 
		return changes;
	}

	CheckBox mMultiObj;
	CheckBox mPreservePaths;
}

class DmdLinkerPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return "Linker"; }
	string GetPageName() { return "General"; }

	override void CreateControls()
	{
		AddControl("Output File", mExeFile = new Text(mCanvas));
		AddControl("Object Files", mObjFiles = new Text(mCanvas));
		AddControl("Library Files", mLibFiles = new Text(mCanvas));
		AddControl("Library Search Path", mLibPaths = new Text(mCanvas));
		AddControl("Definition File", mDefFile = new Text(mCanvas));
		AddControl("Resource File",   mResFile = new Text(mCanvas));
		AddControl("Generate Map File", mGenMap = new ComboBox(mCanvas, 
			[ "Minimum", "Symbols By Address", "Standard", "Full", "With cross references" ], false));
		AddControl("", mImplib = new CheckBox(mCanvas, "Create import library"));
	}

	override void SetControls(ProjectOptions options)
	{
		mExeFile.setText(options.exefile); 
		mObjFiles.setText(options.objfiles); 
		mLibFiles.setText(options.libfiles);
		mLibPaths.setText(options.libpaths);
		mDefFile.setText(options.deffile); 
		mResFile.setText(options.resfile); 
		mGenMap.setSelection(options.mapverbosity); 
		mImplib.setChecked(options.createImplib); 
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mExeFile.getText(), options.exefile, refoptions.exefile); 
		changes += changeOption(mObjFiles.getText(), options.objfiles, refoptions.objfiles); 
		changes += changeOption(mLibFiles.getText(), options.libfiles, refoptions.libfiles); 
		changes += changeOption(mLibPaths.getText(), options.libpaths, refoptions.libpaths); 
		changes += changeOption(mDefFile.getText(), options.deffile, refoptions.deffile); 
		changes += changeOption(mResFile.getText(), options.resfile, refoptions.resfile); 
		changes += changeOption(cast(uint) mGenMap.getSelection(), options.mapverbosity, refoptions.mapverbosity); 
		changes += changeOption(mImplib.isChecked(), options.createImplib, refoptions.createImplib); 
		return changes;
	}

	Text mExeFile;
	Text mObjFiles;
	Text mLibFiles;
	Text mLibPaths;
	Text mDefFile;
	Text mResFile;
	ComboBox mGenMap;
	CheckBox mImplib;
}

class DmdEventsPropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "Build Events"; }

	override void CreateControls()
	{
		AddControl("Pre-Build Command", mPreCmd = new MultiLineText(mCanvas));
		AddControl("Post-Build Command", mPostCmd = new MultiLineText(mCanvas));

		Label lab = new Label(mCanvas, "Use \"if errorlevel 1 goto reportError\" to cancel on error");
		lab.setRect(0, kPageHeight - kLineHeight, kPageWidth, kLineHeight); 
	}

	override void SetControls(ProjectOptions options)
	{
		mPreCmd.setText(options.preBuildCommand); 
		mPostCmd.setText(options.postBuildCommand); 
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mPreCmd.getText(), options.preBuildCommand, refoptions.preBuildCommand); 
		changes += changeOption(mPostCmd.getText(), options.postBuildCommand, refoptions.postBuildCommand); 
		return changes;
	}

	MultiLineText mPreCmd;
	MultiLineText mPostCmd;
}

class DmdCmdLinePropertyPage : ProjectPropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "Command line"; }

	override void CreateControls()
	{
		AddControl("Command line", mCmdLine = new MultiLineText(mCanvas, "", 0, true));
		AddControl("Additional options", mAddOpt = new MultiLineText(mCanvas));
	}

	override void SetControls(ProjectOptions options)
	{
		mCmdLine.setText(options.buildCommandLine()); 
		mAddOpt.setText(options.additionalOptions); 
	}

	override int DoApply(ProjectOptions options, ProjectOptions refoptions)
	{
		int changes = 0;
		changes += changeOption(mAddOpt.getText(), options.additionalOptions, refoptions.additionalOptions); 
		return changes;
	}

	MultiLineText mCmdLine;
	MultiLineText mAddOpt;
}

class FilePropertyPage : NodePropertyPage
{
	string GetCategoryName() { return ""; }
	string GetPageName() { return "File"; }

	override void CreateControls()
	{
		AddControl("Build Tool", mTool = new ComboBox(mCanvas, [ "Auto", "DMD", kToolResourceCompiler, "Custom", "None" ], false));
		AddControl("Build Command", mCustomCmd = new MultiLineText(mCanvas));
		AddControl("Other Dependencies", mDependencies = new Text(mCanvas));
		AddControl("Output File", mOutFile = new Text(mCanvas));
		AddControl("", mLinkOut = new CheckBox(mCanvas, "Add output to link"));
	}

	void enableControls(string tool)
	{
		bool isCustom = (tool == "Custom");
		bool isRc = (tool == kToolResourceCompiler);
		mCustomCmd.setEnabled(isCustom);
		mDependencies.setEnabled(isCustom || isRc);
		mOutFile.setEnabled(isCustom);
		mLinkOut.setEnabled(isCustom);
	}

	override void SetControls(CFileNode node)
	{
		string tool = node.GetTool();
		if(tool.length == 0)
			mTool.setSelection(0);
		else
			mTool.setSelection(mTool.findString(tool));

		enableControls(tool);
		mCustomCmd.setText(node.GetCustomCmd()); 
		mDependencies.setText(node.GetDependencies()); 
		mOutFile.setText(node.GetOutFile()); 
		mLinkOut.setChecked(node.GetLinkOutput()); 
	}

	override int DoApply(CFileNode node, CFileNode refnode)
	{
		int changes = 0;
		string tool = mTool.getText();
		if(tool == "Auto")
			tool = "";
		changes += changeOptionDg!string(tool, &node.SetTool, refnode.GetTool()); 
		changes += changeOptionDg!string(mCustomCmd.getText(), &node.SetCustomCmd, refnode.GetCustomCmd()); 
		changes += changeOptionDg!string(mDependencies.getText(), &node.SetDependencies, refnode.GetDependencies()); 
		changes += changeOptionDg!string(mOutFile.getText(), &node.SetOutFile, refnode.GetOutFile()); 
		changes += changeOptionDg!bool(mLinkOut.isChecked(), &node.SetLinkOutput, refnode.GetLinkOutput()); 
		enableControls(tool);
		return changes;
	}

	ComboBox mTool;
	MultiLineText mCustomCmd;
	Text mDependencies;
	Text mOutFile;
	CheckBox mLinkOut;
}

///////////////////////////////////////////////////////////////////////////////
class ToolsPropertyPage : GlobalPropertyPage
{
	string GetCategoryName() { return "Projects"; }
	string GetPageName() { return "D Options"; }

	this(GlobalOptions options)
	{
		super(options);
	}

	override void CreateControls()
	{
		mLinesPerMultiLine = 3;
		AddControl("DMD install path", mDmdPath = new Text(mCanvas));
		AddControl("Executable paths", mExePath = new MultiLineText(mCanvas));
		mLinesPerMultiLine = 2;
		AddControl("Import paths",     mImpPath = new MultiLineText(mCanvas));
		AddControl("Library paths",    mLibPath = new MultiLineText(mCanvas));
		AddControl("JSON paths",       mJSNPath = new MultiLineText(mCanvas));
		AddControl("Resource includes", mIncPath = new Text(mCanvas));
	}

	override void SetControls(GlobalOptions opts)
	{
		mDmdPath.setText(opts.DMDInstallDir);
		mExePath.setText(opts.ExeSearchPath);
		mImpPath.setText(opts.ImpSearchPath);
		mLibPath.setText(opts.LibSearchPath);
		mIncPath.setText(opts.IncSearchPath);
		mJSNPath.setText(opts.JSNSearchPath);
	}

	override int DoApply(GlobalOptions opts, GlobalOptions refopts)
	{
		int changes = 0;
		changes += changeOption(mDmdPath.getText(), opts.DMDInstallDir, refopts.DMDInstallDir); 
		changes += changeOption(mExePath.getText(), opts.ExeSearchPath, refopts.ExeSearchPath); 
		changes += changeOption(mImpPath.getText(), opts.ImpSearchPath, refopts.ImpSearchPath); 
		changes += changeOption(mLibPath.getText(), opts.LibSearchPath, refopts.LibSearchPath); 
		changes += changeOption(mIncPath.getText(), opts.IncSearchPath, refopts.IncSearchPath); 
		changes += changeOption(mJSNPath.getText(), opts.JSNSearchPath, refopts.JSNSearchPath); 
		return changes;
	}

	Text mDmdPath;
	Text mIncPath;
	MultiLineText mExePath;
	MultiLineText mImpPath;
	MultiLineText mLibPath;
	MultiLineText mJSNPath;
}

///////////////////////////////////////////////////////////////////////////////
const GUID    g_GeneralPropertyPage      = uuid("002a2de9-8bb6-484d-9810-7e4ad4084715");
const GUID    g_DmdGeneralPropertyPage   = uuid("002a2de9-8bb6-484d-9811-7e4ad4084715");
const GUID    g_DmdDebugPropertyPage     = uuid("002a2de9-8bb6-484d-9812-7e4ad4084715");
const GUID    g_DmdCodeGenPropertyPage   = uuid("002a2de9-8bb6-484d-9813-7e4ad4084715");
const GUID    g_DmdMessagesPropertyPage  = uuid("002a2de9-8bb6-484d-9814-7e4ad4084715");
const GUID    g_DmdOutputPropertyPage    = uuid("002a2de9-8bb6-484d-9815-7e4ad4084715");
const GUID    g_DmdLinkerPropertyPage    = uuid("002a2de9-8bb6-484d-9816-7e4ad4084715");
const GUID    g_DmdEventsPropertyPage    = uuid("002a2de9-8bb6-484d-9817-7e4ad4084715");
const GUID    g_CommonPropertyPage       = uuid("002a2de9-8bb6-484d-9818-7e4ad4084715");
const GUID    g_DebuggingPropertyPage    = uuid("002a2de9-8bb6-484d-9819-7e4ad4084715");
const GUID    g_FilePropertyPage         = uuid("002a2de9-8bb6-484d-981a-7e4ad4084715");
const GUID    g_DmdDocPropertyPage       = uuid("002a2de9-8bb6-484d-981b-7e4ad4084715");
const GUID    g_DmdCmdLinePropertyPage   = uuid("002a2de9-8bb6-484d-981c-7e4ad4084715");

// does not need to be registered, created explicitely by package
const GUID    g_ToolsPropertyPage        = uuid("002a2de9-8bb6-484d-9820-7e4ad4084715");

const GUID* guids_propertyPages[] = 
[ 
	&g_GeneralPropertyPage,
	&g_DmdGeneralPropertyPage,
	&g_DmdDebugPropertyPage,
	&g_DmdCodeGenPropertyPage,
	&g_DmdMessagesPropertyPage,
	&g_DmdOutputPropertyPage,
	&g_DmdLinkerPropertyPage,
	&g_DmdEventsPropertyPage,
	&g_CommonPropertyPage,
	&g_DebuggingPropertyPage,
	&g_FilePropertyPage,
	&g_DmdDocPropertyPage,
	&g_DmdCmdLinePropertyPage,
];

class PropertyPageFactory : DComObject, IClassFactory
{
	static PropertyPageFactory create(CLSID* rclsid)
	{
		foreach(id; guids_propertyPages)
			if(*id == *rclsid)
				return new PropertyPageFactory(rclsid);
		return null;
	}

	this(CLSID* rclsid)
	{
		mClsid = *rclsid;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		PropertyPage ppp;
		assert(!UnkOuter);

		     if(mClsid == g_GeneralPropertyPage)
			ppp = new GeneralPropertyPage();
		else if(mClsid == g_DebuggingPropertyPage)
			ppp = new DebuggingPropertyPage();
		else if(mClsid == g_DmdGeneralPropertyPage)
			ppp = new DmdGeneralPropertyPage();
		else if(mClsid == g_DmdDebugPropertyPage)
			ppp = new DmdDebugPropertyPage();
		else if(mClsid == g_DmdCodeGenPropertyPage)
			ppp = new DmdCodeGenPropertyPage();
		else if(mClsid == g_DmdMessagesPropertyPage)
			ppp = new DmdMessagesPropertyPage();
		else if(mClsid == g_DmdDocPropertyPage)
			ppp = new DmdDocPropertyPage();
		else if(mClsid == g_DmdOutputPropertyPage)
			ppp = new DmdOutputPropertyPage();
		else if(mClsid == g_DmdLinkerPropertyPage)
			ppp = new DmdLinkerPropertyPage();
		else if(mClsid == g_DmdEventsPropertyPage)
			ppp = new DmdEventsPropertyPage();
		else if(mClsid == g_DmdCmdLinePropertyPage)
			ppp = new DmdCmdLinePropertyPage();
		else if(mClsid == g_CommonPropertyPage)
			ppp = new CommonPropertyPage();
		else if(mClsid == g_FilePropertyPage)
			ppp = new FilePropertyPage();
		else
			return E_INVALIDARG;

		return ppp.QueryInterface(riid, pvObject);
	}

	override HRESULT LockServer(in BOOL fLock)
	{
		return S_OK;
	}

	static int GetProjectPages(CAUUID *pPages)
	{
version(all) {
		pPages.cElems = 11;
		pPages.pElems = cast(GUID*)CoTaskMemAlloc(pPages.cElems*GUID.sizeof);
		if (!pPages.pElems)
			return E_OUTOFMEMORY;

		pPages.pElems[0] = g_GeneralPropertyPage;
		pPages.pElems[1] = g_DebuggingPropertyPage;
		pPages.pElems[2] = g_DmdGeneralPropertyPage;
		pPages.pElems[3] = g_DmdDebugPropertyPage;
		pPages.pElems[4] = g_DmdCodeGenPropertyPage;
		pPages.pElems[5] = g_DmdMessagesPropertyPage;
		pPages.pElems[6] = g_DmdDocPropertyPage;
		pPages.pElems[7] = g_DmdOutputPropertyPage;
		pPages.pElems[8] = g_DmdLinkerPropertyPage;
		pPages.pElems[9] = g_DmdCmdLinePropertyPage;
		pPages.pElems[10] = g_DmdEventsPropertyPage;
		return S_OK;
} else {
		return returnError(E_NOTIMPL);
}
	}

	static int GetCommonPages(CAUUID *pPages)
	{
		pPages.cElems = 1;
		pPages.pElems = cast(GUID*)CoTaskMemAlloc(pPages.cElems*GUID.sizeof);
		if (!pPages.pElems)
			return E_OUTOFMEMORY;

		pPages.pElems[0] = g_CommonPropertyPage;
		return S_OK;
	}

	static int GetFilePages(CAUUID *pPages)
	{
		pPages.cElems = 1;
		pPages.pElems = cast(GUID*)CoTaskMemAlloc(pPages.cElems*GUID.sizeof);
		if (!pPages.pElems)
			return E_OUTOFMEMORY;

		pPages.pElems[0] = g_FilePropertyPage;
		return S_OK;
	}

private:
	GUID mClsid;
}

