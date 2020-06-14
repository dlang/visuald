// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.dlangsvc;

// import diamond;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.dpackage;
import visuald.dimagelist;
import visuald.expansionprovider;
import visuald.completion;
import visuald.intellisense;
import visuald.searchsymbol;
import visuald.viewfilter;
import visuald.colorizer;
import visuald.windows;
import visuald.simpleparser;
import visuald.config;
import visuald.vdserverclient;
import visuald.vdextensions;

version = VDServer;

//version = DEBUG_GC;
//version = TWEAK_GC;
//import rsgc.gc;
version(TWEAK_GC) {
import rsgc.gcstats;
import core.memory;
extern (C) GCStats gc_stats();
}

import vdc.lexer;
import vdc.ivdserver;
static import vdc.util;

import stdext.array;
import stdext.ddocmacros;
import stdext.string;
import stdext.path;

import std.string;
import std.ascii;
import std.utf;
import std.conv;
import std.path;
import std.algorithm;
import std.array;
import std.datetime;
import std.exception;
import std.range;

import std.parallelism;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.textmgr90;
import sdk.vsi.textmgr120;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.singlefileeditor;
import sdk.vsi.fpstfmt;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;
import sdk.win32.commctrl;

version = threadedOutlining;

///////////////////////////////////////////////////////////////////////////////
__gshared Lexer dLex;
///////////////////////////////////////////////////////////////////////////////

class LanguageService : DisposingComObject,
                        IVsLanguageInfo,
                        IVsLanguageDebugInfo,
                        IVsLanguageDebugInfo2,
                        IVsLanguageDebugInfoRemap,
                        IVsProvideColorableItems,
                        IVsLanguageContextProvider,
                        IServiceProvider,
//                        ISynchronizeInvoke,
                        IVsDebuggerEvents,
                        IVsFormatFilterProvider,
                        IVsOutliningCapableLanguage,
                        IVsUpdateSolutionEvents
{
	static const GUID iid = g_languageCLSID;

	this(Package pkg)
	{
		//mPackage = pkg;
		mUpdateSolutionEvents = newCom!UpdateSolutionEvents(this);
	}

	~this()
	{
	}

	@property VDServerClient vdServerClient()
	{
		if(!mVDServerClient)
		{
			mVDServerClient = new VDServerClient;
			mVDServerClient.start();
		}
		return mVDServerClient;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsLanguageInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProvideColorableItems) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLanguageDebugInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLanguageDebugInfo2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLanguageDebugInfoRemap) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsDebuggerEvents) (this, riid, pvObject))
			return S_OK;
// delegated to mUpdateSolutionEvents
//		if(queryInterface!(IVsUpdateSolutionEvents) (this, riid, pvObject))
//			return S_OK;
//		if(queryInterface!(IVsFormatFilterProvider) (this, riid, pvObject))
//			return S_OK;
		if(queryInterface!(IVsOutliningCapableLanguage) (this, riid, pvObject))
			return S_OK;

		return super.QueryInterface(riid, pvObject);
	}

	void stopAllParsing()
	{
		if(Source.parseTaskPool)
		{
			//Source.parseTaskPool.finish();
			//Source.parseTaskPool.wait();
			Source.parseTaskPool.stop();
		}
	}

	// IDisposable
	override void Dispose()
	{
		stopAllParsing();

		closeSearchWindow();

		setDebugger(null);

		foreach(Source src; mSources)
			src.Release();
		mSources = mSources.init;

		foreach(CodeWindowManager mgr; mCodeWinMgrs)
			mgr.Release();
		mCodeWinMgrs = mCodeWinMgrs.init;

		if(mVDServerClient)
			mVDServerClient.shutDown();

		if(mUpdateSolutionEventsCookie != VSCOOKIE_NIL)
		{
			auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
			if(solutionBuildManager)
			{
				scope(exit) release(solutionBuildManager);
				solutionBuildManager.UnadviseUpdateSolutionEvents(mUpdateSolutionEventsCookie);
				mUpdateSolutionEventsCookie = VSCOOKIE_NIL;
			}
		}

		cdwLastSource = null;
		mLastActiveView = null;
	}

	// IVsLanguageInfo //////////////////////////////////////
	override HRESULT GetCodeWindowManager(IVsCodeWindow pCodeWin, IVsCodeWindowManager* ppCodeWinMgr)
	{
		IVsTextLines buffer;
		if(pCodeWin.GetBuffer(&buffer) == S_OK)
		{
			Source src = GetSource(buffer);
			CodeWindowManager mgr = newCom!CodeWindowManager(this, pCodeWin, src);
			mCodeWinMgrs ~= addref(mgr);
			*ppCodeWinMgr = addref(mgr);
		}
		return S_OK;
	}

	override HRESULT GetColorizer(IVsTextLines pBuffer, IVsColorizer* ppColorizer)
	{
		if(mUpdateSolutionEventsCookie == VSCOOKIE_NIL)
		{
			auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
			if(solutionBuildManager)
			{
				scope(exit) release(solutionBuildManager);
				solutionBuildManager.AdviseUpdateSolutionEvents(mUpdateSolutionEvents, &mUpdateSolutionEventsCookie);
			}
		}

		Source src = GetSource(pBuffer);
		*ppColorizer = addref(src.mColorizer);
		return S_OK;
	}

	override HRESULT GetFileExtensions(BSTR* pbstrExtensions)
	{
		wstring ext = join(g_languageFileExtensions, ";");
		*pbstrExtensions = allocwBSTR(ext);
		return S_OK;
	}

	override HRESULT GetLanguageName(BSTR* bstrName)
	{
		*bstrName = allocwBSTR(g_languageName);
		return S_OK;
	}

	// IVsLanguageDebugInfo //////////////////////////////////////
	override HRESULT GetLanguageID(IVsTextBuffer pBuffer, in int iLine, in int iCol, GUID* pguidLanguageID)
	{
		*pguidLanguageID = g_languageCLSID;
		return S_OK;
	}

	// obsolete
	override HRESULT GetLocationOfName(in LPCOLESTR pszName, BSTR* pbstrMkDoc, TextSpan* pspanLocation)
	{
		mixin(LogCallMix);
		*pbstrMkDoc = null;
		return E_NOTIMPL;
	}

	override HRESULT GetNameOfLocation(IVsTextBuffer pBuffer, in int iLine, in int iCol, BSTR* pbstrName, int* piLineOffset)
	{
		mixin(LogCallMix);

		/*
		string fname;
		if(IPersistFileFormat fileFormat = qi_cast!IPersistFileFormat(pBuffer))
		{
			scope(exit) release(fileFormat);
			uint format;
			LPOLESTR filename;
			if(fileFormat.GetCurFile(&filename, &format) == S_OK)
				fname = detachOLESTR(filename);
		}
		*pbstrName = allocBSTR(fname);
		*/
		*pbstrName = null;
		*piLineOffset = 0;
		return E_FAIL;
	}

	override HRESULT GetProximityExpressions(IVsTextBuffer pBuffer, in int iLine, in int iCol, in int cLines, IVsEnumBSTR* ppEnum)
	{
		auto text = ComPtr!(IVsTextLines)(pBuffer);
		if(!text)
			return E_FAIL;
		Source src = GetSource(text);
		if(!src)
			return E_FAIL;

		*ppEnum = addref(newCom!EnumProximityExpressions(src, iLine, iCol, cLines));
		return S_OK;
	}

	override HRESULT IsMappedLocation(IVsTextBuffer pBuffer, in int iLine, in int iCol)
	{
		mixin(LogCallMix);
		return S_FALSE;
	}

	override HRESULT ResolveName(in LPCOLESTR pszName, in uint dwFlags, IVsEnumDebugName* ppNames)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	override HRESULT ValidateBreakpointLocation(IVsTextBuffer pBuffer, in int iLine, in int iCol, TextSpan* pCodeSpan)
	{
		pCodeSpan.iStartLine = iLine;
		pCodeSpan.iStartIndex = 0;
		pCodeSpan.iEndLine = iLine;
		pCodeSpan.iEndIndex = 0;
		return S_OK;
	}

	// IVsLanguageDebugInfo2 //////////////////////////////////////
	HRESULT QueryCommonLanguageBlock(
	            /+[in]+/  IVsTextBuffer pBuffer, //code buffer containing a break point
	            in  int iLine,                   //line for a break point
	            in  int iCol,                    //column for a break point
	            in  DWORD dwFlag,                //common language block being queried. see LANGUAGECOMMONBLOCK
	            /+[out]+/ BOOL *pfInBlock)       //true if iLine and iCol is inside common language block;otherwise, false;
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	HRESULT ValidateInstructionpointLocation(
	            /+[in]+/  IVsTextBuffer pBuffer, //code buffer containing an instruction point(IP)
	            in  int iLine,             //line for the existing IP
	            in  int iCol,              //column for the existing IP
	            /+[out]+/ TextSpan *pCodeSpan)   //new IP code span
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	HRESULT QueryCatchLineSpan(
	            /+[in]+/  IVsTextBuffer pBuffer,       //code buffer containing a break point
	            in  int iLine,                   //line for a break point
	            in  int iCol,                    //column for a break point
	            /+[out]+/ BOOL *pfIsInCatch,
	            /+[out]+/ TextSpan *ptsCatchLine)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	// IVsLanguageDebugInfoRemap //////////////////////////////////////
	HRESULT RemapBreakpoint(/+[in]+/ IUnknown pUserBreakpointRequest,
	                        /+[out]+/IUnknown* ppMappedBreakpointRequest)
	{
		mixin(LogCallMix);

		/+
		auto bp = ComPtr!(IDebugBreakpointRequest3)(pUserBreakpointRequest);
		if(bp)
		{
			BP_LOCATION_TYPE type;
			HRESULT hr = bp.GetLocationType(&type);
			logCall("type = %x", type);

			BP_REQUEST_INFO info;
			bp.GetRequestInfo(BPREQI_ALLFIELDS, &info);
			if((type & BPLT_LOCATION_TYPE_MASK) == BPLT_FILE_LINE)
			{
				// wrong struct alignment
				if(auto dp2 = (&info.bpLocation.bplocCodeFileLine.pDocPos)[1])
				{
					ScopedBSTR bstrFileName;
					dp2.GetFileName(&bstrFileName.bstr);
					logCall("filename = %s", to_string(bstrFileName));
				}
			}
			BP_REQUEST_INFO2 info2;
			bp.GetRequestInfo2(BPREQI_ALLFIELDS, &info2);

		}
		+/

		return S_FALSE;
	}

	// IVsProvideColorableItems //////////////////////////////////////
	__gshared ColorableItem[] colorableItems;

	__gshared HIMAGELIST completionImageList;

	// delete <VisualStudio-User-Root>\FontAndColors\Cache\{A27B4E24-A735-4D1D-B8E7-9716E1E3D8E0}\Version
	// if the list of colorableItems changes
	static struct DefaultColorData
	{
		string name;
		COLORINDEX foreground;
		COLORINDEX background;
		COLORREF rgbForeground;
		COLORREF darkForeground;
		COLORREF rgbBackground;
	}
	static immutable DefaultColorData[] defaultColors =
	[
		// The first 6 items in this list MUST be these default items.
		DefaultColorData("Keyword",    CI_BLUE,        CI_USERTEXT_BK),
		DefaultColorData("Comment",    CI_DARKGREEN,   CI_USERTEXT_BK),
		DefaultColorData("Identifier", CI_USERTEXT_FG, CI_USERTEXT_BK),
		DefaultColorData("String",     CI_MAROON,      CI_USERTEXT_BK),
		DefaultColorData("Number",     CI_USERTEXT_FG, CI_USERTEXT_BK),
		DefaultColorData("Text",       CI_USERTEXT_FG, CI_USERTEXT_BK),

		// Visual D specific (must match visuald.colorizer.TokenColor)                 Light theme       Dark theme
		DefaultColorData("Visual D Operator",          CI_USERTEXT_FG, CI_USERTEXT_BK),
		DefaultColorData("Visual D Register",             -1,          CI_USERTEXT_BK, RGB(128, 0, 128), RGB(160, 112, 160)),
		DefaultColorData("Visual D Mnemonic",          CI_AQUAMARINE,  CI_USERTEXT_BK, 0,                RGB(0, 192, 192)),
		DefaultColorData("Visual D User Defined Type",    -1,          CI_USERTEXT_BK, RGB(0, 0, 160),   RGB(128, 128, 160)),
		DefaultColorData("Visual D Identifier Interface", -1,          CI_USERTEXT_BK, RGB(32, 192, 160)),
		DefaultColorData("Visual D Identifier Enum",      -1,          CI_USERTEXT_BK, RGB(0, 128, 128), RGB(0, 160, 160)),
		DefaultColorData("Visual D Identifier Enum Value",-1,          CI_USERTEXT_BK, RGB(0, 128, 160), RGB(0, 160, 192)),
		DefaultColorData("Visual D Identifier Template",  -1,          CI_USERTEXT_BK, RGB(0,  96, 128), RGB(64, 160, 192)),
		DefaultColorData("Visual D Identifier Class",     -1,          CI_USERTEXT_BK, RGB(32, 192, 192)),
		DefaultColorData("Visual D Identifier Struct",    -1,          CI_USERTEXT_BK, RGB(0, 192, 128)),
		DefaultColorData("Visual D Identifier Union",     -1,          CI_USERTEXT_BK, RGB(0, 160, 128)),
		DefaultColorData("Visual D Identifier Template Type Parameter", -1, CI_USERTEXT_BK, RGB(64, 0, 160), RGB(96, 128, 192)),

		DefaultColorData("Visual D Identifier Constant",       -1, CI_USERTEXT_BK, RGB(192,   0, 128),   RGB(192,  64, 192)),
		DefaultColorData("Visual D Identifier Local Variable", -1, CI_USERTEXT_BK, RGB(128,  16, 128),   RGB(192,  80, 192)),
		DefaultColorData("Visual D Identifier Parameter",      -1, CI_USERTEXT_BK, RGB(128,  32, 128),   RGB(192,  96, 192)),
		DefaultColorData("Visual D Identifier Thread Local",   -1, CI_USERTEXT_BK, RGB(128,  48, 128),   RGB(192, 128, 192)),
		DefaultColorData("Visual D Identifier Shared Global",  -1, CI_USERTEXT_BK, RGB(128,  64, 128),   RGB(192, 144, 192)),
		DefaultColorData("Visual D Identifier __gshared",      -1, CI_USERTEXT_BK, RGB(128,  80, 128),   RGB(192, 160, 192)),
		DefaultColorData("Visual D Identifier Field",          -1, CI_USERTEXT_BK, RGB(128,  96, 128),   RGB(192, 176, 192)),
		DefaultColorData("Visual D Identifier Variable",       -1, CI_USERTEXT_BK, RGB(128, 128, 128),   RGB(192, 192, 192)),

		DefaultColorData("Visual D Identifier Alias",          -1, CI_USERTEXT_BK, RGB(0, 128, 128)),
		DefaultColorData("Visual D Identifier Module",         -1, CI_USERTEXT_BK, RGB(64, 64, 160),     RGB(128, 192, 208)),
		DefaultColorData("Visual D Identifier Function",       -1, CI_USERTEXT_BK, RGB(128, 96, 160),    RGB(144, 144, 160)),
		DefaultColorData("Visual D Identifier Method",         -1, CI_USERTEXT_BK, RGB(128, 96, 160),    RGB(144, 144, 160)),
		DefaultColorData("Visual D Identifier Basic Type",     -1, CI_USERTEXT_BK, RGB(0, 192, 128)),

		DefaultColorData("Visual D Predefined Version",  -1,          CI_USERTEXT_BK, RGB(160, 0, 0),    RGB(160, 64, 64)),

		DefaultColorData("Visual D Disabled Keyword",    -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
		DefaultColorData("Visual D Disabled Comment",    -1,          CI_USERTEXT_BK, RGB(96, 128, 96)),
		DefaultColorData("Visual D Disabled Identifier", CI_DARKGRAY, CI_USERTEXT_BK),
		DefaultColorData("Visual D Disabled String",     -1,          CI_USERTEXT_BK, RGB(192, 160, 160)),
		DefaultColorData("Visual D Disabled Number",     CI_DARKGRAY, CI_USERTEXT_BK),
		DefaultColorData("Visual D Disabled Text",       CI_DARKGRAY, CI_USERTEXT_BK),
		DefaultColorData("Visual D Disabled Operator",   CI_DARKGRAY, CI_USERTEXT_BK),
		DefaultColorData("Visual D Disabled Register",   -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
		DefaultColorData("Visual D Disabled Mnemonic",   -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
		DefaultColorData("Visual D Disabled Type",       -1,          CI_USERTEXT_BK, RGB(64, 112, 208)),
		DefaultColorData("Visual D Disabled Version",    -1,          CI_USERTEXT_BK, RGB(160, 128, 128)),

		DefaultColorData("Visual D Token String Keyword",    -1,      CI_USERTEXT_BK, RGB(160,32,128),    RGB(160, 128, 128)),
		DefaultColorData("Visual D Token String Comment",    -1,      CI_USERTEXT_BK, RGB(128,160,80)),
		DefaultColorData("Visual D Token String Identifier", -1,      CI_USERTEXT_BK, RGB(128,32,32),     RGB(160, 128, 64)),
		DefaultColorData("Visual D Token String String",     -1,      CI_USERTEXT_BK, RGB(192,64,64),     RGB(192, 128, 64)),
		DefaultColorData("Visual D Token String Number",     -1,      CI_USERTEXT_BK, RGB(128,32,32),     RGB(160, 128, 64)),
		DefaultColorData("Visual D Token String Text",       -1,      CI_USERTEXT_BK, RGB(128,32,32),     RGB(160, 128, 64)),
		DefaultColorData("Visual D Token String Operator",   -1,      CI_USERTEXT_BK, RGB(128,96,32),     RGB(160, 160, 64)),
		DefaultColorData("Visual D Token String Register",   -1,      CI_USERTEXT_BK, RGB(192,0,128),     RGB(160, 64, 128)),
		DefaultColorData("Visual D Token String Mnemonic",   -1,      CI_USERTEXT_BK, RGB(192,0,128),     RGB(160, 64, 128)),
		DefaultColorData("Visual D Token String Type",       -1,      CI_USERTEXT_BK, RGB(112,0,80),      RGB(160, 128, 160)),
		DefaultColorData("Visual D Token String Version",    -1,      CI_USERTEXT_BK, RGB(224, 0, 0),     RGB(160, 64, 64)),

		//                                              Foreground          Background
		DefaultColorData("Visual D Text Coverage",      CI_BLACK, -1, 0, 0, RGB(192, 255, 192)),
		DefaultColorData("Visual D Text Non-Coverage",  CI_BLACK, -1, 0, 0, RGB(255, 192, 192)),
		DefaultColorData("Visual D Margin No Coverage", CI_BLACK, -1, 0, 0, RGB(192, 192, 192)),
	];
	static void shared_static_this()
	{
		colorableItems = new ColorableItem[defaultColors.length];
		foreach(i, def; defaultColors)
			colorableItems[i] = newCom!ColorableItem(def.name, def.foreground, def.background, def.rgbForeground, def.rgbBackground);

		completionImageList = LoadImageList(g_hInst, MAKEINTRESOURCEA(BMP_COMPLETION), 16, 16);
	};
	static void shared_static_dtor()
	{
		foreach(ref def; colorableItems)
		{
			release(def);
			destroy(def); // to keep COM leak detection happy
		}
		Source.parseTaskPool = null;
		if(completionImageList)
		{
			ImageList_Destroy(completionImageList);
			completionImageList = null;
		}
	}

	static void updateThemeColors()
	{
		bool dark = Package.GetGlobalOptions().isDarkTheme();
		foreach(i, ci; colorableItems)
		{
			if (defaultColors[i].darkForeground == 0)
				continue;
			ci.SetDefaultForegroundColor(dark ? defaultColors[i].darkForeground : defaultColors[i].rgbForeground);
		}

		version(none)
		{
			// only resets user colors?
			IVsTextManager2 textmgr = queryService!(VsTextManager, IVsTextManager2);
			if(textmgr)
				textmgr.ResetColorableItems(g_languageCLSID);
			release(textmgr);
		}
	}

	override HRESULT GetColorableItem(in int iIndex, IVsColorableItem* ppItem)
	{
		if(iIndex < 1 || iIndex > colorableItems.length)
			return E_INVALIDARG;

		*ppItem = addref(colorableItems[iIndex-1]);
		return S_OK;
	}

	override HRESULT GetItemCount(int* piCount)
	{
		*piCount = colorableItems.length;
		return S_OK;
	}

	// IVsLanguageContextProvider //////////////////////////////////////
	override HRESULT UpdateLanguageContext(uint dwHint, IVsTextLines pBuffer, TextSpan* ptsSelection, IVsUserContext pUC)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	// IServiceProvider //////////////////////////////////////
	override HRESULT QueryService(in GUID* guidService, in IID* riid, void ** ppvObject)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	// IVsDebuggerEvents //////////////////////////////////////
	override HRESULT OnModeChange(in DBGMODE dbgmodeNew)
	{
		mixin(LogCallMix2);
		mDbgMode = dbgmodeNew;
		return S_OK;
	}

	// IVsFormatFilterProvider //////////////////////////////////////
	override HRESULT CurFileExtensionFormat(in BSTR bstrFileName, uint* pdwExtnIndex)
	{
		mixin(LogCallMix2);
		string filename = to_string(bstrFileName);
		string ext = toLower(extension(filename));
		if (ext == ".d")
			*pdwExtnIndex = 0;
		else if (ext == ".di")
			*pdwExtnIndex = 1;
		else
			return E_FAIL;
		return S_OK;
	}

	override HRESULT GetFormatFilterList(BSTR* pbstrFilterList)
	{
		mixin(LogCallMix);
		*pbstrFilterList = allocBSTR("D Source Files (*.d)\n*.d\nD Interface Files (*.di)\n*.di\n");
		return S_OK;
	}

	override HRESULT QueryInvalidEncoding(in uint Format, BSTR* pbstrMessage)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

	// IVsUpdateSolutionEvents ///////////////////////////////////
	HRESULT UpdateSolution_Begin(/+[in,   out]+/ BOOL *pfCancelUpdate)
	{
		if(pfCancelUpdate)
			*pfCancelUpdate = false;
		return S_OK;
	}

	HRESULT UpdateSolution_Done(in BOOL   fSucceeded, in BOOL fModified, in BOOL fCancelCommand)
	{
		return S_OK;
	}

	HRESULT UpdateSolution_StartUpdate( /+[in, out]+/   BOOL *pfCancelUpdate )
	{
		if(pfCancelUpdate)
			*pfCancelUpdate = false;
		return S_OK;
	}

	HRESULT UpdateSolution_Cancel()
	{
		return S_OK;
	}

	HRESULT OnActiveProjectCfgChange(/+[in]+/   IVsHierarchy pIVsHierarchy)
	{
		UpdateColorizer(false);
		return S_OK;
	}

	void UpdateColorizer(bool force)
	{
		bool showErrors = Package.GetGlobalOptions().showParseErrors;
		foreach(src; mSources)
		{
			src.mColorizer.OnConfigModified(force);
			if (!showErrors && src.mParseErrors.length)
				src.updateParseErrors(null);
		}
	}

	void RestartParser()
	{
		foreach(src; mSources)
			src.mModificationCount++;
	}

	// IVsOutliningCapableLanguage ///////////////////////////////
	HRESULT CollapseToDefinitions(/+[in]+/ IVsTextLines pTextLines,  // the buffer in question
								  /+[in]+/ IVsOutliningSession pSession)
	{
		auto src = GetSource(pTextLines);
		src.mOutlining = true;
		if(auto session = qi_cast!IVsHiddenTextSession(pSession))
		{
			scope(exit) release(session);
			src.UpdateOutlining(session, hrsDefault);
			src.CollapseAllHiddenRegions(session, true);
		}
		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	private Source cdwLastSource;
	private int cdwLastLine, cdwLastColumn;
	public ViewFilter mLastActiveView;
	private SysTime mTimeOutSamePos;

	bool tryJumpToDefinitionInCodeWindow(Source src, int line, int col)
	{
		SysTime now = Clock.currTime();
		if (cdwLastSource == src && cdwLastLine == line && cdwLastColumn == col)
		{
			// wait for the caret staying on the same position for a second
			if(mTimeOutSamePos > now)
				return false;
			mTimeOutSamePos += dur!"days"(1);
		}
		else
		{
			cdwLastSource = src;
			cdwLastLine = line;
			cdwLastColumn = col;
			mTimeOutSamePos = now + dur!"seconds"(1);
			return false;
		}

		if (src.mDisasmFile.length)
		{
			int asmline = src.getLineInDisasm(line);
			if (asmline < 0)
				return false;
			return jumpToDefinitionInCodeWindow("", src.mDisasmFile, asmline, 0, false);
		}

		int startIdx, endIdx;
		if(!src.GetWordExtent(line, col, WORDEXT_CURRENT, startIdx, endIdx))
			return false;
		string word = toUTF8(src.GetText(line, startIdx, line, endIdx));
		if(word.length <= 0)
			return false;

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
			return false;

		string srcfile = src.GetFileName();
		string abspath;
		if(FindFileInSolution(defs[0].filename, srcfile, abspath) != S_OK)
			return false;

		return jumpToDefinitionInCodeWindow("", abspath, defs[0].line, 0, false);
	}

	//////////////////////////////////////////////////////////////
	bool mGCdisabled;
	SysTime mLastExecTime;
	size_t mGCUsedSize;
	enum PAGESIZE = 4096;

	void OnExec()
	{
		version(TWEAK_GC)
		if(false && !mGCdisabled)
		{
			GC.disable();
			mGCdisabled = true;
			//auto stats = gc_stats();
			//mGCUsedSize = stats.usedsize + PAGESIZE * stats.pageblocks;
		}
		mLastExecTime = Clock.currTime() + dur!"seconds"(2);
	}

	void CheckGC(bool forceEnable)
	{
		if(!mGCdisabled)
			return;

		SysTime now = Clock.currTime();
		version(TWEAK_GC)
		if(forceEnable || mLastExecTime < now)
		{
			GC.enable();
			auto stats = gc_stats();
			auto usedSize = stats.usedsize + PAGESIZE * stats.pageblocks;
			if(usedSize > mGCUsedSize + (20<<20))
			{
				GC.collect();
				stats = gc_stats();
				mGCUsedSize = stats.usedsize + PAGESIZE * stats.pageblocks;
			}
			mGCdisabled = false;
		}
	}

	//////////////////////////////////////////////////////////////
	extern(D) alias IdleTask = void delegate();
	IdleTask[] runInIdle;
	__gshared Object syncRunInIdle = new Object;

	void addIdleTask(IdleTask task)
	{
		synchronized(syncRunInIdle)
			runInIdle ~= task;
	}
	void execIdleTasks()
	{
		void delegate()[] toRun;
		synchronized(syncRunInIdle)
		{
			toRun = runInIdle;
			runInIdle = null;
		}
		foreach(r; toRun)
			r();
	}

	bool OnIdle()
	{
		execIdleTasks();

		if(mVDServerClient)
			mVDServerClient.onIdle();

		enum idleActiveViewOnly = true;

		if(IVsTextLines buffer = GetCurrentTextBuffer(null))
		{
			scope(exit) release(buffer);
			if(Source src = GetSource(buffer, false))
			{
				static if(idleActiveViewOnly)
				{
					if(src.OnIdle())
						return true;
					foreach(CodeWindowManager mgr; mCodeWinMgrs)
						if (mgr.mSource is src)
							mgr.OnIdle();
				}
				if(auto cfg = getProjectConfig(src.GetFileName())) // this triggers an update of the colorizer if VC config changed
					release(cfg);
			}
		}

		CheckGC(false);

		static if(!idleActiveViewOnly)
		{
			for(int i = 0; i < mSources.length; i++)
				if(mSources[i].OnIdle())
					return true;
			foreach(CodeWindowManager mgr; mCodeWinMgrs)
				if(mgr.OnIdle())
					return true;
		}

		if(mLastActiveView && mLastActiveView.mView)
		{
			int line, idx;
			mLastActiveView.mView.GetCaretPos(&line, &idx);
			if(tryJumpToDefinitionInCodeWindow(mLastActiveView.mCodeWinMgr.mSource, line, idx))
				return true;
			if (mLastActiveView.mCodeWinMgr.mNavBar)
				mLastActiveView.mCodeWinMgr.mNavBar.UpdateFromCaret(line, idx);
		}
		return false;
	}

	Source GetSource(IVsTextLines buffer, bool create = true)
	{
		Source src;
		for(int i = 0; i < mSources.length; i++)
		{
			src = mSources[i];
			if(src.mBuffer is buffer)
				goto L_found;
		}
		if(!create)
			return null;
		src = newCom!Source(buffer);
		mSources ~= src;
		src.AddRef();
	L_found:
		return src;
	}

	Source GetSource(string filename)
	{
		for(int i = 0; i < mSources.length; i++)
		{
			string srcfile = mSources[i].GetFileName();
			if(CompareFilenames(srcfile, filename) == 0)
				return mSources[i];
		}
		return null;
	}

	Source[] GetSources()
	{
		return mSources;
	}

	IVsTextView GetView(string filename)
	{
		foreach(cmgr; mCodeWinMgrs)
		{
			string srcfile = cmgr.mSource.GetFileName();
			if(CompareFilenames(srcfile, filename) == 0)
			{
				if (cmgr.mViewFilters.length)
					return cmgr.mViewFilters[0].mView;
				return null;
			}
		}
		return null;
	}

	ViewFilter GetViewFilter(Source src, IVsTextView view)
	{
		foreach(cmgr; mCodeWinMgrs)
			if (cmgr.mSource is src)
				return cmgr.GetViewFilter(view);
		return null;
	}

	void setDebugger(IVsDebugger debugger)
	{
		if(mCookieDebuggerEvents && mDebugger)
		{
			mDebugger.UnadviseDebuggerEvents(mCookieDebuggerEvents);
			mCookieDebuggerEvents = 0;
		}
		mDebugger = release(mDebugger);

		mDebugger = addref(debugger);
		if(mDebugger)
			mDebugger.AdviseDebuggerEvents(this, &mCookieDebuggerEvents);
	}

	bool IsDebugging()
	{
		return (mDbgMode & ~ DBGMODE_EncMask) != DBGMODE_Design;
	}

	bool GetCoverageData(string filename, uint line, uint* data, uint cnt, float* covPrecent)
	{
		if(!Package.GetGlobalOptions().showCoverageMargin)
			return false;

		Source src = GetSource(filename);
		if(!src)
			return false;

		auto cov = src.mColorizer.mCoverage;
		if(cov.length == 0)
			return false;

		for(uint ln = 0; ln < cnt; ln++)
		{
			uint covLine = src.adjustLineNumberSinceLastBuildReverse(line + ln, true);
			data[ln] = covLine >= cov.length ? -1 : cov[covLine];
		}
		if (covPrecent)
			*covPrecent = src.mColorizer.mCoveragePercent;

		return true;
	}

	// QuickInfo callback from C# ///////////////////////////////////

	private uint mLastTipIdleTaskScheduled;
	private uint mLastTipIdleTaskHandled;

	private uint mLastTipRequest;
	private uint mLastTipReceived;
	private wstring mLastTip;
	private wstring mLastTipFmt;
	private wstring mLastTipLinks;

	extern(D)
	void tipCallback(uint request, string fname, string text, TextSpan span)
	{
		mLastTipReceived = request;
		text = text.strip();
		text = text.replace("\r", "");
		text = replace(text, "\a", "\n\n");
		text = phobosDdocExpand(text);

		// remove quotes from `code` and put coloring information into fmt
		// extract links inside code from #<symbol#filename,line,col#>
		wstring tip = toUTF16(text);
		string fmt;
		wstring links;
		int state = Lexer.State.kWhite;
		size_t pos = 0;
		int prevcol = -1;
		bool incode = false;
		int beglink = -1;
		while (pos < tip.length)
		{
			uint prevpos = pos;
			int tok, col;
			if (tip[pos] == '`')
			{
				tip = tip[0 .. pos] ~ tip[pos + 1 .. $];
				incode = !incode;
				state = Lexer.State.kWhite;
				continue;
			}
			if (!incode)
			{
				while (pos < tip.length && tip[pos] != '`')
					decode(tip, pos);
				col = 0;
			}
			else if (state == Lexer.State.kWhite && tip[pos] == '#')
			{
				if (beglink < 0)
				{
					if (tip.length > pos + 1 && tip[pos+1] == '<')
					{
						tip = tip[0 .. pos] ~ tip[pos + 2 .. $];
						beglink = pos;
						continue;
					}
					pos++;
				}
				else
				{
					uint lpos = pos + 1;
					while (lpos + 1 < tip.length && (tip[lpos] != '#' || tip[lpos+1] != '>'))
						decode(tip, lpos);

					wstring link = tip[pos + 1 .. lpos];
					links ~= to!wstring(beglink) ~ "," ~ to!wstring(pos - beglink) ~ "," ~ link ~ ";";
					beglink = -1;

					tip = tip[0 .. pos] ~ tip[lpos + 2 .. $];
				}
			}
			else
			{
				col = dLex.scan(state, tip, pos, tok);
			}
			if (col != prevcol)
			{
				if (prevpos > 0)
				{
					fmt ~= ";";
					fmt ~= to!string(prevpos);
					fmt ~= ":";
				}
				fmt ~= defaultColors[col == 0 ? 5 : col-1].name;
				prevcol = col;
			}
		}
		mLastTip = tip;
		mLastTipFmt = toUTF16(fmt);
		mLastTipLinks = links;
	}

	uint RequestTooltip(string filename, int line, int col)
	{
		if (!Package.GetGlobalOptions().usesQuickInfoTooltips())
			return 0;

		if (++mLastTipIdleTaskScheduled == 0) // skip 0 as an error value
			++mLastTipIdleTaskScheduled;
		uint task = mLastTipIdleTaskScheduled;

		addIdleTask(() {
			if (task != mLastTipIdleTaskScheduled)
				return; // ignore old requests
			auto src = GetSource(filename);
			if (!src)
				return;

			TextSpan span = TextSpan(col, line, col + 1, line);
			string errorTip = src.getParseError(line, col);
			if (errorTip.length)
			{
				mLastTipRequest -= 10;
				tipCallback(mLastTipRequest, filename, errorTip, span);
			}
			else
			{
				ConfigureSemanticProject(src);
				int flags = (Package.GetGlobalOptions().showValueInTooltip ? 1 : 0) | 2 | 8;

				mLastTipRequest = vdServerClient.GetTip(src.GetFileName(), &span, flags, &tipCallback);
			}
			mLastTipIdleTaskHandled = mLastTipIdleTaskScheduled;
		});
		return mLastTipIdleTaskScheduled;
	}

	bool GetTooltipResult(uint task, out wstring tip, out wstring fmtdesc, out wstring links)
	{
		if (task != mLastTipIdleTaskScheduled)
			return true; // return empty tip for wrong request
		if (task != mLastTipIdleTaskHandled)
			return false; // wait some more
		if (mLastTipRequest != mLastTipReceived)
			return false; // wait some more

		tip = mLastTip;
		fmtdesc = mLastTipFmt;
		links = mLastTipLinks;
		return true;
	}

	// semantic completion ///////////////////////////////////

	uint GetTip(Source src, TextSpan* pSpan, bool overloads, GetTipCallBack cb)
	{
		ConfigureSemanticProject(src);
		int flags = Package.GetGlobalOptions().showValueInTooltip ? 1 : 0;
		if (overloads)
			flags |= 4;
		return vdServerClient.GetTip(src.GetFileName(), pSpan, flags, cb);
	}
	uint GetDefinition(Source src, TextSpan* pSpan, GetDefinitionCallBack cb)
	{
		ConfigureSemanticProject(src);
		return vdServerClient.GetDefinition(src.GetFileName(), pSpan, cb);
	}
	uint GetSemanticExpansions(Source src, string tok, int line, int idx, GetExpansionsCallBack cb)
	{
		ConfigureSemanticProject(src);
		wstring expr = src.FindExpressionBefore(line, idx);
		return vdServerClient.GetSemanticExpansions(src.GetFileName(), tok, line, idx, expr, cb);
	}
	uint GetReferences(Source src, string tok, int line, int idx, bool moduleOnly, GetReferencesCallBack cb)
	{
		ConfigureSemanticProject(src);
		wstring expr;
		return vdServerClient.GetReferences(src.GetFileName(), tok, line, idx, expr, moduleOnly, cb);
	}
	void GetIdentifierTypes(Source src, int startLine, int endLine, bool resolve, GetIdentifierTypesCallBack cb)
	{
		// always called after parse, no need to reconfigure project
		vdServerClient.GetIdentifierTypes(src.GetFileName(), startLine, endLine, resolve, cb);
	}
	void UpdateSemanticModule(Source src, wstring srctext, bool verbose, UpdateModuleCallBack cb)
	{
		ConfigureSemanticProject(src);
		vdServerClient.UpdateModule(src.GetFileName(), srctext, verbose, cb);
	}
	void ClearSemanticProject()
	{
		vdServerClient.ClearSemanticProject();
	}

	void ConfigureSemanticProject(Source src)
	{
		string file = src.GetFileName();
		Config cfg = getProjectConfig(file, true);
		if(!cfg)
			cfg = getCurrentStartupConfig();

		string[] imp;
		string[] stringImp;
		string[] versionids;
		string[] debugids;
		string cmdline;
		uint flags = 0;

		if(cfg)
		{
			scope(exit) release(cfg);
			auto cfgopts = cfg.GetProjectOptions();
			auto globopts = Package.GetGlobalOptions();
			imp = GetImportPaths(cfg) ~ Package.GetGlobalOptions().getImportPaths(cfgopts.compiler);
			flags = ConfigureFlags!()(cfgopts.useUnitTests, !cfgopts.release, cfgopts.isX86_64,
									  cfgopts.cov, cfgopts.doDocComments, cfgopts.boundscheck == 3,
									  cfgopts.compiler == Compiler.GDC,
									  cfgopts.versionlevel, cfgopts.debuglevel,
									  !cfgopts.useDeprecated, !cfgopts.errDeprecated,
									  cfgopts.compiler == Compiler.LDC,
									  cfgopts.useMSVCRT (), cfgopts.warnings, !cfgopts.infowarnings,
									  globopts.mixinAnalysis, globopts.UFCSExpansions);

			string strimp = cfgopts.replaceEnvironment(cfgopts.fileImppath, cfg);
			stringImp = tokenizeArgs(strimp);
			foreach(ref i; stringImp)
				i = normalizeDir(unquoteArgument(i));
			makeFilenamesAbsolute(stringImp, cfg.GetProjectDir());

			if (cfgopts.addDepImp)
				foreach(dep; cfg.getImportsFromDependentProjects())
					imp.addunique(dep);
			string versions = cfg.getCompilerVersionIDs();
			versionids = tokenizeArgs(versions);
			debugids = tokenizeArgs(cfgopts.debugids);
			cmdline = cfgopts.dmdFrontEndOptions();
		}
		else
		{
			// source file loaded into VS without project
			imp = Package.GetGlobalOptions().getImportPaths(Compiler.DMD);
			versionids = [ // default versions for dmd -m64
				"DigitalMars", "Windows", "Win64",
				"CRuntime_Microsoft", "CppRuntime_Microsoft",
				"D_Version2", "all", "assert",
				"LittleEndian", "D_SIMD",
				"X86_64", "D_LP64", "D_InlineAsm_X86_64",
				"D_ModuleInfo", "D_Exceptions", "D_TypeInfo", "D_HardFloat",
			];
			flags = ConfigureFlags!()(false, // bool unittestOn,
									  true,  // bool debugOn,
									  true,  // bool x64,
									  false, // bool cov,
									  false, // bool doc,
									  false, // bool nobounds,
									  false, // bool gdc,
									  0,     // int versionLevel,
									  0,     // int debugLevel,
									  false, // bool noDeprecated,
									  true,  // bool deprecateInfo,
									  false, // bool ldc,
									  true,  // bool msvcrt,
									  true,  // bool warnings,
									  false, // bool warnAsError,
									  true,  // bool mixinAnalysis,
									  false);// bool ufcsExpansions
		}
		vdServerClient.ConfigureSemanticProject(file, assumeUnique(imp), assumeUnique(stringImp),
		                                              assumeUnique(versionids), assumeUnique(debugids), cmdline, flags);
	}

	bool isBinaryOperator(Source src, int startLine, int startIndex, int endLine, int endIndex)
	{
		auto pos = vdc.util.TextPos(startIndex, startLine);
		return src.mBinaryIsIn.contains(pos) !is null;
		//return vdServerClient.isBinaryOperator(src.GetFileName(), startLine, startIndex, endLine, endIndex);
	}

private:
	//Package              mPackage;
	Source[]             mSources;
	CodeWindowManager[]  mCodeWinMgrs;
	DBGMODE              mDbgMode;

	VDServerClient       mVDServerClient;
	IVsDebugger          mDebugger;
	VSCOOKIE             mCookieDebuggerEvents = VSCOOKIE_NIL;
	VSCOOKIE             mUpdateSolutionEventsCookie = VSCOOKIE_NIL;
	UpdateSolutionEvents mUpdateSolutionEvents;
}

///////////////////////////////////////////////////////////////////////////////
// seperate object from LanguageService to avoid circular references
class UpdateSolutionEvents : DComObject, IVsUpdateSolutionEvents
{
	LanguageService mLangSvc;

	this(LanguageService svc)
	{
		mLangSvc = svc;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsUpdateSolutionEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsUpdateSolutionEvents ///////////////////////////////////
	HRESULT UpdateSolution_Begin(/+[in,   out]+/ BOOL *pfCancelUpdate)
	{
		return mLangSvc.UpdateSolution_Begin(pfCancelUpdate);
	}

	HRESULT UpdateSolution_Done(in BOOL   fSucceeded, in BOOL fModified, in BOOL fCancelCommand)
	{
		return mLangSvc.UpdateSolution_Done(fSucceeded, fModified, fCancelCommand);
	}

	HRESULT UpdateSolution_StartUpdate( /+[in, out]+/   BOOL *pfCancelUpdate )
	{
		return mLangSvc.UpdateSolution_StartUpdate(pfCancelUpdate);
	}

	HRESULT UpdateSolution_Cancel()
	{
		return mLangSvc.UpdateSolution_Cancel();
	}

	HRESULT OnActiveProjectCfgChange(/+[in]+/   IVsHierarchy pIVsHierarchy)
	{
		return mLangSvc.OnActiveProjectCfgChange(pIVsHierarchy);
	}
}

///////////////////////////////////////////////////////////////////////////////

class CodeWindowManager : DisposingComObject, IVsCodeWindowManager
{
	IVsCodeWindow mCodeWin;
	Source mSource;
	LanguageService mLangSvc;
	ViewFilter[] mViewFilters;
	NavigationBarClient mNavBar;

	this(LanguageService langSvc, IVsCodeWindow pCodeWin, Source source)
	{
		mCodeWin = pCodeWin;
		if(mCodeWin)
		{
			mCodeWin.AddRef();
		}
		mSource = addref(source);
		mLangSvc = langSvc;
		source.mCodeWinMgr = this;
	}

	~this()
	{
	}

	override void Dispose()
	{
		CloseFilters();

		if(mCodeWin)
		{
			mCodeWin.Release();
			mCodeWin = null;
		}
		mSource = release(mSource);
		mNavBar = release(mNavBar);
		mLangSvc = null;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsCodeWindowManager) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsCodeWindowManager //////////////////////////////////////
	override int AddAdornments()
	{
		mixin(LogCallMix);

		IVsTextView textView;
		if(mCodeWin.GetPrimaryView(&textView) != S_OK)
			return E_FAIL;

		// attach view filter to primary view.
		if(textView)
			OnNewView(textView);
		release(textView);

		// attach view filter to secondary view.
		textView = null;
		if(mCodeWin.GetSecondaryView(&textView) != S_OK)
			return E_FAIL;
		if(textView)
			OnNewView(textView);
		release(textView);

		return S_OK;
	}

	override int RemoveAdornments()
	{
		mixin(LogCallMix);

		CloseFilters();
		return S_OK;
	}

	override int OnNewView(IVsTextView pView)
	{
		mixin(LogCallMix);

		ViewFilter vf = newCom!ViewFilter(this, pView);
		mViewFilters ~= vf;
		return S_OK;
	}

	//////////////////////////////////////////////////////////////////////
	void SetupNavigationBar()
	{
		if (mNavBar)
			return;

		if (auto ddbm = qi_cast!IVsDropdownBarManager(mCodeWin))
		{
			IVsDropdownBar bar;
			if (ddbm.GetDropdownBar(&bar) != S_OK || !bar)
			{
				mNavBar = addref(newCom!NavigationBarClient(this));
				ddbm.AddDropdownBar(3, mNavBar);
			}
		}
	}

	//////////////////////////////////////////////////////////////////////

	bool OnIdle()
	{
		foreach(ViewFilter vf; mViewFilters)
			if(vf.OnIdle())
				return true;
		return false;
	}

	void CloseFilters()
	{
		foreach(ViewFilter vf; mViewFilters)
			vf.Dispose();
		mViewFilters = mViewFilters.init;
	}

	ViewFilter GetViewFilter(IVsTextView pView)
	{
		foreach(vf; mViewFilters)
			if(vf.mView is pView)
				return vf;
		return null;
	}
}

/////////////////////////////////////////////////////////////////////////
class NavigationBarClient : DisposingComObject, IVsDropdownBarClient, IVsCoTaskMemFreeMyStrings
{
	IVsDropdownBar mDropdownBar;
	CodeWindowManager mWinMgr;

	this(CodeWindowManager mgr)
	{
		mWinMgr = mgr;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsDropdownBarClient) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCoTaskMemFreeMyStrings) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override void Dispose()
	{
		mDropdownBar = release(mDropdownBar);
	}

	// IVsDropdownBarClient
	HRESULT SetDropdownBar(/+[in]+/ IVsDropdownBar pDropdownBar)
	{
		mDropdownBar = addref(pDropdownBar);
		return S_OK;
	}

	// called whenever info about a combo is needed; any of the out parameters are allowed to be passed in as NULL ptrs if not needed
	HRESULT GetComboAttributes(in int iCombo,
							   /+[out]+/ ULONG *pcEntries,
							   /+[out]+/ ULONG *puEntryType,  // ORing of DROPDOWNENTRYTYPE enum
							   /+[out]+/ HANDLE *phImageList)  // actually an HIMAGELIST
	{
		switch (iCombo)
		{
			case 0:
				*pcEntries = mGlobal.length;
				break;
			case 1:
				*pcEntries = mColumn2.length;
				break;
			case 2:
				*pcEntries = mColumn3.length;
				break;
			default:
				return S_FALSE;
		}
		*puEntryType = ENTRY_TEXT | ENTRY_IMAGE; // DROPDOWNENTRYTYPE
		*phImageList = cast(HANDLE) LanguageService.completionImageList;
		return S_OK;
	}

	// called for ENTRY_TEXT
	HRESULT GetEntryText(in int iCombo, in int iIndex, /+[out]+/ WCHAR **ppszText)
	{
		int idx = getNodeIndex(iCombo, iIndex);
		if (idx < 0 || idx >= mNodes.length)
			return S_FALSE;

		*ppszText = allocBSTR(mNodes[idx].desc);
		return S_OK;
	}

	// called for ENTRY_ATTR
	HRESULT GetEntryAttributes(in int iCombo, in int iIndex, 
							   /+[out]+/ ULONG *pAttr) // ORing of DROPDOWNFONTATTR enum values
	{
		return E_NOTIMPL;
	}

	// called for ENTRY_IMAGE
	HRESULT GetEntryImage(in int iCombo, in int iIndex, /+[out]+/ int *piImageIndex)
	{
		int idx = getNodeIndex(iCombo, iIndex);
		if (idx < 0 || idx >= mNodes.length)
			return S_FALSE; // keep space for image

		*piImageIndex = mNodes[idx].getImage();
		return S_OK;
	}

	HRESULT OnItemSelected(in int iCombo, in int iIndex)
	{
		return E_NOTIMPL;
	}

	HRESULT OnItemChosen(in int iCombo, in int iIndex)
	{
		int idx = getNodeIndex(iCombo, iIndex);
		if (idx < 0 || idx >= mNodes.length)
			return S_FALSE; // keep space for image

		return NavigateTo(mWinMgr.mSource.mBuffer, mNodes[idx].begline, 0, mNodes[idx].begline, 0);
	}

	HRESULT OnComboGetFocus(in int iCombo)
	{
		return E_NOTIMPL;
	}

	// GetComboTipText returns a tooltip for an entire combo
	HRESULT GetComboTipText(in int iCombo,  /+[out]+/ BSTR *pbstrText)
	{
		return E_NOTIMPL;
	}

	/////////////////////////////
	struct OutlineNode
	{
		int begline;
		int endline;
		int depth;
		int image;
		string desc;

		bool containsLine(int line) const
		{
			return begline <= line && line <= endline;
		}
		int getImage() const
		{
			return image;
		}
	}
	OutlineNode[] mNodes;
	size_t[] mGlobal;
	size_t[] mColumn2;
	size_t[] mColumn3;
	int mCurrentLine;

	void UpdateFromSource(string outline)
	{
		string[] lines = outline.splitLines();
		mNodes = new OutlineNode[lines.length];
		size_t valid = 0;

		foreach(ln; lines)
		{
			string[] toks = ln.split(":");
			if (toks.length >= 5)
			{
				try
				{
					mNodes[valid].depth = parse!int(toks[0]);
					mNodes[valid].begline = parse!int(toks[1]) - 1;
					mNodes[valid].endline = parse!int(toks[2]) - 1;
					mNodes[valid].image = visuald.completion.Declaration.Type2Glyph(toks[3]);
					mNodes[valid].desc = toks[4];
					if (mNodes[valid].depth > 0 && mNodes[valid].begline >= 0 &&
						mNodes[valid].endline >= mNodes[valid].begline && mNodes[valid].desc.length)
					valid++;
				}
				catch(ConvException)
				{
				}
			}
		}
		mNodes = mNodes[0..valid];

		FillGlobalColumn();

		_UpdateFromLine(mCurrentLine);
	}

	void FillGlobalColumn()
	{
		size_t cnt = 0;
		foreach (ref node; mNodes)
			if (node.depth <= 1)
				cnt++;

		mGlobal.length = cnt;
		cnt = 0;
		for (size_t n = 0; n < mNodes.length; n++)
			if (mNodes[n].depth <= 1)
				mGlobal[cnt++] = n;
	}

	int getNodeIndex(int iCombo, int index)
	{
		if (iCombo == 0)
			return index >= mGlobal.length ? -1 : mGlobal[index];
		if (iCombo == 1)
			return index >= mColumn2.length ? -1 : mColumn2[index];
		if (iCombo == 2)
			return index >= mColumn3.length ? -1 : mColumn3[index];
		return -1;
	}

	int findGlobalIndex(int line)
	{
		for (size_t g = 0; g < mGlobal.length; g++)
			if (mNodes[mGlobal[g]].containsLine(line))
				return g;
		return -1;
	}

	void UpdateFromCaret(int line, int col)
	{
		// col ignored for now
		if (line == mCurrentLine)
			return;
		_UpdateFromLine(line);
	}

	void _UpdateFromLine(int line)
	{
		mCurrentLine = line;
		mColumn2 = null;
		mColumn3 = null;
		int sel1 = findGlobalIndex(line);
		int sel2 = -1;
		int sel3 = -1;
		if (sel1 >= 0)
		{
			int g = mGlobal[sel1];
			int gdepth = mNodes[g].depth;
			for (int h = g + 1; h < mNodes.length; h++)
			{
				if (mNodes[h].depth <= gdepth)
					break;
				if (mNodes[h].depth == gdepth + 1)
				{
					mColumn2 ~= h;
					if (mNodes[h].containsLine(line))
					{
						sel2 = mColumn2.length - 1;
						int hdepth = mNodes[h].depth;
						for (int i = h + 1; i < mNodes.length; i++)
						{
							if (mNodes[i].depth <= hdepth)
								break;
							if (mNodes[i].depth == hdepth + 1)
							{
								mColumn3 ~= i;
								if (mNodes[i].containsLine(line))
								{
									sel3 = mColumn3.length - 1;
								}
							}
						}
					}
				}
			}
		}
		if (mDropdownBar)
		{
			mDropdownBar.RefreshCombo(0, sel1);
			mDropdownBar.RefreshCombo(1, sel2);
			mDropdownBar.RefreshCombo(2, sel3);
		}
	}
}

/////////////////////////////////////////////////////////////////////////
class CodeDefViewContext : DComObject, IVsCodeDefViewContext
{
	private string symbol;
	private string filename;
	private int line;
	private int column;

	this(string symbol, string filename, int line, int col)
	{
		this.symbol = symbol;
		this.filename = filename;
		this.line = line;
		this.column = col;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsCodeDefViewContext) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT GetCount(ULONG* pcItems)
	{
		*pcItems = 1;
		return S_OK;
	}
	override HRESULT GetCol(in ULONG iItem, ULONG* piCol)
	{
		*piCol = column;
		return S_OK;
	}
	override HRESULT GetLine(in ULONG iItem, ULONG* piLine)
	{
		*piLine = line;
		return S_OK;
	}
	override HRESULT GetFileName(in ULONG iItem, BSTR *pbstrFilename)
	{
		*pbstrFilename = allocBSTR(filename);
		return S_OK;
	}
	override HRESULT GetSymbolName(in ULONG iItem, BSTR *pbstrSymbolName)
	{
		*pbstrSymbolName = allocBSTR(symbol);
		return S_OK;
	}
}
/////////////////////////////////////////////////////////////////////////

HRESULT reloadTextBuffer(string fname)
{
	IVsRunningDocumentTable pRDT = queryService!(IVsRunningDocumentTable);
	if(!pRDT)
		return E_FAIL;
	scope(exit) release(pRDT);

	auto docname = _toUTF16z(fname);
	IVsHierarchy srpIVsHierarchy;
	VSITEMID     vsItemId          = VSITEMID_NIL;
	IUnknown     srpIUnknown;
	VSDOCCOOKIE  vsDocCookie       = VSDOCCOOKIE_NIL;
	HRESULT hr = pRDT.FindAndLockDocument(/* [in]  VSRDTFLAGS dwRDTLockType   */ RDT_NoLock,
										  /* [in]  LPCOLESTR pszMkDocument    */ docname,
										  /* [out] IVsHierarchy **ppHier      */ &srpIVsHierarchy,
										  /* [out] VSITEMID *pitemid          */ &vsItemId,
										  /* [out] IUnknown **ppunkDocData    */ &srpIUnknown,
										  /* [out] VSCOOKIE *pdwCookie        */ &vsDocCookie);

	// FindAndLockDocument returns S_FALSE if the doc is not in the RDT
	if (hr != S_OK)
		return hr;

	scope(exit) release(srpIUnknown);
	scope(exit) release(srpIVsHierarchy);

	IVsTextLines textBuffer = qi_cast!IVsTextLines(srpIUnknown);
	if(!textBuffer)
		if(auto bufferProvider = qi_cast!IVsTextBufferProvider(srpIUnknown))
		{
			bufferProvider.GetTextBuffer(&textBuffer);
			release(bufferProvider);
		}
	if(!textBuffer)
		return returnError(E_FAIL);
	scope(exit) release(textBuffer);

	if (auto docdata = qi_cast!IVsPersistDocData(srpIUnknown))
	{
		docdata.ReloadDocData(RDD_IgnoreNextFileChange|RDD_RemoveUndoStack);
		release(docdata);
	}

	return textBuffer.Reload(true);
}

HRESULT saveTextBuffer(string fname)
{
	IVsRunningDocumentTable pRDT = queryService!(IVsRunningDocumentTable);
	if(!pRDT)
		return E_FAIL;
	scope(exit) release(pRDT);

	auto docname = _toUTF16z(fname);
	IVsHierarchy srpIVsHierarchy;
	VSITEMID     vsItemId          = VSITEMID_NIL;
	IUnknown     srpIUnknown;
	VSDOCCOOKIE  vsDocCookie       = VSDOCCOOKIE_NIL;
	HRESULT hr = pRDT.FindAndLockDocument(/* [in]  VSRDTFLAGS dwRDTLockType   */ RDT_NoLock,
										  /* [in]  LPCOLESTR pszMkDocument    */ docname,
										  /* [out] IVsHierarchy **ppHier      */ &srpIVsHierarchy,
										  /* [out] VSITEMID *pitemid          */ &vsItemId,
										  /* [out] IUnknown **ppunkDocData    */ &srpIUnknown,
										  /* [out] VSCOOKIE *pdwCookie        */ &vsDocCookie);

	// FindAndLockDocument returns S_FALSE if the doc is not in the RDT
	if (hr != S_OK)
		return hr;

	scope(exit) release(srpIUnknown);
	scope(exit) release(srpIVsHierarchy);

	hr = pRDT.SaveDocuments(RDTSAVEOPT_SaveIfDirty, srpIVsHierarchy, vsItemId, vsDocCookie);
	return hr;
}

IVsTextView findCodeDefinitionWindow()
{
	IVsCodeDefView cdv = queryService!(SVsCodeDefView,IVsCodeDefView);
	if (!cdv)
		return null;
	scope(exit) release(cdv);

	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return null;
	scope(exit) release(textmgr);

	IVsEnumTextViews enumTextViews;

	// Passing null will return all available views, at least according to the documentation
	// unfortunately, it returns error E_INVALIDARG, said to be not implemented
	HRESULT hr = textmgr.EnumViews(null, &enumTextViews);
	if (!enumTextViews)
		return null;
	scope(exit) release(enumTextViews);

	IVsTextView tv;
	DWORD fetched;
	while(enumTextViews.Next(1, &tv, &fetched) == S_OK && fetched == 1)
	{
		BOOL result;
		if (cdv.IsCodeDefView(tv, &result) == S_OK && result)
			return tv;
	}
	return null;
}

bool jumpToDefinitionInCodeWindow(string symbol, string filename, int line, int col, bool forceShow)
{
	IVsCodeDefView cdv = queryService!(SVsCodeDefView,IVsCodeDefView);
	if (cdv is null)
		return false;
	scope(exit) release(cdv);

	if (!forceShow && cdv.IsVisible() != S_OK)
		return false;

	CodeDefViewContext context = newCom!CodeDefViewContext(symbol, filename, line, col);
	cdv.SetContext(context);

	if (forceShow)
	{
		if (cdv.IsVisible() != S_OK)
			cdv.ShowWindow();
		cdv.ForceIdleProcessing();
	}
	return true;
}

///////////////////////////////////////////////////////////////////////////////

int GetUserPreferences(LANGPREFERENCES3 *langPrefs, IVsTextView view)
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return E_FAIL;
	scope(exit) release(textmgr);

	langPrefs.guidLang = g_languageCLSID;
	IVsTextManager4 textmgr4;
	IID txtmgr4_iid = uuid_IVsTextManager4; // taking address of enum not allowed
	if(textmgr.QueryInterface(&txtmgr4_iid, cast(void**)&textmgr4) == S_OK && textmgr4)
	{
		scope(exit) release(textmgr4);
		if(int rc = textmgr4.GetUserPreferences4(null, langPrefs, null))
			return rc;
	}
	else
	{
		if(int rc = textmgr.GetUserPreferences(null, null, cast(LANGPREFERENCES*)langPrefs, null))
			return rc;
	}

	if (view)
	{
		int flags, tabsize, indentsize;
		if(vdhelper_GetTextOptions(view, &flags, &tabsize, &indentsize) == S_OK)
		{
			langPrefs.uTabSize = max(1, tabsize);
			langPrefs.uIndentSize = max(1, indentsize);
			langPrefs.fInsertTabs = (flags & 1) == 0;
		}
	}
	return S_OK;
}

static struct FormatOptions
{
	uint tabSize;
	uint indentSize;
	uint indentStyle;
	bool insertTabs;
	bool indentCase;
}

void GetFormatOptions(FormatOptions *fmtOpt, const LANGPREFERENCES3 *langPrefs)
{
	fmtOpt.tabSize = langPrefs.uTabSize;
	fmtOpt.indentSize = langPrefs.uIndentSize;
	fmtOpt.insertTabs = langPrefs.fInsertTabs != 0;
	fmtOpt.indentStyle = langPrefs.IndentStyle;

	fmtOpt.indentCase = Package.GetGlobalOptions().fmtIndentCase;
}

int GetFormatOptions(FormatOptions *fmtOpt, IVsTextView view)
{
	LANGPREFERENCES3 langPrefs;
	if(int rc = GetUserPreferences(&langPrefs, view))
		return rc;

	GetFormatOptions(fmtOpt, &langPrefs);
	return S_OK;
}

// An object to break cyclic dependencies on Source
class SourceEvents : DisposingComObject, IVsUserDataEvents, IVsTextLinesEvents
{
	Source mSource;
	uint mCookieUserDataEvents;
	uint mCookieTextLinesEvents;

	this(Source src, IVsTextLines buffer)
	{
		mSource = src;

		if(buffer)
		{
			mCookieUserDataEvents = Advise!(IVsUserDataEvents)(buffer, this);
			mCookieTextLinesEvents = Advise!(IVsTextLinesEvents)(buffer, this);
		}
	}

	override void Dispose()
	{
		IVsTextLines buffer = mSource.mBuffer;
		if(buffer)
		{
			if(mCookieUserDataEvents)
				Unadvise!(IVsUserDataEvents)(buffer, mCookieUserDataEvents);
			if(mCookieTextLinesEvents)
				Unadvise!(IVsTextLinesEvents)(buffer, mCookieTextLinesEvents);
		}
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsUserDataEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTextLinesEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsUserDataEvents //////////////////////////////////////
	override int OnUserDataChange(in GUID* riidKey, in VARIANT vtNewValue)
	{
		return mSource.OnUserDataChange(riidKey, vtNewValue);
	}

	// IVsTextLinesEvents //////////////////////////////////////
	override int OnChangeLineText(in TextLineChange *pTextLineChange, in BOOL fLast)
	{
		return mSource.OnChangeLineText(pTextLineChange, fLast);
	}

	override int OnChangeLineAttributes(in int iFirstLine, in int iLastLine)
	{
		return mSource.OnChangeLineAttributes(iFirstLine, iLastLine);
	}
}

struct ParseError
{
	ParserSpan span;
	string msg;
}

struct IdentifierType
{
	uint line;
	uint col;
	uint type;
}

class Source : DisposingComObject, IVsUserDataEvents, IVsTextLinesEvents,
               IVsTextMarkerClient, IVsHiddenTextClient
{
	Colorizer mColorizer;
	IVsTextLines mBuffer;
	CodeWindowManager mCodeWinMgr;
	CompletionSet mCompletionSet;
	MethodData mMethodData;
	ExpansionProvider mExpansionProvider;
	SourceEvents mSourceEvents;
	bool mOutlining;
	bool mStopOutlining;
	bool mVerifiedEncoding;
	bool mHasPendingUpdateModule;
	IVsHiddenTextSession mHiddenTextSession;

	static struct LineChange { int oldLine, newLine; }
	LineChange[] mLineChanges;
	size_t mLastSaveLineChangePos;
	TextLineChange mLastTextLineChange;

	wstring mParseText;
	ParseError[] mParseErrors;
	IdentifierType[][wstring] mIdentifierTypes;
	vdc.util.TextPos[] mBinaryIsIn;
	NewHiddenRegion[] mOutlineRegions;

	int mOutliningState;
	int mModificationCountOutlining;
	int mModificationCountSemantic;
	int mModificationCount;

	string mDisasmFile;
	string mLineInfoFile;
	LineInfo[] mDisasmLineInfo;
	SymLineInfo[string] mDisasmSymInfo;

	this(IVsTextLines buffer)
	{
		mBuffer = addref(buffer);
		mColorizer = newCom!Colorizer(this);
		mSourceEvents = newCom!SourceEvents(this, mBuffer);

		mOutlining = Package.GetGlobalOptions().autoOutlining;
		mModificationCountOutlining = -1;
		mModificationCountSemantic = -1;
	}
	~this()
	{
	}

	override void Dispose()
	{
		mExpansionProvider = release(mExpansionProvider);
		DismissCompletor();
		DismissMethodTip();

		clearParseErrors();
		clearReferenceMarker();

		mCompletionSet = release(mCompletionSet);
		if(mMethodData)
		{
			mMethodData.Dispose(); // we need to break the circular reference MethodData<->IVsMethodTipWindow
			mMethodData = release(mMethodData);
		}
		mSourceEvents.Dispose();
		mSourceEvents = null;
		mBuffer = release(mBuffer);
		mHiddenTextSession = release(mHiddenTextSession);
		mColorizer = null;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsUserDataEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTextLinesEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTextMarkerClient) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHiddenTextClient) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void setUtf8Encoding()
	{
		if(auto ud = qi_cast!IVsUserData(mBuffer))
		{
			scope(exit) release(ud);
			//object oname;
			//Guid GUID_VsBufferMoniker = typeof(IVsUserData).GUID;
			VARIANT var;
			if(SUCCEEDED(ud.GetData(&GUID_VsBufferEncodingVSTFF, &var)))
			{
				uint dwBufferVSTFF = var.ulVal;
				uint codepage = dwBufferVSTFF & VSTFF_CPMASK;           // to extract codepage
				uint vstffFlags = dwBufferVSTFF & VSTFF_FLAGSMASK;   // to extract CHARFMT
				if(!(vstffFlags & VSTFF_SIGNATURE) && codepage != 65001) // no signature, and not utf8
				{
					var.ulVal = vstffFlags | 65001;
					ud.SetData(&GUID_VsBufferEncodingVSTFF, var);
				}
			}
		}
	}

	// IVsUserDataEvents //////////////////////////////////////
	override int OnUserDataChange(in GUID* riidKey, in VARIANT vtNewValue)
	{
		return S_OK;
	}

	// IVsTextLinesEvents //////////////////////////////////////
	override int OnChangeLineText(in TextLineChange *pTextLineChange, in BOOL fLast)
	{
		mLastTextLineChange = *pTextLineChange;
		mModificationCount++;
		if(!mVerifiedEncoding)
		{
			mVerifiedEncoding = true;
			setUtf8Encoding();
		}
		if(pTextLineChange.iOldEndLine != pTextLineChange.iNewEndLine)
		{
			bool skip = false;
			if(pTextLineChange.iStartLine == 0 && pTextLineChange.iOldEndLine == 0)
			{
				// is this the first insert that actually fills the Source with the file content?
				skip = (GetLineCount() == pTextLineChange.iNewEndLine + 1);
			}
			if(!skip)
			{
				LineChange chg = LineChange(pTextLineChange.iOldEndLine, pTextLineChange.iNewEndLine);
				mLineChanges ~= chg;
			}
		}
		VerifyLineBreaks(pTextLineChange.iStartLine, pTextLineChange.iNewEndLine);
		if(mOutlining)
			CheckOutlining(pTextLineChange);
		return mColorizer.OnLinesChanged(pTextLineChange.iStartLine, pTextLineChange.iOldEndLine, pTextLineChange.iNewEndLine, fLast != 0);
	}

	void ClearLineChanges()
	{
		mLineChanges = mLineChanges.init;
		mLastSaveLineChangePos = 0;
	}

	override int OnChangeLineAttributes(in int iFirstLine, in int iLastLine)
	{
		return S_OK;
	}

	HRESULT ReColorizeLines(int iTopLine, int iBottomLine)
	{
		if(IVsTextColorState colorState = qi_cast!IVsTextColorState(mBuffer))
		{
			scope(exit) release(colorState);
			if(iBottomLine == -1)
				iBottomLine = GetLineCount() - 1;
			colorState.ReColorizeLines(iTopLine, iBottomLine);
		}
		return S_OK;
	}

	int adjustLineNumberSinceLastBuild(int line, bool sinceSave)
	{
		size_t pos = sinceSave ? mLastSaveLineChangePos : 0;
		foreach(ref chg; mLineChanges[pos..$])
			if(line >= chg.oldLine)
				line += chg.newLine - chg.oldLine;
		return line;
	}

	int adjustLineNumberSinceLastBuildReverse(int line, bool sinceSave)
	{
		size_t pos = sinceSave ? mLastSaveLineChangePos : 0;
		foreach_reverse(ref chg; mLineChanges[pos..$])
			if(line >= chg.newLine)
				line -= chg.newLine - chg.oldLine;
		return line;
	}

	// IVsTextMarkerClient //////////////////////////////////////
	override HRESULT MarkerInvalidated()
	{
		return S_OK;
	}

	override HRESULT GetTipText(/+[in]+/ IVsTextMarker pMarker,
		/+[out, optional]+/ BSTR *pbstrText)
	{
		if(auto marker = qi_cast!IVsTextLineMarker(pMarker))
		{
			scope(exit) marker.Release();
			TextSpan span;
			if(marker.GetCurrentSpan(&span) == S_OK)
			{
				string tip = getParseError(span.iStartLine, span.iStartIndex);
				if(tip.length)
				{
					*pbstrText = allocBSTR(tip);
					return S_OK;
				}
			}
		}
		return E_FAIL;
	}

	override HRESULT OnBufferSave(LPCOLESTR pszFileName)
	{
		mLastSaveLineChangePos = mLineChanges.length;
		return S_OK;
	}

	override HRESULT OnBeforeBufferClose()
	{
		return S_OK;
	}


	// Commands -- see MarkerCommandValues for meaning of iItem param
	override HRESULT GetMarkerCommandInfo(/+[in]+/ IVsTextMarker pMarker, in int iItem,
		/+[out, custom(uuid_IVsTextMarkerClient, "optional")]+/ BSTR * pbstrText,
		/+[out]+/ DWORD* pcmdf)
	{
		return E_NOTIMPL;
	}

	override HRESULT ExecMarkerCommand(/+[in]+/ IVsTextMarker pMarker, in int iItem)
	{
		return E_NOTIMPL;
	}

	override HRESULT OnAfterSpanReload()
	{
		return S_OK;
	}

	override HRESULT OnAfterMarkerChange(/+[in]+/ IVsTextMarker pMarker)
	{
		return S_OK;
	}

	// IVsHiddenTextClient ///////////////////////////////////////////////
	HRESULT OnHiddenRegionChange(IVsHiddenRegion pHidReg,
								 in HIDDEN_REGION_EVENT EventCode,     // HIDDENREGIONEVENT value
								 in BOOL fBufferModifiable)
	{
		return S_OK;
	}

	HRESULT GetTipText(/+[in]+/ IVsHiddenRegion pHidReg,
					   /+[out, optional]+/ BSTR *pbstrText)
	{
		TextSpan span;
		HRESULT hr = pHidReg.GetSpan(&span);
		if (FAILED(hr) || !pbstrText)
			return hr;
		wstring txt = GetText(span.iStartLine, 0, span.iEndLine, span.iEndIndex);

		LANGPREFERENCES3 langPrefs;
		uint tabsz = GetUserPreferences(&langPrefs, null) == S_OK ? langPrefs.uTabSize : 8;
		if (span.iStartIndex > 0 && span.iStartIndex <= txt.length)
		{
			int vpos = visiblePosition(txt, tabsz, span.iStartIndex);
			txt = repeat(cast(wchar)' ', vpos).array().to!wstring ~ txt[span.iStartIndex .. $];
		}
		// unindent text, limit line length and number of lines
		enum maxLines = 30;
		enum maxLineLength = 130;
		wstring[] lines = txt.splitLines();
		while (lines.length > 0 && strip(lines[0]).empty)
			lines = lines[1..$];
		size_t visibleLines = min(lines.length, maxLines);
		size_t minIndent = size_t.max;
		for (size_t ln = 0; ln < visibleLines; ln++)
		{
			int p;
			int n = countVisualSpaces(lines[ln], tabsz, &p);
			if (p < lines[ln].length && n < minIndent) // ignore empty lines
				minIndent = n;
		}
		for (size_t ln = 0; ln < visibleLines; ln++)
		{
			auto line = lines[ln].detab(tabsz);
			if (line.length < minIndent)
				line = null;
			else if (line.length > minIndent + maxLineLength)
				line = line[minIndent .. minIndent + maxLineLength] ~ "..."w;
			else
				line = line[minIndent .. $];
			lines[ln] = line.to!wstring;
		}
		if (lines.length > visibleLines)
			lines = lines[0..visibleLines] ~ "..."w;
		wstring tipText = join(lines, "\n"w);
		*pbstrText = allocwBSTR(tipText);
		return S_OK;
	}

	HRESULT GetMarkerCommandInfo(/+[in]+/ IVsHiddenRegion pHidReg, in int iItem,
									 /+[out, custom(uuid_IVsHiddenTextClient, "optional")]+/ BSTR * pbstrText,
									 /+[out]+/ DWORD* pcmdf)
	{
		return E_NOTIMPL;
	}
	HRESULT ExecMarkerCommand(/+[in]+/ IVsHiddenRegion pHidReg, in int iItem)
	{
		return E_NOTIMPL;
	}

	/*
	MakeBaseSpanVisible is used for visibility control.  If the user does something that requires a
	piece of hidden text to be visible (e.g. Goto line command, debugger stepping, find in files hit,
	etc.) then we will turn around and call this for regions that the text hiding manager cannot
	automatically make visible.  (In the current implementation this will only happen for concealed
	regions; collapsible ones will be automatically expanded.)  This CANNOT fail!!  You must either
	destroy the hidden region by calling IVsHiddenRegion::Remove() or else reset its range so that
	it is no longer hiding the hidden text.  It is OK to add/remove other regions when this is called.
	*/
	HRESULT MakeBaseSpanVisible(/+[in]+/ IVsHiddenRegion pHidReg, in TextSpan *pBaseSpan)
	{
		return E_NOTIMPL;
	}
	HRESULT OnBeforeSessionEnd()
	{
		return S_OK;
	}

	///////////////////////////////////////////////////////////////////////////////
	void setDisasmFiles(string asmfile, string linefile)
	{
		mDisasmFile = asmfile;
		mLineInfoFile = linefile;

		try
		{
			GlobalOptions globOpt = Package.GetGlobalOptions();
			if(globOpt.demangleError)
				asmfile ~= ".mangled";
			mDisasmSymInfo = readDisasmFile(asmfile);
			mDisasmLineInfo = readLineInfoFile(linefile, GetFileName());

			// force update to Code Definition Window
			auto langsvc = Package.GetLanguageService();
			int line, idx;
			if (langsvc.mLastActiveView && langsvc.mLastActiveView.mView &&
				langsvc.mLastActiveView.mCodeWinMgr.mSource == this)
				langsvc.mLastActiveView.mView.GetCaretPos(&line, &idx);

			reloadTextBuffer(mDisasmFile);

			int asmline = getLineInDisasm(line);
			jumpToDefinitionInCodeWindow("", mDisasmFile, asmline, 0, true);
		}
		catch(Exception e)
		{
			writeToBuildOutputPane(e.msg);
		}

	}

	int getLineInDisasm(int line)
	{
		line++; // 0-based line numbers in VS to 1-based line numbers in debug info
		if (line >= mDisasmLineInfo.length)
			line = mDisasmLineInfo.length - 1;
		// prefer to display asm of line before current line if none available on it
		while (line > 0 && mDisasmLineInfo[line].sym is null)
			line--;
		// fall back to display asm of first line in the file
		while (line < mDisasmLineInfo.length && mDisasmLineInfo[line].sym is null)
			line++;

		if (line >= mDisasmLineInfo.length)
			return -1;

		SymLineInfo* symInfo = mDisasmLineInfo[line].sym in mDisasmSymInfo;
		if (!symInfo)
			return -1;

		foreach (i, off; symInfo.offsets)
			if (off >= mDisasmLineInfo[line].offset)
				return symInfo.firstLine + i;

		return -1;
	}

	///////////////////////////////////////////////////////////////////////////////
	enum
	{
		kOutlineStateValid,
		kOutlineStateDirty,
		kOutlineStateDirtyIdle,
		kOutlineStateDirtyIdle2,
	}
	int mOutlineState = kOutlineStateDirty;

	bool OnIdle()
	{
		if(mColorizer.UpdateCoverage(false))
			return true;

		if(startParsing(true, true))
			return true;

version(threadedOutlining)
{
		return false;
} else {
		if(!mOutlining)
			return false;

		final switch(mOutlineState)
		{
			case kOutlineStateDirtyIdle2:
				UpdateOutlining();
				mOutlineState = kOutlineStateValid;
				return true;
			case kOutlineStateDirty:
				mOutlineState = kOutlineStateDirtyIdle;
				return false;
			case kOutlineStateDirtyIdle:
				mOutlineState = kOutlineStateDirtyIdle2;
				return false;
			case kOutlineStateValid:
				return false;
		}
}
	}

	void CheckOutlining(in TextLineChange *pTextLineChange)
	{
version(threadedOutlining) {} else
		mOutlineState = kOutlineStateDirty;
	}

	IVsHiddenTextSession GetHiddenTextSession()
	{
		if(mHiddenTextSession)
			return mHiddenTextSession;

		if(auto htm = queryService!(VsTextManager, IVsHiddenTextManager))
		{
			scope(exit) release(htm);
			if(htm.GetHiddenTextSession(mBuffer, &mHiddenTextSession) != S_OK)
				htm.CreateHiddenTextSession(0, mBuffer, this, &mHiddenTextSession);
		}
		return mHiddenTextSession;
	}

	enum int kHiddenRegionCookie = 37;

	bool AnyOutlineExpanded(IVsHiddenTextSession session)
	{
		IVsEnumHiddenRegions penum;
		TextSpan span = TextSpan(0, 0, 0, GetLineCount());
		session.EnumHiddenRegions(FHR_BY_CLIENT_DATA, kHiddenRegionCookie, &span, &penum);

		IVsHiddenRegion region;
		uint fetched;
		int hiddenLine = -1;
		bool expanded = false;
		while (!expanded && penum.Next(1, &region, &fetched) == S_OK && fetched == 1)
		{
			uint state;
			region.GetState(&state);
			region.GetSpan(&span);
			release(region);

			if(span.iStartLine <= hiddenLine)
				continue;
			if(state == hrsExpanded)
				expanded = true;
			hiddenLine = span.iEndLine;
		}
		release(penum);
		return expanded;
	}

	void UpdateOutlining()
	{
		if(auto session = GetHiddenTextSession())
			UpdateOutlining(session, hrsExpanded);
	}

	HRESULT StopOutlining()
	{
		if(mOutlining)
		{
			mStopOutlining = true;
			version(threadedOutlining)
				mModificationCount++; // trigger reparsing
			else
				CheckOutlining(null);
		}
		return S_OK;
	}

	HRESULT ToggleOutlining()
	{
		if(mOutlining)
		{
			if(auto session = GetHiddenTextSession())
				CollapseAllHiddenRegions(session, AnyOutlineExpanded(session));
		}
		return S_OK;
	}

	void UpdateOutlining(IVsHiddenTextSession session, int state)
	{
		NewHiddenRegion[] rgns = CreateOutlineRegions(state);
		if(DiffRegions(session, rgns))
			session.AddHiddenRegions(chrNonUndoable, rgns.length, rgns.ptr, null);
	}

	void CollapseAllHiddenRegions(IVsHiddenTextSession session, bool collapsed)
	{
		IVsEnumHiddenRegions penum;
		TextSpan span = TextSpan(0, 0, 0, GetLineCount());
		session.EnumHiddenRegions(FHR_BY_CLIENT_DATA, kHiddenRegionCookie, &span, &penum);

		IVsHiddenRegion region;
		uint fetched;
		while (penum.Next(1, &region, &fetched) == S_OK && fetched == 1)
		{
			region.SetState(collapsed ? hrsDefault : hrsExpanded, chrDefault);
			release(region);
		}
		release(penum);
	}

	NewHiddenRegion[] CreateOutlineRegions(int expansionState)
	{
		wstring source = GetText(); // should not be read from another thread
		return CreateOutlineRegions(source, expansionState);
	}

	NewHiddenRegion[] CreateOutlineRegions(wstring source, int expansionState)
	{
		NewHiddenRegion[] rgns;
		int lastOpenRegion = -1; // builds chain with iEndIndex of TextSpan
		Lexer lex;
		int state = 0;
		int lastCommentStartLine = -1;
		int lastCommentStartLineLength = 0;
		int prevLineLenth = 0;
		int ln = 0;
		int prevBracketLine = -1;
		int prevtok = 0;
		foreach(txt; splitter(source, '\n'))
		{
			if(mModificationCountOutlining != mModificationCount)
				break;

			//wstring txt = GetText(ln, 0, ln, -1);
			if(txt.length > 0 && txt[$-1] == '\r')
				txt = txt[0..$-1];

			uint pos = 0;
			bool isSpaceOrComment = true;
			bool isComment = false;
			while(pos < txt.length)
			{
				bool isCaseRegion(ref NewHiddenRegion rgn)
				{
					// -2: case before colon
					// -3: case after colon
					return rgn.tsHiddenText.iEndLine == -2 || rgn.tsHiddenText.iEndLine == -3;
				}
				void closeCaseRegion(int idx, int ln, int prevpos)
				{
					lastOpenRegion = rgns[idx].tsHiddenText.iEndIndex;
					if(isSpaceOrComment && !isComment) // move back into previous line
					{
						prevpos = prevLineLenth;
						ln--;
					}
					if(rgns[idx].tsHiddenText.iStartLine >= ln || rgns[idx].tsHiddenText.iEndLine == -2)
					{
						for(int i = idx; i < rgns.length - 1; i++)
							rgns[i] = rgns[i + 1];
						rgns.length = rgns.length - 1;
					}
					else
					{
						rgns[idx].tsHiddenText.iEndIndex = prevpos;
						rgns[idx].tsHiddenText.iEndLine = ln;
					}
				}

				uint prevpos = pos;
				int tok;
				int col = dLex.scan(state, txt, pos, tok);
				if(prevtok != TOK_goto && (tok == TOK_case || tok == TOK_default))
				{
					bool hasOpenCase = lastOpenRegion >= 0 && isCaseRegion(rgns[lastOpenRegion]);
					if (hasOpenCase && rgns[lastOpenRegion].tsHiddenText.iStartLine >= ln - 1)
					{
						// single line case statements don't need to be foldable
						// move start of region forward
						rgns[lastOpenRegion].tsHiddenText.iStartLine = ln;
					}
					else
					{
						if(hasOpenCase)
							closeCaseRegion(lastOpenRegion, ln, prevpos);

						NewHiddenRegion rgn;
						rgn.iType = hrtCollapsible;
						rgn.dwBehavior = hrbClientControlled;
						rgn.dwState = expansionState;
						rgn.tsHiddenText = TextSpan(pos - 1, ln, lastOpenRegion, -2); // use endLine as marker for 'case'
						rgn.pszBanner = "..."w.ptr;
						rgn.dwClient = kHiddenRegionCookie;
						lastOpenRegion = rgns.length;
						rgns ~= rgn;
					}

				}
				if(col == TokenCat.Operator)
				{
					if(txt[pos-1] == '{' || txt[pos-1] == '[')
					{
						NewHiddenRegion rgn;
						rgn.iType = hrtCollapsible;
						rgn.dwBehavior = hrbClientControlled;
						rgn.dwState = expansionState;
						if(ln > prevBracketLine+1 && isSpaceOrComment && !isComment) // move into previous line
							rgn.tsHiddenText = TextSpan(prevLineLenth, ln-1, lastOpenRegion, -1);
						else
							rgn.tsHiddenText = TextSpan(pos - 1, ln, lastOpenRegion, -1);
						rgn.pszBanner = txt[pos-1] == '{' ? "{...}"w.ptr : "[...]"w.ptr;
						rgn.dwClient = kHiddenRegionCookie;
						lastOpenRegion = rgns.length;
						rgns ~= rgn;
						prevBracketLine = ln;
					}
					else if((txt[pos-1] == '}' || txt[pos-1] == ']') && lastOpenRegion >= 0)
					{
						if(isCaseRegion(rgns[lastOpenRegion]))
							closeCaseRegion(lastOpenRegion, ln, prevpos);

						if(lastOpenRegion >= 0)
						{
							int idx = lastOpenRegion;
							lastOpenRegion = rgns[idx].tsHiddenText.iEndIndex;
							if(rgns[idx].tsHiddenText.iStartLine == ln)
							{
								for(int i = idx; i < rgns.length - 1; i++)
									rgns[i] = rgns[i + 1];
								rgns.length = rgns.length - 1;
							}
							else
							{
								rgns[idx].tsHiddenText.iEndIndex = pos;
								rgns[idx].tsHiddenText.iEndLine = ln;
							}
							prevBracketLine = ln;
						}
					}
					else if (tok == TOK_colon && lastOpenRegion >= 0)
					{
						if(rgns[lastOpenRegion].tsHiddenText.iEndLine == -2)
						{
							rgns[lastOpenRegion].tsHiddenText.iStartLine = ln;
							rgns[lastOpenRegion].tsHiddenText.iStartIndex = pos;
							rgns[lastOpenRegion].tsHiddenText.iEndLine = -3;
						}
					}
					else if (tok == TOK_slice && prevtok == TOK_colon && lastOpenRegion >= 0)
					{
						// case range statement "case n: .. case", wait for next colon
						if(rgns[lastOpenRegion].tsHiddenText.iEndLine == -3)
							rgns[lastOpenRegion].tsHiddenText.iEndLine = -2;
					}
				}
				isComment = isComment || (col == TokenCat.Comment);
				if (!Lexer.isCommentOrSpace(col, txt[prevpos .. pos]))
				{
					prevtok = tok;
					isSpaceOrComment = false;
				}
			}
			if(lastCommentStartLine >= 0)
			{
				// do not fold single comment line with subsequent empty line
				if(!isSpaceOrComment || (!isComment && lastCommentStartLine + 1 == ln))
				{
					if(lastCommentStartLine + 1 < ln)
					{
						NewHiddenRegion rgn;
						rgn.iType = hrtCollapsible;
						rgn.dwBehavior = hrbClientControlled;
						rgn.dwState = expansionState;
						rgn.tsHiddenText = TextSpan(lastCommentStartLineLength, lastCommentStartLine, prevLineLenth, ln - 1);
						rgn.pszBanner = "..."w.ptr;
						rgn.dwClient = kHiddenRegionCookie;
						rgns ~= rgn;
					}
					lastCommentStartLine = -1;
				}
			}
			else if(isComment && isSpaceOrComment)
			{
				lastCommentStartLine = ln;
				lastCommentStartLineLength = txt.length;
			}
			prevLineLenth = txt.length;
			ln++;
		}
		while(lastOpenRegion >= 0)
		{
			int idx = lastOpenRegion;
			lastOpenRegion = rgns[idx].tsHiddenText.iEndIndex;
			rgns[idx].tsHiddenText.iEndIndex = 0;
			rgns[idx].tsHiddenText.iEndLine = ln;
			rgns[idx].pszBanner = rgns[idx].pszBanner[0] == '{' ? "{..."w.ptr : "[..."w.ptr;
		}
		return rgns;
	}

	version(none) unittest
	{
		const(void)* p = typeid(NewHiddenRegion).rtInfo;
		assert(p !is rtinfoNoPointers && p !is rtinfoHasPointers);
	}

	bool DiffRegions(IVsHiddenTextSession session, ref NewHiddenRegion[] rgns)
	{
		// Compare the existing regions with the new regions and
		// remove any that do not match the new regions.
		IVsEnumHiddenRegions penum;
		TextSpan span = TextSpan(0, 0, 0, GetLineCount());
		session.EnumHiddenRegions(FHR_BY_CLIENT_DATA, kHiddenRegionCookie, &span, &penum);

		uint found = 0;
		uint enumerated = 0;
		uint fetched;
		IVsHiddenRegion region;
		while(penum.Next(1, &region, &fetched) == S_OK && fetched == 1)
		{
			enumerated++;
			region.GetSpan(&span);
			int i;
			for(i = 0; i < rgns.length; i++)
				if(rgns[i].tsHiddenText == span)
					break;
			if(i < rgns.length)
			{
				for(int j = i + 1; j < rgns.length; j++)
					rgns[j-1] = rgns[j];
				rgns.length = rgns.length - 1;
				found++;
			}
			else
				region.Invalidate(chrNonUndoable);
			release(region);
		}
		release(penum);

		// validate regions against current text
		int lines = GetLineCount();
		for(int i = 0; i < rgns.length; i++)
		{
			with(rgns[i].tsHiddenText)
			{
				if(iStartLine >= lines)
				{
					rgns.length = i;
					break;
				}
				if(iEndLine >= lines)
					iEndLine = lines;
				int length;
				mBuffer.GetLengthOfLine(iStartLine, &length);
				if(iStartIndex >= length)
					iStartIndex = length;
				if(iStartLine != iEndLine)
					mBuffer.GetLengthOfLine(iEndLine, &length);
				if(iEndIndex >= length)
					iEndIndex = length;
			}
		}
		return found != enumerated || rgns.length != 0;
	}

	static bool lessRegionStart(IVsHiddenRegion a, IVsHiddenRegion b)
	{
		TextSpan aspan, bspan;
		a.GetSpan(&aspan);
		b.GetSpan(&bspan);
		return aspan.iStartLine < bspan.iStartLine ||
		       (aspan.iStartLine == bspan.iStartLine && aspan.iStartIndex < bspan.iStartIndex);
	}

	HRESULT CollapseDisabled(bool unittests, bool disabled)
	{
		auto session = GetHiddenTextSession();
		if(!session)
			return S_OK;

		IVsEnumHiddenRegions penum;
		TextSpan span = TextSpan(0, 0, 0, GetLineCount());
		session.EnumHiddenRegions(FHR_BY_CLIENT_DATA, kHiddenRegionCookie, &span, &penum);

		mColorizer.syncParser(span.iEndLine);

		IVsHiddenRegion[] rgns;
		IVsHiddenRegion region;
		uint fetched;
		while (penum.Next(1, &region, &fetched) == S_OK && fetched == 1)
			rgns ~= region;

		// sort regions by start
		auto sortedrgns = sort!lessRegionStart(rgns);
		int nextLine = 0;
		foreach(rgn; sortedrgns)
		{
			DWORD state;
			rgn.GetState(&state);
			if((state & hrsExpanded) != 0)
			{
				rgn.GetSpan(&span);
				int len;
				if(mBuffer.GetLengthOfLine(span.iStartLine, &len) == S_OK && span.iStartIndex >= len)
				{
					span.iStartLine++;
					span.iStartIndex = 0;
				}
				if(span.iStartLine >= nextLine)
				{
					bool collapse = unittests && mColorizer.isInUnittest(span.iStartLine, span.iStartIndex);
					if (!collapse)
						collapse = disabled && !mColorizer.isAddressEnabled(span.iStartLine, span.iStartIndex);
					if(collapse)
					{
						rgn.SetState(hrsDefault, chrDefault);
						nextLine = span.iEndLine; // do not collapse recursively
					}
				}
			}
		}

		foreach(rgn; rgns)
			release(rgn);
		release(penum);
		return S_OK;
	}

	///////////////////////////////////////////////////////////////////////////////
	wstring GetText(int startLine, int startCol, int endLine, int endCol)
	{
		if(endLine == -1)
			mBuffer.GetLastLineIndex(&endLine, &endCol);
		else if(endCol == -1)
			mBuffer.GetLengthOfLine(endLine, &endCol);

		BSTR text;
		HRESULT hr = mBuffer.GetLineText(startLine, startCol, endLine, endCol, &text);
		return wdetachBSTR(text);
	}

	wstring GetText()
	{
		int endLine, endCol;
		mBuffer.GetLastLineIndex(&endLine, &endCol);

		BSTR text;
		HRESULT hr = mBuffer.GetLineText(0, 0, endLine, endCol, &text);
		return wdetachBSTR(text);
	}

	bool GetWordExtent(int line, int idx, WORDEXTFLAGS flags, out int startIdx, out int endIdx)
	{
		startIdx = endIdx = idx;

version(all)
{
		wstring txt = GetText(line, 0, line, -1);
		if(idx > txt.length)
			return false;
		for(size_t p = endIdx; p < txt.length && dLex.isIdentifierCharOrDigit(decode(txt, p)); endIdx = p) {}
		for(size_t p = startIdx; p > 0 && dLex.isIdentifierCharOrDigit(decodeBwd(txt, p)); startIdx = p) {}
		return startIdx < endIdx;
}
else
{
		int length;
		mBuffer.GetLengthOfLine(line, &length);
		// pin to length of line just in case we return false and skip pinning at the end of this method.
		startIdx = endIdx = min(idx, length);
		if (length == 0)
			return false;

		//get the character classes
		TokenInfo[] lineInfo = GetLineInfo(line);
		if (lineInfo.length == 0)
			return false;

		int count = lineInfo.length;
		TokenInfo info;
		int index = this.GetTokenInfoAt(lineInfo, idx, info, true);
		if (index < 0)
			return false;
		if (index < lineInfo.length - 1 && info.EndIndex == idx)
			if (lineInfo[index + 1].type == TokenCat.Identifier)
				info = lineInfo[++index];
		if (index > 0 && info.StartIndex == idx)
			if (lineInfo[index - 1].type == TokenCat.Identifier)
				info = lineInfo[--index];

		// don't do anything in comment or text or literal space, unless we
		// are doing intellisense in which case we want to match the entire value
		// of quoted strings.
		TokenCat type = info.type;
		if ((flags != WORDEXT_FINDTOKEN || type != TokenCat.String) &&
		    (type == TokenCat.Comment || type == TokenCat.Text ||
			 type == TokenCat.String || type == TokenCat.Literal || type == TokenCat.Operator))
			return false;

		//search for a token
		switch (flags & WORDEXT_MOVETYPE_MASK)
		{
		case WORDEXT_PREVIOUS:
			index--;
			while (index >= 0 && !MatchToken(flags, lineInfo[index]))
				index--;
			if (index < 0)
				return false;
			break;

		case WORDEXT_NEXT:
			index++;
			while (index < count && !MatchToken(flags, lineInfo[index]))
				index++;
			if (index >= count)
				return false;
			break;

		case WORDEXT_NEAREST:
			int prevIdx = index;
			prevIdx--;
			while (prevIdx >= 0 && !MatchToken(flags, lineInfo[prevIdx]))
				prevIdx--;
			int nextIdx = index;
			while (nextIdx < count && !MatchToken(flags, lineInfo[nextIdx]))
				nextIdx++;

			if (prevIdx < 0 && nextIdx >= count)
				return false;
			if (nextIdx >= count)
				index = prevIdx;
			else if (prevIdx < 0)
				index = nextIdx;
			else if (index - prevIdx < nextIdx - index)
				index = prevIdx;
			else
				index = nextIdx;
			break;

		case WORDEXT_CURRENT:
		default:
			if (!MatchToken(flags, info))
				return false;
			break;
		}
		info = lineInfo[index];

		// We found something, set the span, pinned to the valid coordinates for the
		// current line.
		startIdx = min(length, info.StartIndex);
		endIdx = min(length, info.EndIndex);
		return true;
}
	}

	bool GetTipSpan(TextSpan* pSpan)
	{
		if(pSpan.iStartLine == pSpan.iEndLine && pSpan.iStartIndex == pSpan.iEndIndex)
		{
			int startIdx, endIdx;
			if(!GetWordExtent(pSpan.iStartLine, pSpan.iStartIndex, WORDEXT_CURRENT, startIdx, endIdx))
				return false;
			pSpan.iStartIndex = startIdx;
			pSpan.iEndIndex = endIdx;

			wstring txt = GetText(pSpan.iStartLine, 0, pSpan.iStartLine, -1);
		L_again:
			size_t idx = pSpan.iStartIndex;
			dchar c;
			for (size_t p = idx; p > 0 && isWhite(c = decodeBwd(txt, p)); idx = p) {}
			if(idx >= 0 && c == '.')
			{
				idx--; // skip '.'
				for (size_t p = idx; p > 0 && isWhite(decodeBwd(txt, p)); idx = p) {}
				for (size_t p = idx; p > 0 && dLex.isIdentifierCharOrDigit(decodeBwd(txt, p)); idx = p) {}
				pSpan.iStartIndex = idx;
				goto L_again;
			}
		}
		return true;
	}

	static bool MatchToken(WORDEXTFLAGS flags, TokenInfo info)
	{
		TokenCat type = info.type;
		if ((flags & WORDEXT_FINDTOKEN) != 0)
			return type != TokenCat.Comment && type != TokenCat.String;
		return (type == TokenCat.Keyword || type == TokenCat.Identifier || type == TokenCat.Literal);
	}

	int GetLineCount()
	{
		int lineCount;
		mBuffer.GetLineCount(&lineCount);
		return lineCount;
	}

	int GetLastLineIndex(ref int endLine, ref int endCol)
	{
		return mBuffer.GetLastLineIndex(&endLine, &endCol);
	}

	TokenInfo[] GetLineInfo(int line, wstring *ptext = null)
	{
		wstring text = GetText(line, 0, line, -1);
		if(ptext)
			*ptext = text;
		return GetLineInfoFromText(line, text);
	}

	TokenInfo[] GetLineInfoFromText(int line, wstring text)
	{
		TokenInfo[] lineInfo;
		int iState = mColorizer.GetLineState(line);
		if(iState == -1)
			return lineInfo;

		lineInfo = dLex.ScanLine(iState, text);
		return lineInfo;
	}

	static int GetTokenInfoAt(TokenInfo[] infoArray, int col, ref TokenInfo info, bool extendLast = false)
	{
		int len = infoArray.length;
		for (int i = 0; i < len; i++)
		{
			int start = infoArray[i].StartIndex;
			int end = infoArray[i].EndIndex;

			if (i == 0 && start > col)
				return -1;

			if (col >= start && col < end)
			{
				info = infoArray[i];
				return i;
			}
		}
		if (len > 0)
		{
			info = infoArray[len-1];
			if(col == info.EndIndex)
				return len-1;
		}
		return -1;
	}

	wstring _getToken(ref TokenInfo[] infoArray, ref int line, ref int col,
	                  ref TokenInfo info, int idx, bool skipComments)
	{
		wstring text;
		if(idx < 0)
			idx = infoArray.length;
		for(;;)
		{
			text = GetText(line, 0, line, -1);
			while(idx < infoArray.length)
			{
				if((!skipComments || infoArray[idx].type != TokenCat.Comment) &&
				   (infoArray[idx].type != TokenCat.Text || !isWhite(text[infoArray[idx].StartIndex])))
					break;
				idx++;
			}
			if(idx < infoArray.length)
				break;

			line++;
			int lineCount;
			mBuffer.GetLineCount(&lineCount);
			if(line >= lineCount)
				return "";

			infoArray = GetLineInfo(line);
			idx = 0;
		}
		info = infoArray[idx];
		col = infoArray[idx].StartIndex;
		return text[infoArray[idx].StartIndex .. infoArray[idx].EndIndex];
	}

	wstring GetToken(ref TokenInfo[] infoArray, ref int line, ref int col,
	                 ref TokenInfo info, bool skipComments = true)
	{
		int idx = GetTokenInfoAt(infoArray, col, info);
		return _getToken(infoArray, line, col, info, idx, skipComments);
	}

	wstring GetNextToken(ref TokenInfo[] infoArray, ref int line, ref int col,
						 ref TokenInfo info, bool skipComments = true)
	{
		int idx = GetTokenInfoAt(infoArray, col, info);
		if(idx >= 0)
			idx++;
		return _getToken(infoArray, line, col, info, idx, skipComments);
	}

	string GetFileName()
	{
		if(!mBuffer)
			return null;
		if(IPersistFileFormat fileFormat = qi_cast!IPersistFileFormat(mBuffer))
		{
			scope(exit) release(fileFormat);
			uint format;
			LPOLESTR filename;
			if(fileFormat.GetCurFile(&filename, &format) == S_OK)
				return to_string(filename);
		}
		if(IVsUserData ud = qi_cast!IVsUserData(mBuffer))
		{
			scope(exit) release(ud);
			//object oname;
			//Guid GUID_VsBufferMoniker = typeof(IVsUserData).GUID;
			//hr = ud.GetData(ref GUID_VsBufferMoniker, out oname);
		}
		return null;
	}

	//////////////////////////////////////////////////////////////
	bool findStatementStart(ref int line, ref int col, ref wstring fn)
	{
		int cl = col;
		int level = 0;
		TokenInfo info;
		bool testNextFn = false;
		for(int ln = line; ln >= 0; --ln)
		{
			wstring txt;
			TokenInfo[] lineInfo = GetLineInfo(ln, &txt);
			int inf = cl < 0 ? lineInfo.length - 1 : GetTokenInfoAt(lineInfo, cl-1, info);
			for( ; inf >= 0; inf--)
			{
				if(lineInfo[inf].type != TokenCat.Comment &&
				   (lineInfo[inf].type != TokenCat.Text || !isWhite(txt[lineInfo[inf].StartIndex])))
				{
					wchar ch = txt[lineInfo[inf].StartIndex];
					if(level == 0)
						if(ch == ';' || ch == '}' || ch == '{' || ch == ':')
							return true;

					if(testNextFn && lineInfo[inf].type == TokenCat.Identifier)
						fn = txt[lineInfo[inf].StartIndex .. lineInfo[inf].EndIndex];
					testNextFn = false;

					if(Lexer.isClosingBracket(ch))
						level++;
					else if(Lexer.isOpeningBracket(ch) && level > 0)
					{
						level--;
						if(level == 0 && fn.length == 0)
							testNextFn = true;
					}
					line = ln;
					col = inf;
				}
			}
			cl = -1;
		}

		return false;
	}

	wstring getScopeIdentifer(int line, int col, wstring fn)
	{
		TokenInfo info;
		TokenInfo[] infoArray = GetLineInfo(line);
		wstring next, tok = GetToken(infoArray, line, col, info);

		for(;;)
		{
			switch(tok)
			{
			case "struct":
			case "class":
			case "interface":
			case "union":
			case "enum":
				next = GetNextToken(infoArray, line, col, info);
				if(next == ":" || next == "{")
					return tok; // unnamed class/struct/enum
				return next;

			case "mixin":
			case "static":
			case "final":
			case "const":
			case "alias":
			case "override":
			case "abstract":
			case "volatile":
			case "deprecated":
			case "in":
			case "out":
			case "inout":
			case "lazy":
			case "auto":
			case "private":
			case "package":
			case "protected":
			case "public":
			case "export":
				break;

			case "align":
			case "extern":
				next = GetNextToken(infoArray, line, col, info);
				if(next == "("w)
				{
					next = GetNextToken(infoArray, line, col, info);
					next = GetNextToken(infoArray, line, col, info);
				}
				else
				{
					tok = next;
					continue;
				}
				break;

			case "synchronized":
				next = GetNextToken(infoArray, line, col, info);
				if(next == "("w)
				{
					next = GetNextToken(infoArray, line, col, info);
					next = GetNextToken(infoArray, line, col, info);
				}
				return tok;

			case "scope":
				next = GetNextToken(infoArray, line, col, info);
				if(next == "("w)
				{
					tok ~= next;
					tok ~= GetNextToken(infoArray, line, col, info);
					tok ~= GetNextToken(infoArray, line, col, info);
					return tok;
				}
				break;

			case "debug":
			case "version":
				next = GetNextToken(infoArray, line, col, info);
				if(next == "("w)
				{
					tok ~= next;
					tok ~= GetNextToken(infoArray, line, col, info);
					tok ~= GetNextToken(infoArray, line, col, info);
				}
				return tok;

			case "this":
			case "if":
			case "else":
			case "while":
			case "for":
			case "do":
			case "switch":
			case "try":
			case "catch":
			case "finally":
			case "with":
			case "asm":
			case "foreach":
			case "foreach_reverse":
				return tok;

			default:
				return fn.length ? fn ~ "()"w : tok;
			}
			tok = GetNextToken(infoArray, line, col, info);
		}
	}

	//////////////////////////////////////////////////////////////
	int ReplaceLineIndent(int line, FormatOptions* fmtOpt, ref CacheLineIndentInfo cacheInfo)
	{
		wstring linetxt = GetText(line, 0, line, -1);
		int p, orgn = countVisualSpaces(linetxt, fmtOpt.tabSize, &p);
		int n = 0;
		if(p < linetxt.length)
			n = CalcLineIndent(line, 0, fmtOpt, cacheInfo);
		if(n < 0)
			n = 0;
		if(n == orgn)
			return S_OK;

		return doReplaceLineIndent(line, p, n, fmtOpt);
	}

	int doReplaceLineIndent(int line, int idx, int n, FormatOptions* fmtOpt)
	{
		int tabsz = (fmtOpt.insertTabs && fmtOpt.tabSize > 0 ? fmtOpt.tabSize : n + 1);
		string spc = replicate("\t", n / tabsz) ~ replicate(" ", n % tabsz);
		wstring wspc = toUTF16(spc);

		TextSpan changedSpan;
		return mBuffer.ReplaceLines(line, 0, line, idx, wspc.ptr, wspc.length, &changedSpan);
	}

	static struct _LineTokenIterator(SRC)
	{
		int line;
		int tok;
		SRC src;

		wstring lineText;
		TokenInfo[] lineInfo;

		this(SRC _src, int _line, int _tok)
		{
			src = _src;
			set(_line, _tok);
		}

		void set(int _line, int _tok)
		{
			line = _line;
			tok = _tok;
			lineInfo = src.GetLineInfo(line, &lineText);
		}

		bool advance()
		{
			while(tok + 1 >= lineInfo.length)
			{
				if(line + 1 >= src.GetLineCount())
					return false;

				line++;
				lineInfo = src.GetLineInfo(line, &lineText);
				tok = -1;
			}
			tok++;
			return true;
		}

		bool onSpace()
		{
			return (lineInfo[tok].type == TokenCat.Text && isWhite(lineText[lineInfo[tok].StartIndex]));
		}

		bool onCommentOrSpace()
		{
			return (lineInfo[tok].type == TokenCat.Comment ||
			        (lineInfo[tok].type == TokenCat.Text && isWhite(lineText[lineInfo[tok].StartIndex])));
		}

		bool advanceOverSpaces()
		{
			while(advance())
			{
				if(!onSpace())
					return true;
			}
			return false;
		}
		bool advanceOverComments()
		{
			while(advance())
			{
				if(!onCommentOrSpace())
					return true;
			}
			return false;
		}
		bool advanceOverBraces()
		{
			wstring txt = getText();
			if(txt == "}")
			{
				int otherLine, otherIndex;
				if(src.FindClosingBracketForward(line, lineInfo[tok].StartIndex, otherLine, otherIndex))
				{
					set(otherLine, otherIndex);
				}
			}
			return advanceOverComments();
		}

		bool ensureNoComment(bool skipLines)
		{
			if(tok < lineInfo.length && !onCommentOrSpace())
				return true;

			if(!skipLines)
			{
				while(tok + 1 < lineInfo.length)
				{
					tok++;
					if(!onCommentOrSpace())
						return true;
				}
				return false;
			}
			return advanceOverComments();
		}

		bool retreat()
		{
			while(tok <= 0)
			{
				if(line <= 0)
					return false;

				line--;
				lineInfo = src.GetLineInfo(line, &lineText);
				tok = lineInfo.length;
			}
			tok--;
			return true;
		}

		bool retreatOverComments()
		{
			while(retreat())
			{
				if(!onCommentOrSpace())
					return true;
			}
			return false;
		}
		bool retreatOverBraces()
		{
			wstring txt = getText();
			if(txt == "}" || txt == ")" || txt == "]")
			{
				int otherLine, otherLinePos;
				if(src.FindOpeningBracketBackward(line, tok, otherLine, otherLinePos))
				{
					int iState;
					uint pos;
					int otherIndex = src.FindLineToken(otherLine, otherLinePos, iState, pos);
					set(otherLine, otherIndex);
				}
			}
			return retreatOverComments();
		}

		wstring getText()
		{
			if(tok < lineInfo.length)
				return lineText[lineInfo[tok].StartIndex .. lineInfo[tok].EndIndex];
			return null;
		}

		int getIndex()
		{
			if(tok < lineInfo.length)
				return lineInfo[tok].StartIndex;
			return 0;
		}

		int getEndIndex()
		{
			if(tok < lineInfo.length)
				return lineInfo[tok].EndIndex;
			return 0;
		}

		int getTokenType()
		{
			if(tok < lineInfo.length)
				return lineInfo[tok].type;
			return -1;
		}

		int getTokenId()
		{
			if(tok < lineInfo.length)
				return lineInfo[tok].tokid;
			return -1;
		}

		wstring getPrevToken(int n = 1)
		{
			auto it = this;
			foreach(i; 0..n)
				it.retreatOverComments();
			return it.getText();
		}
		wstring getNextToken(int n = 1)
		{
			auto it = this;
			foreach(i; 0..n)
				it.advanceOverComments();
			return it.getText();
		}
	}

	alias _LineTokenIterator!Source LineTokenIterator;

	static struct CacheLineIndentInfo
	{
		bool hasOpenBraceInfoValid;
		bool hasOpenBrace;
		int  hasOpenBraceLine;
		int  hasOpenBraceTok;
		LineTokenIterator hasOpenBraceIt;

		bool findCommaInfoValid;
		int  findCommaIndent;
		int  findCommaIndentLine;
	}

	// calculate the indentation of the given line
	// - if ch != 0, assume it being inserted at the beginning of the line
	// - find the beginning of the previous statement
	//   - if the first token on the line is "else", find the matching "if" and indent to its line
	//   - set iterator tokIt to the last token of the previous line
	//   - if *tokIt is ';', move back one
	//   - while *tokIt is not the stop marker or '{' or ';'
	//     - move back one matching braces
	// - if the token before the given line is not ';' or '}', indent by one level more

	// special handling for:
	// - comma at the end of next line
	// - case/default
	// - label:

	int CalcLineIndent(int line, dchar ch, FormatOptions* fmtOpt, ref CacheLineIndentInfo cacheInfo)
	{
		LineTokenIterator lntokIt = LineTokenIterator(this, line, 0);
		wstring startTok;
		wstring startTok2;
		if(ch != 0)
			startTok ~= ch;
		else
		{
			lntokIt.ensureNoComment(false);
			startTok = lntokIt.getText();
			startTok2 = lntokIt.getNextToken(1);
		}
		wstring txt;

		if(!lntokIt.retreatOverComments())
			return 0;

		bool isOpenBraceOrCase(ref LineTokenIterator it)
		{
			wstring txt = it.getText();
			if(txt == "{" || txt == "[")
				return true;
			if(txt == "case" || txt == "default")
			{
				wstring prev = it.getPrevToken();
				if(prev != "goto")
					return true;
			}
			return false;
		}
		int findMatchingIf()
		{
			int cntIf = 1;
			while(cntIf > 0 && lntokIt.retreatOverBraces())
			{
				if(isOpenBraceOrCase(lntokIt)) // emergency exit on pending opening brace
					return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + fmtOpt.tabSize;
				txt = lntokIt.getText();
				if(txt == "if")
					--cntIf;
				else if(txt == "else")
					++cntIf;
			}
			return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
		}
		bool findOpenBrace(ref LineTokenIterator it)
		{
			int itline = it.line;
			int ittok  = it.tok;

			bool saveCacheInfo(bool res)
			{
				cacheInfo.hasOpenBraceInfoValid = true;
				cacheInfo.hasOpenBrace = res;
				cacheInfo.hasOpenBraceIt = it;
				cacheInfo.hasOpenBraceLine = itline;
				cacheInfo.hasOpenBraceTok = ittok;
				return res;
			}

			do
			{
				txt = it.getText();
				if(txt == "{" || txt == "[" || txt == "(")
					return saveCacheInfo(true);

				if(cacheInfo.hasOpenBraceInfoValid && it.line == cacheInfo.hasOpenBraceLine && it.tok == cacheInfo.hasOpenBraceTok)
				{
					it = cacheInfo.hasOpenBraceIt;
					return cacheInfo.hasOpenBrace;
				}
			}
			while(it.retreatOverBraces());

			return saveCacheInfo(false);
		}

		int findPreviousCaseIndent()
		{
			do
			{
				txt = lntokIt.getText();
				if(txt == "{" || txt == "[") // emergency exit on pending opening brace
					return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + (fmtOpt.indentCase ? fmtOpt.tabSize : 0);
				if(txt == "case" || txt == "default")
					if(lntokIt.getPrevToken() != "goto")
						break;
			}
			while(lntokIt.retreatOverBraces());
			return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
		}

		// called when previous line ends with a comma
		// use cases:
		//
		// enum ID {
		//     E1,
		//--------------
		// function(arg1,
		//--------------
		// int[] arr = [
		//     expression,
		//--------------
		// Struct s = {
		//     expression,
		//--------------
		// case C1,
		//--------------
		// case C1:
		//     expression,
		//--------------
		// label:
		//     expression,
		//--------------
		// public import mod1,
		//--------------
		// ulong var,
		//--------------
		// const(UDT) var,

		int findCommaIndent()
		{
			int itline = lntokIt.line;

			int saveCacheInfo(int indent)
			{
				cacheInfo.findCommaInfoValid = true;
				cacheInfo.findCommaIndent = indent;
				cacheInfo.findCommaIndentLine = itline;
				return indent;
			}

			wstring txt;
			int commaIndent = countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
			do
			{
				if(cacheInfo.findCommaInfoValid && lntokIt.line < cacheInfo.findCommaIndentLine)
					return saveCacheInfo(cacheInfo.findCommaIndent);

				wstring prevtxt = txt;
				txt = lntokIt.getText();
				if(txt == "(")
					// TODO: should scan for first non-white after '('
					return saveCacheInfo(visiblePosition(lntokIt.lineText, fmtOpt.tabSize, lntokIt.getIndex() + 1));
				if(txt == "[")
					return saveCacheInfo(commaIndent);
				if(txt == ",")
					commaIndent = countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
				if(txt == "{")
				{
					// figure out if this is a struct initializer, enum declaration or a statement group
					if(lntokIt.retreatOverBraces())
					{
						wstring prev = txt;
						txt = lntokIt.getText();
						if(txt == "=") // struct initializer
							return saveCacheInfo(commaIndent);
						do
						{
							txt = lntokIt.getText();
							if(txt == "enum")
							{
								commaIndent = countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
								break;
							}
							if(txt == "{" || txt == "}" || txt == ";")
							{
								if(prev == "enum")
									return saveCacheInfo(commaIndent);
								else
									break;
							}
							prev = txt;
						}
						while(lntokIt.retreatOverBraces());
					}
					return saveCacheInfo(commaIndent + fmtOpt.tabSize);
				}
				if(isOpenBraceOrCase(lntokIt))
					return saveCacheInfo(countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + fmtOpt.tabSize);

				if(txt == ";") // triggers the end of a statement, but not do {} while()
					return saveCacheInfo(commaIndent + fmtOpt.tabSize);

				if(txt == "}" && prevtxt != ",")
				{
					// end of statement or struct initializer?
					// assumes it on '}',
/+					bool isPrecededByStatement(ref LineTokenIterator it)
					{
						if (!it.retreatOverComments())
							return false;

						txt = it.getText();
						if (txt == "{")
							return true; // empty statement {}

						do
						{
							if (txt == ";" || txt == "if" || txt == "switch" || txt == "while" || txt == "for" ||
								txt == "foreach" || txt == "with" || txt == "synchronized" || txt == "try" || txt == "asm")
								return true;
							if (!it.retreatOverBraces())
								break;
							txt = it.getText();
						}
						while(txt != "{");
						return false;
					}
					// indent once from line with first comma
					if (!isPrecededByStatement(lntokIt))
						return saveCacheInfo(commaIndent + fmtOpt.tabSize);
+/
					return saveCacheInfo(commaIndent + fmtOpt.tabSize);
//					lntokIt.advanceOverComments();
//					return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + fmtOpt.tabSize;
				}
			}
			while(lntokIt.retreatOverBraces());

			return saveCacheInfo(fmtOpt.tabSize);
		}

		if(startTok == "else")
			return findMatchingIf();
		if(startTok == "case" || startTok == "default")
			return findPreviousCaseIndent();

		LineTokenIterator it = lntokIt;
		bool hasOpenBrace = findOpenBrace(it);
		if(hasOpenBrace && (txt == "(" || txt == "["))
		{
			// align to text following the open brace
			LineTokenIterator nit = it;
			if(nit.advanceOverSpaces() && nit.line < line)
				return visiblePosition(nit.lineText, fmtOpt.tabSize, nit.getIndex());
		}

		if(startTok == "}" || startTok == "]")
		{
			if(hasOpenBrace)
				return countVisualSpaces(it.lineText, fmtOpt.tabSize);
			return 0;
		}

		wstring prevTok = lntokIt.getText();
		if(prevTok == ",")
			return findCommaIndent();

		int indent = 0, labelIndent = 0;
		bool newStmt = (prevTok == ";" || prevTok == "}" || prevTok == "{" || prevTok == ":");
		if(newStmt)// || prevTok == ":")
			if(dLex.isIdentifier(startTok) && startTok2 == ":") // is it a jump label?
			{
				labelIndent = -fmtOpt.tabSize;
				newStmt = true;
			}
		if(newStmt)
		{
			if(prevTok != "{" && prevTok != ":")
				lntokIt.retreatOverBraces();
		}
		else if(prevTok == ")" && (startTok == "in" || startTok == "out" || startTok == "body"))
			indent = 0; // special case to not indent in/out/body contracts
		else if(startTok != "{" && startTok != "[" && hasOpenBrace)
			indent = fmtOpt.tabSize;
		if(prevTok == "{" || prevTok == "[")
			return nextTabPosition(countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + labelIndent, fmtOpt.tabSize);

		bool skipLabel = false;
		do
		{
			wstring nexttxt = txt;
			txt = lntokIt.getText();
			if(txt == "(")
				return visiblePosition(lntokIt.lineText, fmtOpt.tabSize, lntokIt.getIndex() + 1);
			if(isOpenBraceOrCase(lntokIt))
				return nextTabPosition(countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + indent + labelIndent, fmtOpt.tabSize);

			if((txt == "}" && nexttxt != ",") || txt == ";") // triggers the end of a statement, but not do {} while()
			{
				// use indentation of next statement
				lntokIt.advanceOverComments();
				// skip labels
				wstring label = lntokIt.getText();
				if(!dLex.isIdentifier(label) || lntokIt.getNextToken() != ":")
					return countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + indent + labelIndent;
				lntokIt.retreatOverComments();
				newStmt = true;
			}
			if(!newStmt && isKeyword(toUTF8(txt))) // dLex.isIdentifier(txt))
			{
				return indent + countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize);
			}
			if(newStmt && txt == "else")
			{
				findMatchingIf();
				if(isOpenBraceOrCase(lntokIt))
					return nextTabPosition(countVisualSpaces(lntokIt.lineText, fmtOpt.tabSize) + labelIndent, + fmtOpt.tabSize);
			}
		}
		while(lntokIt.retreatOverBraces());

		return indent + labelIndent;
	}

	int ReindentLines(IVsTextView view, int startline, int endline)
	{
		FormatOptions fmtOpt;
		if(int rc = GetFormatOptions(&fmtOpt, view))
			return rc;
		if(fmtOpt.indentStyle != vsIndentStyleSmart)
			return S_FALSE;

		CacheLineIndentInfo cacheInfo;
		for(int line = startline; line <= endline; line++)
		{
			int rc = ReplaceLineIndent(line, &fmtOpt, cacheInfo);
			if(FAILED(rc))
				return rc;
		}
		return S_OK;
	}

	int VerifyLineBreaks(int iStartLine, int iNewEndLine)
	{
		if(iStartLine >= iNewEndLine) // only insertions
			return S_FALSE;

		int rc = S_FALSE; // S_OK if modification
		int refline = (iStartLine > 0 ? iStartLine - 1 : iNewEndLine + 1);
		if (refline < GetLineCount())
		{
			string refnl = GetLineBreakText(mBuffer, refline);
			wstring wrefnl = to!wstring(refnl);
			for (int ln = iStartLine; ln <= iNewEndLine; ln++)
			{
				string nl = GetLineBreakText(mBuffer, ln);
				if (nl != refnl)
				{
					wstring text = GetText(ln, 0, ln + 1, 0);
					if (text.endsWith(nl))
					{
						text = text[0..$-nl.length] ~ wrefnl;
						TextSpan changedSpan;
						rc = mBuffer.ReplaceLines(ln, 0, ln + 1, 0, text.ptr, text.length, &changedSpan);
					}
				}
			}
		}
		return rc;
	}

	////////////////////////////////////////////////////////////////////////
	wstring FindExpressionBefore(int caretLine, int caretIndex)
	{
		int startLine, startIndex;
		LineTokenIterator lntokIt = LineTokenIterator(this, caretLine + 1, 0);
		while(lntokIt.line > caretLine || (lntokIt.getIndex() >= caretIndex && lntokIt.line == caretLine))
			if(!lntokIt.retreatOverComments())
				break;

		if(lntokIt.getTokenType() == TokenColor.Identifier && lntokIt.getEndIndex() >= caretIndex && lntokIt.line == caretLine)
			lntokIt.retreatOverComments();
		if(lntokIt.getText() != ".")
			return null;

		caretLine = lntokIt.line;
		caretIndex = lntokIt.getIndex();
		lntokIt.retreatOverComments();

	L_retry:
		startLine = lntokIt.line;
		startIndex = lntokIt.getIndex();

		int type = lntokIt.getTokenType();
		if(type == TokenColor.Identifier || type == TokenColor.String || type == TokenColor.Literal)
		{
			lntokIt.retreatOverComments();
			wstring tok = lntokIt.getText();
			if(tok == "." || tok == "!")
			{
				lntokIt.retreatOverComments();
				goto L_retry;
			}
		}
		else
		{
			wstring tok = lntokIt.getText();
			if(tok == "}" || tok == ")" || tok == "]")
			{
				lntokIt.retreatOverBraces();
				goto L_retry;
			}
		}
		wstring wsnip = GetText(startLine, startIndex, caretLine, caretIndex);
		return wsnip;
	}

	////////////////////////////////////////////////////////////////////////
	enum
	{
		AutoComment,
		ForceComment,
		ForceUncomment,
	}

	int CommentLines(IVsTextView view, int startline, int endline, int commentMode)
	{
		LANGPREFERENCES3 langPrefs;
		if(int rc = GetUserPreferences(&langPrefs, view))
			return rc;

		wstring[] lines;
		wstring txt;
		int n, m, p, indent = -1;
		int line;
		// calc minimum indent
		for(line = startline; line <= endline; line++)
		{
			txt = GetText(line, 0, line, -1);
			n = countVisualSpaces(txt, langPrefs.uTabSize, &p);
			if (p < txt.length) // ignore empty line
				indent = (indent < 0 || indent > n ? n : indent);
			lines ~= txt;
		}

		for(line = startline; line <= endline; line++)
		{
			txt = lines[line - startline];
			n = countVisualSpaces(txt, langPrefs.uTabSize, &p);
			if(p >= txt.length || n != indent)
				break;
			else if(p + 1 >= txt.length || txt[p] != '/' || txt[p+1] != '/')
				break;
		}

		if (line > endline && commentMode != ForceComment)
		{
			// remove comment
			for(line = startline; line <= endline; line++)
			{
				txt = lines[line - startline];
				n = countVisualSpaces(txt, langPrefs.uTabSize, &p);
				assert(n == indent && txt[p] == '/' && txt[p+1] == '/');
				txt = txt[0..p] ~ "  " ~ txt[p+2..$];
				m = countVisualSpaces(txt, langPrefs.uTabSize, &p) - 2;

				if(p >= txt.length)
					txt = "";
				else
					txt = createVisualSpaces!wstring(m, langPrefs.fInsertTabs ? langPrefs.uTabSize : 0);

				TextSpan changedSpan;
				if (int hr = mBuffer.ReplaceLines(line, 0, line, p, txt.ptr, txt.length, &changedSpan))
					return hr;
			}
		}
		else if((line <= endline && commentMode != ForceUncomment) || commentMode == ForceComment)
		{
			// insert comment
			int tabsz = (langPrefs.fInsertTabs ? langPrefs.uTabSize : 0);
			wstring pfx = createVisualSpaces!wstring(indent, tabsz) ~ "//"w;

			for(line = startline; line <= endline; line++)
			{
				txt = lines[line - startline];
				n = countVisualSpaces(txt, langPrefs.uTabSize, &p);

				wstring add = createVisualSpaces!wstring(n - indent, 0, 2); // use spaces, not tabs
				wstring ins = pfx ~ add;
				TextSpan changedSpan;
				if (int hr = mBuffer.ReplaceLines(line, 0, line, p, ins.ptr, ins.length, &changedSpan))
					return hr;
			}
		}
		return S_OK;
	}

	//////////////////////////////////////////////////////////////

	// return the token index from the scan sequence
	// iState,pos is the scan state before the token at char index idx
	int FindLineToken(int line, int idx, out int iState, out uint pos)
	{
		int state = mColorizer.GetLineState(line);
		if(state == -1)
			return -1;

		wstring text = GetText(line, 0, line, -1);
		uint p = 0;
		int tok = 0;
		while(p < text.length)
		{
			iState = state;
			pos = p;
			if(p == idx)
				return tok;

			dLex.scan(state, text, p);
			if(p > idx)
				return tok;

			tok++;
		}
		return -1;
	}

	// continuing from FindLineToken
	bool FindEndOfTokens(ref int iState, ref int line, ref uint pos,
						 bool function(int state, int data) testFn, int data)
	{
		int lineCount;
		mBuffer.GetLineCount(&lineCount);

		uint plinepos = pos;
		while(line < lineCount)
		{
			wstring text = GetText(line, 0, line, -1);
			while(pos < text.length)
			{
				uint ppos = pos;
				int toktype = dLex.scan(iState, text, pos);
				if(testFn(iState, data))
				{
					/+
					if(ppos == 0)
					{
						pos = plinepos;
						line--;
					}
					else
						pos = ppos;
					+/
					return true;
				}
			}
			plinepos = pos;
			pos = 0;
			line++;
		}
		return false;
	}

	static bool testEndComment(int state, int level)
	{
		int slevel = Lexer.nestingLevel(state);
		if(slevel > level)
			return false;
		auto sstate = Lexer.scanState(state);
		if(sstate == Lexer.State.kNestedComment)
			return slevel <= level;
		return sstate != Lexer.State.kBlockComment;
	}

	bool FindEndOfComment(int startState, ref int iState, ref int line, ref uint pos)
	{
		int level = Lexer.nestingLevel(startState);
		if(testEndComment(iState, level))
			return true;
		return FindEndOfTokens(iState, line, pos, &testEndComment, level);
	}

	static bool testEndString(int state, int level)
	{
		if(Lexer.tokenStringLevel(state) > level)
			return false;

		auto sstate = Lexer.scanState(state);
		return !Lexer.isStringState(sstate);
	}
	bool FindEndOfString(int startState, ref int iState, ref int line, ref uint pos)
	{
		int level = Lexer.tokenStringLevel(startState);
		if(testEndString(iState, level))
			return true;
		return FindEndOfTokens(iState, line, pos, &testEndString, level);
	}

	bool FindStartOfTokens(ref int iState, ref int line, ref uint pos,
	                       bool function(int state, int data) testFn, int data)
	{
		int lineState;
		uint plinepos = pos;
		uint foundpos = uint.max;

		while(line >= 0)
		{
			wstring text = GetText(line, 0, line, -1);
			lineState = mColorizer.GetLineState(line);

			uint len = (plinepos > text.length ? text.length : plinepos);
			plinepos = 0;

			if(testFn(lineState, data))
				foundpos = 0;
			while(plinepos < len)
			{
				int toktype = dLex.scan(lineState, text, plinepos);
				if(testFn(lineState, data))
					foundpos = plinepos;
			}

			if(foundpos < uint.max)
			{
				pos = foundpos;
				return true;
			}

			plinepos = uint.max;
			line--;
		}
		return false;
	}

	static bool testStartComment(int state, int level)
	{
		if(!Lexer.isCommentState(Lexer.scanState(state)))
			return true;
		int slevel = Lexer.nestingLevel(state);
		return slevel < level;
	}

	bool FindStartOfComment(ref int iState, ref int line, ref uint pos)
	{
		// comment ends after the token that starts at (line,pos) with state iState
		// possible states:
		// - not a comment state: comment starts at passed pos
		// - it's a block comment: scan backwards until we find a non-comment state
		// - it's a nested comment: scan backwards until we find a state with nesting level less than passed state
		if(!Lexer.isCommentState(Lexer.scanState(iState)))
			return true;
		int level = Lexer.nestingLevel(iState);
		return FindStartOfTokens(iState, line, pos, &testStartComment, level);
	}

	bool FindStartOfString(ref int iState, ref int line, ref uint pos)
	{
		int level = Lexer.tokenStringLevel(iState);
		if(testEndString(iState, level))
			return true;
		return FindStartOfTokens(iState, line, pos, &testEndString, level);
	}

	bool FindClosingBracketForward(int line, int idx, out int otherLine, out int otherIndex)
	{
		int iState;
		uint pos;
		int tok = FindLineToken(line, idx, iState, pos);
		if(tok < 0)
			return false;

		wstring text = GetText(line, 0, line, -1);
		uint ppos = pos;
		int toktype = dLex.scan(iState, text, pos);
		if(toktype != TokenCat.Operator)
			return false;

		return FindClosingBracketForward(line, iState, pos, otherLine, otherIndex);
	}

	bool FindClosingBracketForward(int line, int iState, uint pos, out int otherLine, out int otherIndex)
	{
		int lineCount;
		mBuffer.GetLineCount(&lineCount);
		int level = 1;
		while(line < lineCount)
		{
			wstring text = GetText(line, 0, line, -1);
			while(pos < text.length)
			{
				uint ppos = pos;
				int type = dLex.scan(iState, text, pos);
				if(type == TokenCat.Operator)
				{
					if(Lexer.isOpeningBracket(text[ppos]))
						level++;
					else if(Lexer.isClosingBracket(text[ppos]))
						if(--level <= 0)
						{
							otherLine = line;
							otherIndex = ppos;
							return true;
						}
				}
			}
			line++;
			pos = 0;
		}
		return false;
	}

	bool FindOpeningBracketBackward(int line, int tok, out int otherLine, out int otherIndex,
	                                int* pCountComma = null)
	{
		if(pCountComma)
			*pCountComma = 0;
		int level = 1;
		while(line >= 0)
		{
			wstring text = GetText(line, 0, line, -1);
			int[] tokpos;
			int[] toktype;
			uint pos = 0;

			int iState = mColorizer.GetLineState(line);
			if(iState == -1)
				break;

			while(pos < text.length)
			{
				tokpos ~= pos;
				toktype ~= dLex.scan(iState, text, pos);
			}
			int p = (tok >= 0 ? tok : tokpos.length) - 1;
			for( ; p >= 0; p--)
			{
				pos = tokpos[p];
				if(toktype[p] == TokenCat.Operator)
				{
					if(pCountComma && text[pos] == ',')
						(*pCountComma)++;
					else if(Lexer.isClosingBracket(text[pos]))
						level++;
					else if(Lexer.isOpeningBracket(text[pos]))
						if(--level <= 0)
						{
							otherLine = line;
							otherIndex = pos;
							return true;
						}
				}
			}
			line--;
			tok = -1;
		}
		return false;
	}

	bool ScanBackward(int line, int tok,
					  bool delegate(wstring text, uint pos, uint ppos, int type) dg)
	{
		while(line >= 0)
		{
			wstring text = GetText(line, 0, line, -1);
			int[] tokpos;
			int[] toktype;
			uint pos = 0;

			int iState = mColorizer.GetLineState(line);
			if(iState == -1)
				break;

			while(pos < text.length)
			{
				tokpos ~= pos;
				toktype ~= dLex.scan(iState, text, pos);
			}
			int p = (tok >= 0 ? tok : tokpos.length) - 1;
			uint ppos = (p >= tokpos.length - 1 ? text.length : tokpos[p+1]);
			for( ; p >= 0; p--)
			{
				pos = tokpos[p];
				if(dg(text, pos, ppos, toktype[p]))
					return true;
				ppos = pos;
			}
			line--;
			tok = -1;
		}
		return false;
	}

	// tok is sitting on the opening parenthesis, return method name and its position
	wstring FindMethodIdentifierBackward(int line, int tok, int* pline, int* pindex)
	{
		LineTokenIterator it = LineTokenIterator(this, line, tok);
		scope(exit)
		{
			if(pline)
				*pline = it.line;
			if(pindex)
				*pindex = it.getIndex();
		}
		if(!it.retreatOverComments())
			return null;

		if(it.getText() == ")")
		{
			// skip over template arguments
			if(it.retreatOverBraces() &&
			   it.getText() == "!" &&
			   it.retreatOverComments() &&
			   it.getTokenType() == TokenCat.Identifier)
				return it.getText();
			return null;
		}
		if(it.getText() == "!")
		{
			// inside template argument list
			if(it.retreatOverComments() &&
			   it.getTokenType() == TokenCat.Identifier)
				return it.getText();
			return null;
		}
		switch(it.getTokenId())
		{
			case TOK___vector:
			mixin(case_TOKs_BasicTypeX);
			mixin(case_TOKs_TemplateSingleArgument);
			{
				LineTokenIterator it2 = it;
				if(it2.retreatOverComments() &&
				   it2.getText() == "!" &&
				   it2.retreatOverComments())
					it = it2;
				break;
			}
			default:
				break;
		}
		if (it.getTokenType() == TokenCat.Identifier)
			return it.getText();
		return null;
	}

	//////////////////////////////////////////////////////////////
	wstring mLastBraceCompletionText;
	int mLastBraceCompletionLine;

	int CompleteOpenBrace(int line, int col, dchar ch)
	{
		// a closing brace is added if
		// - the remaining line is empty
		// - or the rest of the line was inserted by previous automatic additions
		if (mLastBraceCompletionLine != line)
			mLastBraceCompletionText = null;

		wstring text = GetText(line, 0, line, -1);
		if (text.length < col)
			return S_FALSE;

		wstring tail = strip(text[col..$]);
		if (!tail.empty && tail != mLastBraceCompletionText)
			return S_FALSE;

		wchar closech = Lexer.closingBracket(ch);
		TextSpan changedSpan;
		if (int rc = mBuffer.ReplaceLines(line, col, line, col, &closech, 1, &changedSpan))
			return rc;

		mLastBraceCompletionText = closech ~ mLastBraceCompletionText;
		mLastBraceCompletionLine = line;

		return S_OK;
	}

	int DeleteClosingBrace(ref int line, ref int col, dchar ch)
	{
		// assume the closing brace being already inserted. Remove the subsequent
		// identical brace if it has been inserted by open brace completion
		if (mLastBraceCompletionLine != line || mLastBraceCompletionText.empty)
			return S_FALSE;

		TextSpan changedSpan;
		wstring text = GetText(line, 0, line, -1);
		if (text.length <= col || text[col] != ch || mLastBraceCompletionText[0] != ch)
		{
			if (mLastBraceCompletionText[0] == '\n' &&
				mLastBraceCompletionText.length > 1 && mLastBraceCompletionText[1] == ch)
			{
				wstring ntext = GetText(line + 1, 0, line + 1, -1);
				wstring nt = stripLeft(ntext);
				if (nt.length > 0 && nt[0] == ch)
				{
					wstring t = strip(text);
					if (t.length > 0 && t[$-1] == ch)
					{
						int ncol = ntext.length - nt.length;
						if (t.length == 1)
						{
							// remove empty auto inserted line
							if (int rc = mBuffer.ReplaceLines(line, col, line + 1, ncol + 1, null, 0, &changedSpan))
								return rc;
						}
						else
						{
							// remove just inserted brace and move forward behind existing
							if (int rc = mBuffer.ReplaceLines(line, col - 1, line, col, null, 0, &changedSpan))
								return rc;
							col = ncol + 1;
							line = line + 1;
							mLastBraceCompletionLine = line;
						}
						mLastBraceCompletionText = mLastBraceCompletionText[2..$];
						return S_OK;
					}
				}
			}

			return S_FALSE;
		}

		if (int rc = mBuffer.ReplaceLines(line, col, line, col + 1, null, 0, &changedSpan))
			return rc;

		mLastBraceCompletionText = mLastBraceCompletionText[1..$];
		return S_OK;
	}

	int CompleteQuote(int line, int col, dchar ch)
	{
		if (mLastBraceCompletionLine != line)
			mLastBraceCompletionText = null;

		// a closing quote is added if the cursor is inside a string
		int state = mColorizer.GetLineState(line);
		if(state == -1)
			return S_FALSE;

		// get the lexer state at the current edit position
		wstring text = GetText(line, 0, line, -1);
		if(text.length < col)
			return S_FALSE;

		wstring tail = strip(text[col..$]);
		text = text[0..col];

		uint pos = 0;
		int id = -1;
		while(pos < text.length)
			dLex.scan(state, text, pos, id);

		Lexer.State s = Lexer.scanState(state);
		int nesting = Lexer.nestingLevel(state);
		int tokLevel = Lexer.tokenStringLevel(state);
		int otherState = Lexer.getOtherState(state);

		switch(s)
		{
			case Lexer.State.kStringToken:
			case Lexer.State.kStringCStyle:
			case Lexer.State.kStringWysiwyg:
			case Lexer.State.kStringAltWysiwyg:
			case Lexer.State.kStringDelimited:
				break;
			default:
				return DeleteClosingBrace(line, col, ch);
		}

		// only auto append on end of line
		if (!tail.empty && tail != mLastBraceCompletionText)
			return S_FALSE;

		wstring close;
		close ~= ch;
		TextSpan changedSpan;
		if (int rc = mBuffer.ReplaceLines(line, col, line, col, close.ptr, close.length, &changedSpan))
			return rc;

		mLastBraceCompletionText = close ~ mLastBraceCompletionText;
		mLastBraceCompletionLine = line;
		return S_OK;
	}

	int CompleteLineBreak(int line, int col, ref FormatOptions fmtOpt)
	{
		if (mLastBraceCompletionLine != line - 1)
			return S_FALSE;

		mLastBraceCompletionLine = line;

		if (mLastBraceCompletionText.length && mLastBraceCompletionText[0] == '}')
		{
			wstring newline = "\n"w;
			TextSpan changedSpan;
			if (int rc = mBuffer.ReplaceLines(line, col, line, col, newline.ptr, newline.length, &changedSpan))
				return rc;
			CacheLineIndentInfo cacheInfo;
			if (int rc = ReplaceLineIndent(line + 1, &fmtOpt, cacheInfo))
				return rc;

			mLastBraceCompletionText = newline ~ mLastBraceCompletionText;
		}
		return S_OK;
	}

	int AutoCompleteBrace(ref int line, ref int col, dchar ch, ref FormatOptions fmtOpt)
	{
		if(ch == '\n')
			return CompleteLineBreak(line, col, fmtOpt);

		if(ch == '"' || ch == '`' || ch == '\'')
			return CompleteQuote(line, col, ch);

		if(ch == '(' || ch == '[' || ch == '{')
			return CompleteOpenBrace(line, col, ch);

		return DeleteClosingBrace(line, col, ch);
	}

	//////////////////////////////////////////////////////////////

	class ClippingSource
	{
		Source mSrc;
		int mClipLine;
		int mClipIndex;

		this(Source src)
		{
			mSrc = src;
			mClipLine = int.max;
		}

		void setClip(int line, int idx)
		{
			mClipLine = line;
			mClipIndex = idx;
		}

		int GetLineCount()
		{
			int lines = mSrc.GetLineCount();
			if(lines - 1 > mClipLine)
				lines = mClipLine + 1;
			return lines;
		}

		TokenInfo[] GetLineInfo(int line, wstring *ptext = null)
		{
			if(line > mClipLine)
				return null;
			if(line < mClipLine)
				return mSrc.GetLineInfo(line, ptext);

			wstring text = GetText(line, 0, line, -1);
			if(text.length > mClipIndex)
				text = text[0 .. mClipIndex];
			if(ptext)
				*ptext = text;
			return mSrc.GetLineInfoFromText(line, text);
		}

		int FindLineToken(int line, int idx, out int iState, out uint pos)
		{
			// only used in brace matched search
			return mSrc.FindLineToken(line, idx, iState, pos);
		}
		bool FindOpeningBracketBackward(int line, int tok, out int otherLine, out int otherIndex,
										int* pCountComma = null)
		{
			// no brace matching needed for finding imports
			return mSrc.FindOpeningBracketBackward(line, tok, otherLine, otherIndex, pCountComma);
		}
		bool FindClosingBracketForward(int line, int idx, out int otherLine, out int otherIndex)
		{
			// no brace matching needed for finding imports
			return mSrc.FindClosingBracketForward(line, idx, otherLine, otherIndex);
		}
	}

	wstring GetImportModule(int line, int index, bool clipSource)
	{
		auto clipsrc = new ClippingSource(this);
		if(clipSource)
			clipsrc.setClip(line, index);

		auto lntokIt = _LineTokenIterator!ClippingSource(clipsrc, line, 0);
		while(lntokIt.line < line || (lntokIt.getIndex() <= index && lntokIt.line == line))
			if (!lntokIt.advanceOverComments())
				goto L_eol;
		lntokIt.retreatOverComments();
	L_eol:
		wstring tok = lntokIt.getText();
		while((tok == "static" || tok == "public" || tok == "private")
			  && lntokIt.advanceOverComments())
			tok = lntokIt.getText();

		while(tok != "import" && (tok == "." || dLex.isIdentifier(tok))
			  && lntokIt.retreatOverComments())
			tok = lntokIt.getText();

		auto lntokIt2 = lntokIt;
		while(tok != "import" && (tok == "," || tok == "=" || tok == ":" || tok == "." || dLex.isIdentifier(tok))
			  && lntokIt.retreatOverComments())
		{
			if(tok == ":")
				return null; // no import handling on selective import identifier
			tok = lntokIt.getText();
		}

		if(tok != "import")
			return null;
		lntokIt2.advanceOverComments();
		tok = lntokIt2.getText();
		wstring imp;
		while(tok == "." || dLex.isIdentifier(tok))
		{
			imp ~= tok;
			if(!lntokIt2.advanceOverComments())
				break;
			tok = lntokIt2.getText();
		}
		return imp;
	}

	//////////////////////////////////////////////////////////////

	// create our own task pool to be able to destroy it (it keeps a the
	//  arguments to the last task, so they are never collected)
	__gshared TaskPool parseTaskPool;

	void runTask(T)(T dg)
	{
		import core.thread;

		if(!parseTaskPool)
		{
			int threads = defaultPoolThreads;
			if(threads < 1)
				threads = 1;
			parseTaskPool = new TaskPool(threads);
			parseTaskPool.isDaemon = true;
			parseTaskPool.priority(Thread.PRIORITY_MIN);
		}
		auto task = task(dg);
		parseTaskPool.put(task);
	}

	// outlining and semantic combined to grab the whole text only once
	bool startParsing(bool outline, bool semantic)
	{
		if(mOutliningState > 1)
			finishParsing();

		outline  = outline  && mModificationCountOutlining != mModificationCount && mOutlining && mOutliningState == 0;
		semantic = semantic && mModificationCountSemantic  != mModificationCount && Package.GetGlobalOptions().usesUpdateSemanticModule();

		if(!outline && !semantic)
			return false;

		wstring srctext = GetText(); // should not be read from another thread
		if (semantic)
		{
			bool verbose = (mModificationCountSemantic == -1);
			mModificationCountSemantic = mModificationCount;
			mHasPendingUpdateModule = true;
			auto langsvc = Package.GetLanguageService();
			langsvc.UpdateSemanticModule(this, srctext, verbose, &OnUpdateModule);
		}
		if (outline)
		{
			mParseText = srctext;
			mOutliningState = 1;
			mModificationCountOutlining = mModificationCount;
			runTask(&doParse);
		}
		return true;
	}

	bool ensureCurrentTextParsed()
	{
		return startParsing(false, true);
	}

	extern(D) void OnUpdateModule(uint request, string filename, string parseErrors, vdc.util.TextPos[] binaryIsIn,
								  string tasks, string outline)
	{
		mHasPendingUpdateModule = false;
		if (!Package.GetGlobalOptions().showParseErrors)
			parseErrors = null;
		updateParseErrors(parseErrors);
		mBinaryIsIn = binaryIsIn;
		if(IVsTextColorState colorState = qi_cast!IVsTextColorState(mBuffer))
		{
			scope(exit) release(colorState);
			foreach(pos; mBinaryIsIn)
				colorState.ReColorizeLines(pos.line - 1, pos.line);
		}
		Package.GetErrorProvider().updateTaskItems(filename, parseErrors);
		Package.GetTaskProvider().updateTaskItems(filename, tasks);

		if (Package.GetGlobalOptions().semanticHighlighting)
			Package.GetLanguageService().GetIdentifierTypes(this, 0, -1, Package.GetGlobalOptions().semanticResolveFields,
															&OnUpdateIdentifierTypes);

		if (mCodeWinMgr && mCodeWinMgr.mNavBar)
			mCodeWinMgr.mNavBar.UpdateFromSource(outline);
	}

	bool parseErrorEntry(string e, ref ParseError error)
	{
		auto idx = indexOf(e, ':');
		if(idx > 0)
		{
			string[] num = split(e[0..idx], ",");
			if(num.length == 4)
			{
				try
				{
					error.span.iStartLine  = parse!int(num[0]);
					error.span.iStartIndex = parse!int(num[1]);
					error.span.iEndLine    = parse!int(num[2]);
					error.span.iEndIndex   = parse!int(num[3]);
					error.msg = e[idx+1..$].replace("\a", "\n");
					return true;
				}
				catch(ConvException)
				{
				}
			}
		}
		return false;
	}

	void updateParseErrors(string err)
	{
		string[] errs = splitLines(err);
		mParseErrors = mParseErrors.init;
		foreach(e; errs)
		{
			ParseError error;
			if (parseErrorEntry(e, error))
			{
				if (error.span.iStartLine == error.span.iEndLine && error.span.iEndIndex <= error.span.iStartIndex + 1)
				{
					// figure the length of the span from the lexer by using the full token
					int line = error.span.iStartLine - 1;
					int iState = mColorizer.GetLineState(line);
					wstring text = GetText(line, 0, line, -1);
					uint pos = 0;
					wstring ident;
					while(pos < text.length)
					{
						uint ppos = pos;
						int type = dLex.scan(iState, text, pos);
						if (pos > error.span.iStartIndex)
						{
							error.span.iStartIndex = ppos;
							error.span.iEndIndex = pos;
							break;
						}
					}
				}
				mParseErrors ~= error;
			}
		}
		finishParseErrors();
	}

	void clearParseErrors()
	{
		void removeMarkers(int type)
		{
			IVsEnumLineMarkers pEnum;
			if(mBuffer.EnumMarkers(0, 0, 0, 0, type, EM_ENTIREBUFFER, &pEnum) == S_OK)
			{
				scope(exit) release(pEnum);
				IVsTextLineMarker marker;
				while(pEnum.Next(&marker) == S_OK)
				{
					marker.Invalidate();
					marker.Release();
				}
			}
		}
		removeMarkers(MARKER_CODESENSE_ERROR);
		removeMarkers(MARKER_OTHER_ERROR);
		removeMarkers(MARKER_WARNING);
	}

	void finishParseErrors()
	{
		string file = GetFileName();
		Config cfg = getProjectConfig(file, true);
		if(!cfg)
			cfg = getCurrentStartupConfig();
		auto opts = cfg ? cfg.GetProjectOptions() : null;

		clearParseErrors();
		for(int i = 0; i < mParseErrors.length; i++)
		{
			auto span = mParseErrors[i].span;
			int mtype = MARKER_CODESENSE_ERROR;
			if (mParseErrors[i].msg.startsWith("Warning:") && (!opts || opts.infowarnings))
				mtype = MARKER_WARNING;
			else if (mParseErrors[i].msg.startsWith("Deprecation:") && (!opts || !opts.errDeprecated))
				mtype = MARKER_OTHER_ERROR;
			else if (mParseErrors[i].msg.startsWith("Info:"))
				mtype = MARKER_WARNING;
			IVsTextLineMarker marker;
			mBuffer.CreateLineMarker(mtype, span.iStartLine - 1, span.iStartIndex,
									 span.iEndLine - 1, span.iEndIndex, this, &marker);
			if (marker && Package.GetGlobalOptions().usesQuickInfoTooltips())
			{
				// do not show tooltip error via GetTipText, but through RequestTooltip
				DWORD visualStyle;
				marker.GetVisualStyle(&visualStyle);
				visualStyle &= ~MV_TIP_FOR_BODY;
				marker.SetVisualStyle(visualStyle);
			}
			//release(marker);
		}
	}

	enum kReferenceMarkerType = MARKER_REFACTORING_FIELD;

	void clearReferenceMarker()
	{
		auto stream = qi_cast!IVsTextStream(mBuffer);
		if (stream)
		{
			IVsEnumStreamMarkers pEnum;
			if(stream.EnumMarkers(0, 0, kReferenceMarkerType, EM_ENTIREBUFFER, &pEnum) == S_OK)
			{
				scope(exit) release(pEnum);
				IVsTextStreamMarker marker;
				while(pEnum.Next(&marker) == S_OK)
				{
					marker.Invalidate();
					marker.Release();
				}
			}
		}
	}

	void updateReferenceMarker(string[] exps)
	{
		clearReferenceMarker();

		if (exps.length > 0)
		{
			auto stream = qi_cast!IVsTextStream(mBuffer);
			if (stream)
			{
				foreach(e; exps)
				{
					ParseError error;
					if (parseErrorEntry(e, error))
					{
						int spos, epos;
						if (stream.GetPositionOfLineIndex(error.span.iStartLine - 1, error.span.iStartIndex, &spos) == S_OK &&
							stream.GetPositionOfLineIndex(error.span.iEndLine   - 1, error.span.iEndIndex,   &epos) == S_OK)
						{
							IVsTextStreamMarker marker;
							stream.CreateStreamMarker(kReferenceMarkerType, spos, epos - spos, this, &marker);
						}
					}
				}
				release(stream);
			}
		}
	}

	extern(D) void OnUpdateIdentifierTypes(uint request, string filename, string identifierTypes)
	{
		bool typesChanged = updateIdentifierTypes(identifierTypes);
		if (typesChanged)
		{
			if(IVsTextColorState colorState = qi_cast!IVsTextColorState(mBuffer))
			{
				scope(exit) release(colorState);
				colorState.ReColorizeLines(-1, -1);
			}
		}
	}

	bool updateIdentifierTypes(string identifierTypes)
	{
		bool changed = mIdentifierTypes.length > 0; // could be more precise
		string[] idtypes = splitLines(identifierTypes);
		mIdentifierTypes = mIdentifierTypes.init;
		foreach(idt; idtypes)
		{
			auto idx = indexOf(idt, ':');
			if(idx > 0)
			{
				string ident = idt[0..idx];
				IdentifierType[] idspans;
				string[] spans = split(idt[idx+1..$], ";");
				foreach(sp; spans)
				{
					string[] num = split(sp, ",");
					try
					{
						IdentifierType it;
						if(num.length >= 3)
						{
							it.type = parse!int(num[0]);
							it.line = parse!int(num[1]);
							it.col  = parse!int(num[2]);
							idspans ~= it;
						}
						else if(num.length == 1)
						{
							it.type = parse!int(num[0]);
							it.line = 0;
							it.col  = 0;
							idspans ~= it;
						}
					}
					catch(ConvException)
					{
					}
				}
				if (idspans.length)
					mIdentifierTypes[to!wstring(ident)] = idspans;
			}
		}
		changed = changed || mIdentifierTypes.length > 0;
		return changed;
	}

	int convertTypeRefToColor(uint kind)
	{
		switch (kind)
		{
			case TypeReferenceKind.Unknown:           return TokenColor.Identifier;
			case TypeReferenceKind.Interface:         return TokenColor.Interface;
			case TypeReferenceKind.Enum:              return TokenColor.Enum;
			case TypeReferenceKind.EnumValue:         return TokenColor.EnumValue;
			case TypeReferenceKind.Template:          return TokenColor.Template;
			case TypeReferenceKind.Class:             return TokenColor.Class;
			case TypeReferenceKind.Struct:            return TokenColor.Struct;
			case TypeReferenceKind.Union:             return TokenColor.Union;
			case TypeReferenceKind.TemplateTypeParameter: return TokenColor.TemplateTypeParameter;
			case TypeReferenceKind.Constant:          return TokenColor.Constant;
			case TypeReferenceKind.LocalVariable:     return TokenColor.LocalVariable;
			case TypeReferenceKind.ParameterVariable: return TokenColor.ParameterVariable;
			case TypeReferenceKind.TLSVariable:       return TokenColor.TLSVariable;
			case TypeReferenceKind.SharedVariable:    return TokenColor.SharedVariable;
			case TypeReferenceKind.GSharedVariable:   return TokenColor.GSharedVariable;
			case TypeReferenceKind.MemberVariable:    return TokenColor.MemberVariable;
			case TypeReferenceKind.Variable:          return TokenColor.Variable;
			case TypeReferenceKind.Alias:             return TokenColor.Alias;
			case TypeReferenceKind.Module:            return TokenColor.Module;
			case TypeReferenceKind.Function:          return TokenColor.Function;
			case TypeReferenceKind.Method:            return TokenColor.Method;
			case TypeReferenceKind.BasicType:         return TokenColor.BasicType;
			default:                                  return TokenColor.Identifier;
		}
	}

	int getIdentifierColor(wstring id, int line, int col)
	{
		if (id.length > 1 && id[0] == '@') // @UDA lexed as single token
		{
			id = id[1..$];
			col++;
		}
		auto pit = id in mIdentifierTypes;
		if (!pit)
			return TokenColor.Identifier;

		IdentifierType it = IdentifierType(line, col, 0);
		auto a = assumeSorted!"a.line < b.line || (a.line == b.line && a.col < b.col)"(*pit);
		auto sections = a.trisect(it);
		uint type;
		if (!sections[1].empty)
			type = sections[1].front.type;
		else if (!sections[0].empty)
			type = sections[0].back.type;
		else
			type = sections[2].front.type;
		return convertTypeRefToColor(type);
	}

	bool finishParsing()
	{
		if(mOutlining)
		{
			if(mStopOutlining)
			{
				mOutlineRegions = mOutlineRegions.init;
				mOutlining = false;
			}
			if(mModificationCountOutlining == mModificationCount)
			{
				if(auto session = GetHiddenTextSession())
					if(DiffRegions(session, mOutlineRegions))
						session.AddHiddenRegions(chrNonUndoable, mOutlineRegions.length, mOutlineRegions.ptr, null);
				mOutlineRegions = mOutlineRegions.init;
			}
		}

		mParseText = null;
		mOutliningState = 0;
		ReColorizeLines(0, -1);
		return true;
	}

	void doParse()
	{
		if(mOutlining)
		{
			mOutlineRegions = CreateOutlineRegions(mParseText, hrsExpanded);
		}
		mOutliningState = 2;
	}

	int hasParseError(ParserSpan span)
	{
		for(int i = 0; i < mParseErrors.length; i++)
			if(spanContains(span, mParseErrors[i].span.iStartLine-1, mParseErrors[i].span.iStartIndex))
			{
				if (mParseErrors[i].msg.startsWith("Warning:"))
					return 2;
				if (mParseErrors[i].msg.startsWith("Deprecation:"))
					return 3;
				if (mParseErrors[i].msg.startsWith("Info:"))
					return 3;
				return 1;
			}
		return 0;
	}

	string getParseError(int line, int index)
	{
		for(int i = 0; i < mParseErrors.length; i++)
			if(spanContains(mParseErrors[i].span, line+1, index))
				return mParseErrors[i].msg;
		return null;
	}

	//////////////////////////////////////////////////////////////

	ExpansionProvider GetExpansionProvider()
	{
		if(!mExpansionProvider)
			mExpansionProvider = addref(newCom!ExpansionProvider(this));
		return mExpansionProvider;
	}


	IVsTextLines GetTextLines() { return mBuffer; }

	CompletionSet GetCompletionSet()
	{
		if(!mCompletionSet)
			mCompletionSet = addref(newCom!CompletionSet(this));
		return mCompletionSet;
	}

	MethodData GetMethodData()
	{
		if(!mMethodData)
			mMethodData = addref(newCom!MethodData());
		return mMethodData;
	}

	bool IsCompletorActive()
	{
		if (mCompletionSet && mCompletionSet.isActive())
			return true;
		return false;
	}

	bool IsMethodTipActive()
	{
		if (mMethodData && mMethodData.mDisplayed)
			return true;
		return false;
	}

	void DismissCompletor()
	{
		if (mCompletionSet && mCompletionSet.mDisplayed)
			mCompletionSet.Close();
	}
	void DismissMethodTip()
	{
		if (mMethodData && mMethodData.mDisplayed)
			mMethodData.Close();
	}

	bool EnableFormatSelection() { return true; }

}

///////////////////////////////////////////////////////////////////////////////

class EnumProximityExpressions : DComObject, IVsEnumBSTR
{
	wstring[] mExpressions;
	int mPos;

	this(Source src, int iLine, int iCol, int cLines)
	{
		int begLine = iLine < cLines ? 0 : iLine - cLines;
		for(int line = begLine; line < iLine + cLines; line++)
		{
			int iState = src.mColorizer.GetLineState(line);
			if(iState == -1)
				break;

			wstring text = src.GetText(line, 0, line, -1);
			uint pos = 0;
			wstring ident;
			while(pos < text.length)
			{
				uint ppos = pos;
				int type = dLex.scan(iState, text, pos);
				wstring txt = text[ppos .. pos];
				if(type == TokenCat.Identifier || txt == "this"w)
				{
					ident ~= txt;
					if(ident.length > 4 && ident[0..5] == "this."w)
						ident = "this->"w ~ ident[5..$];
					addunique(mExpressions, ident);
//					if(!ident.startsWith("this."w))
//						addunique(mExpressions, "this."w ~ ident);
				}
				else if (type == TokenCat.Operator && txt == "."w)
					ident ~= "."w;
				else
					ident = ""w;
			}
		}
		if(arrIndex(mExpressions, "this"w) < 0)
			mExpressions ~= "this"w;
	}

	this(EnumProximityExpressions epe)
	{
		mExpressions = epe.mExpressions;
		mPos = epe.mPos;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsEnumBSTR) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsEnumBSTR
	override int Next(in ULONG celt, BSTR *rgelt, ULONG *pceltFetched)
	{
		if(mPos + celt > mExpressions.length)
			return E_FAIL;

		for(int i = 0; i < celt; i++)
			rgelt[i] = allocwBSTR(mExpressions[mPos + i]);

		mPos += celt;
		if(pceltFetched)
			*pceltFetched = celt;

		return S_OK;
	}

	override int Skip(in ULONG celt)
	{
		mPos += celt;
		return S_OK;
	}

	override int Reset()
	{
		mPos = 0;
		return S_OK;
	}

	override int Clone(IVsEnumBSTR* ppenum)
	{
		auto clone = newCom!EnumProximityExpressions(this);
		*ppenum = addref(clone);
		return S_OK;
	}

	override int GetCount(ULONG *pceltCount)
	{
		*pceltCount = mExpressions.length;
		return S_OK;
	}
}

///////////////////////////////////////////////////////////////////////

version(unittest)
{
	mixin template ImplementInterface(I)
	{
		static foreach(i, m; __traits(allMembers, I))
		{
			static if (is(typeof(mixin(m)))) // filter IUnknown?
			{
				mixin("enum type" ~ i.stringof ~ " = typeof(" ~ m ~ ").stringof;");
				//pragma(msg, m, " ", mixin("type" ~ i.stringof));
				static if (mixin("type" ~ i.stringof).length > 21)
					static if (mixin("type" ~ i.stringof)[0..21] == "extern (Windows) int(")
						mixin("override HRESULT " ~ m ~ mixin("type" ~ i.stringof)[20..$] ~ " { return E_NOTIMPL; }");
			}
		}
	}
	class TextLines : DComObject, IVsTextLines
	{
		mixin ImplementInterface!IVsTextLines;

		HRESULT GetLineText(
            in int       iStartLine,  // starting line
            in CharIndex iStartIndex, // starting character index within the line (must be <= length of line)
            in int       iEndLine,    // ending line
            in CharIndex iEndIndex,   // ending character index within the line (must be <= length of line)
            /+[out]+/ BSTR *    pbstrBuf)
		{
			if (iStartLine >= text.length)
				return E_FAIL;
			if (iStartIndex > text[iStartLine].length)
				return E_FAIL;
			int endLine = iEndLine < 0 ? text.length - 1 : iEndLine;
			if (endLine >= text.length)
				return E_FAIL;
			int endIndex = iEndIndex < 0 ? text[endLine].length : iEndIndex;
			if (endIndex > text[endLine].length)
				return E_FAIL;

			if (iStartLine == endLine)
			{
				if (endIndex < iStartIndex)
					return E_FAIL;
				*pbstrBuf = allocwBSTR(text[iStartLine][iStartIndex..endIndex]);
			}
			else
			{
				auto s = text[iStartLine][iStartIndex .. $];
				for(int ln = iStartLine + 1; ln < endLine; ln++)
					s ~= "\n"w ~ text[ln];
				s ~= "\n"w ~ text[endLine][0..endIndex];
				*pbstrBuf = allocwBSTR(s);
			}
			return S_OK;
		}

		HRESULT GetLineCount (/+[out]+/ int *piLines)
		{
			*piLines = text.length;
			return S_OK;
		};
		HRESULT GetLastLineIndex (/+[out]+/ int *piLine,
		                          /+[out]+/ int *piIndex)
		{
			*piLine = text.length - 1;
			*piIndex = text.length > 0 ? text[$-1].length : -1;
			return S_OK;
		};
		HRESULT GetLengthOfLine (in int iLine,
		                         int *piLength)
		{
			if (iLine >= text.length)
				return E_FAIL;
			*piLength = text[iLine].length;
			return S_OK;
		}

		override HRESULT ReplaceLines (
            in int       iStartLine,  // starting line
            in CharIndex iStartIndex, // starting character index within the line (must be <= length of line)
            in int       iEndLine,    // ending line
            in CharIndex iEndIndex,   // ending character index within the line (must be <= length of line)
            in LPCWSTR   pszText,     // text to insert, if any
            in int       iNewLen,     // # of chars to insert, if any
            TextSpan *pChangedSpan)  // range of characters changed
		{
			assert(iStartLine == iEndLine);
			if (iStartLine >= text.length)
				return E_FAIL;
			if (iEndIndex < iStartIndex)
				return E_FAIL;
			if (iEndIndex > text[iStartLine].length)
				return E_FAIL;
			text[iStartLine] = text[iStartLine][0..iStartIndex] ~ pszText[0..iNewLen] ~ text[iStartLine][iEndIndex..$];
			return S_OK;
		}

		const(wchar)[][] text;
	}

	void testIndent(const(wchar)[] txt, const(wchar)[] exp, bool indentCase)
	{
		Package pkg = newCom!Package();
		TextLines textLines = newCom!TextLines();
		textLines.text = splitLines(txt);
		Source src = newCom!Source(textLines);
		int lines = textLines.text.length;

		FormatOptions fmtOpt;
		fmtOpt.tabSize = 4;
		fmtOpt.indentSize = 4;
		fmtOpt.insertTabs = true;
		fmtOpt.indentCase = indentCase;

		Source.CacheLineIndentInfo cacheInfo;
		for(int line = 0; line < lines; line++)
		{
			int rc = src.ReplaceLineIndent(line, &fmtOpt, cacheInfo);
			assert(!FAILED(rc));
		}
		const(wchar)[] ntxt = join(textLines.text, "\n"w);
		exp = stripRight(translate(exp, null, "\r"w)); // remove \r and trailing \n
		assert(ntxt == exp);

		src.Dispose();
		pkg.Dispose();
	}
}

//////////////////////////////////
unittest
{
	const(wchar)[] txt = q{
void foo()
 {
  switch(n)
  {
  case 1:
   return;
  case 2:
  break;
  }
 }
};
	const(wchar)[] exp = q{
void foo()
{
	switch(n)
	{
		case 1:
			return;
		case 2:
			break;
	}
}
};
	testIndent(txt, exp, true);

	const(wchar)[] exp2 = q{
void foo()
{
	switch(n)
	{
	case 1:
		return;
	case 2:
		break;
	}
}
};
	testIndent(txt, exp2, false);
}

//////////////////////////////////
unittest
{
	const(wchar)[] txt = q{
private enum Enum : int
{
 E1,
 E2,
 E3 = E1 +
 E2,
 E4
}
};
	const(wchar)[] exp = q{
private enum Enum : int
{
	E1,
	E2,
	E3 = E1 +
		E2,
	E4
}
};
	testIndent(txt, exp, true);
}

//////////////////////////////////
unittest
{
	const(wchar)[] txt = q{
auto var1,
var2 = () { return 1; },
var3;
const LanguageProperty[] g_languageProperties =
[
 { "RequestStockColors"w, 0 },
 { "ShowCompletion"w, 1 },
];
const int[][] arr =
[
 [ 1, 2, 3, 4 ],
 [ 1, 2, 3, 4,
 5, 6, 7, 8 ],
 [ 1, 2, 3, 4 ],
];
void fun( int a,
int b)
{
int x = a,
y = b;
return fun( a,
b );
}
};
	const(wchar)[] exp = q{
auto var1,
	var2 = () { return 1; },
	var3;
const LanguageProperty[] g_languageProperties =
[
	{ "RequestStockColors"w, 0 },
	{ "ShowCompletion"w, 1 },
];
const int[][] arr =
[
	[ 1, 2, 3, 4 ],
	[ 1, 2, 3, 4,
	  5, 6, 7, 8 ],
	[ 1, 2, 3, 4 ],
];
void fun( int a,
		  int b)
{
	int x = a,
		y = b;
	return fun( a,
				b );
}
};
	testIndent(txt, exp, true);
}
