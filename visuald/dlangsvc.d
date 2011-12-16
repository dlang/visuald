// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

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

import vdc.lexer;

import ast = vdc.ast.all;
static import vdc.util;
import vdc.parser.engine;

import stdext.array;
import stdext.string;

import std.string;
import std.ascii;
import std.utf;
import std.conv;
import std.algorithm;
import std.array;

import std.parallelism;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.textmgr90;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.singlefileeditor;
import sdk.vsi.fpstfmt;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;

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
		mPackage = pkg;
		mUpdateSolutionEvents = new UpdateSolutionEvents(this);
	}

	~this()
	{
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
		foreach(Source src; mSources)
			if(auto parser = src.mParser)
				parser.abort = true;
		
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
			CodeWindowManager mgr = new CodeWindowManager(this, pCodeWin, src);
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
		return E_NOTIMPL;
	}

	override HRESULT GetLanguageName(BSTR* bstrName)
	{
		return E_NOTIMPL;
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
		return S_OK;
	}

	override HRESULT GetProximityExpressions(IVsTextBuffer pBuffer, in int iLine, in int iCol, in int cLines, IVsEnumBSTR* ppEnum)
	{
		auto text = ComPtr!(IVsTextLines)(pBuffer);
		if(!text)
			return E_FAIL;
		Source src = GetSource(text);
		if(!src)
			return E_FAIL;

		*ppEnum = addref(new EnumProximityExpressions(src, iLine, iCol, cLines));
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
	
	// delete <VisualStudio-User-Root>\FontAndColors\Cache\{A27B4E24-A735-4D1D-B8E7-9716E1E3D8E0}\Version
	// if the list of colorableItems changes
	
	static void shared_static_this()
	{
		colorableItems = [
			// The first 6 items in this list MUST be these default items.
			new ColorableItem("Keyword",    CI_BLUE,        CI_USERTEXT_BK),
			new ColorableItem("Comment",    CI_DARKGREEN,   CI_USERTEXT_BK),
			new ColorableItem("Identifier", CI_USERTEXT_FG, CI_USERTEXT_BK),
			new ColorableItem("String",     CI_MAROON,      CI_USERTEXT_BK),
			new ColorableItem("Number",     CI_USERTEXT_FG, CI_USERTEXT_BK),
			new ColorableItem("Text",       CI_USERTEXT_FG, CI_USERTEXT_BK),
			
			// Visual D specific (must match Lexer.TokenCat)
			new ColorableItem("Visual D Operator",         CI_USERTEXT_FG, CI_USERTEXT_BK),
			new ColorableItem("Visual D Register",         CI_PURPLE,      CI_USERTEXT_BK),
			new ColorableItem("Visual D Mnemonic",         CI_AQUAMARINE,  CI_USERTEXT_BK),
			new ColorableItem("Visual D Type",                -1,          CI_USERTEXT_BK, RGB(0, 0, 160)),
			new ColorableItem("Visual D Predefined Version",  -1,          CI_USERTEXT_BK, RGB(160, 0, 0)),
				
			new ColorableItem("Visual D Disabled Keyword",    -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
			new ColorableItem("Visual D Disabled Comment",    -1,          CI_USERTEXT_BK, RGB(96, 128, 96)),
			new ColorableItem("Visual D Disabled Identifier", CI_DARKGRAY, CI_USERTEXT_BK),
			new ColorableItem("Visual D Disabled String",     -1,          CI_USERTEXT_BK, RGB(192, 160, 160)),
			new ColorableItem("Visual D Disabled Number",     CI_DARKGRAY, CI_USERTEXT_BK),
			new ColorableItem("Visual D Disabled Text",       CI_DARKGRAY, CI_USERTEXT_BK),
			new ColorableItem("Visual D Disabled Operator",   CI_DARKGRAY, CI_USERTEXT_BK),
			new ColorableItem("Visual D Disabled Register",   -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
			new ColorableItem("Visual D Disabled Mnemonic",   -1,          CI_USERTEXT_BK, RGB(128, 160, 224)),
			new ColorableItem("Visual D Disabled Type",       -1,          CI_USERTEXT_BK, RGB(64, 112, 208)),
			new ColorableItem("Visual D Disabled Version",    -1,          CI_USERTEXT_BK, RGB(160, 128, 128)),

			new ColorableItem("Visual D Token String Keyword",    -1,      CI_USERTEXT_BK, RGB(160,0,128)),
			new ColorableItem("Visual D Token String Comment",    -1,      CI_USERTEXT_BK, RGB(128,160,80)),
			new ColorableItem("Visual D Token String Identifier", -1,      CI_USERTEXT_BK, RGB(128,32,32)),
			new ColorableItem("Visual D Token String String",     -1,      CI_USERTEXT_BK, RGB(255,64,64)),
			new ColorableItem("Visual D Token String Number",     -1,      CI_USERTEXT_BK, RGB(128,32,32)),
			new ColorableItem("Visual D Token String Text",       -1,      CI_USERTEXT_BK, RGB(128,32,32)),
			new ColorableItem("Visual D Token String Operator",   -1,      CI_USERTEXT_BK, RGB(128,32,32)),
			new ColorableItem("Visual D Token String Register",   -1,      CI_USERTEXT_BK, RGB(192,0,128)),
			new ColorableItem("Visual D Token String Mnemonic",   -1,      CI_USERTEXT_BK, RGB(192,0,128)),
			new ColorableItem("Visual D Token String Type",       -1,      CI_USERTEXT_BK, RGB(112,0,80)),
			new ColorableItem("Visual D Token String Version",    -1,      CI_USERTEXT_BK, RGB(224, 0, 0)),
		];
	};
	static void shared_static_dtor()
	{
		clear(colorableItems); // to keep GC leak detection happy
		Source.parseTaskPool = null;
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
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	override HRESULT GetFormatFilterList(BSTR* pbstrFilterList)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
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
		foreach(src; mSources)
			src.mColorizer.OnConfigModified();
		
		return S_OK;
	}

	// IVsOutliningCapableLanguage ///////////////////////////////
	HRESULT CollapseToDefinitions(/+[in]+/ IVsTextLines pTextLines,  // the buffer in question
								  /+[in]+/ IVsOutliningSession pSession)
	{
		GetSource(pTextLines).mOutlining = true;
		if(auto session = qi_cast!IVsHiddenTextSession(pSession))
		{
			GetSource(pTextLines).UpdateOutlining(session, hrsDefault);
			GetSource(pTextLines).CollapseAllHiddenRegions(session, true);
		}
		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	private Source cdwLastSource;
	private int cdwLastLine, cdwLastColumn;
	public ViewFilter mLastActiveView;
	
	bool tryJumpToDefinitionInCodeWindow(Source src, int line, int col)
	{
		if (cdwLastSource == src && cdwLastLine == line && cdwLastColumn == col)
			return false;

		cdwLastSource = src;
		cdwLastLine = line;
		cdwLastColumn = col;

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
		
		return jumpToDefinitionInCodeWindow("", abspath, defs[0].line, 0);
	}
	
	//////////////////////////////////////////////////////////////
	bool OnIdle()
	{
		for(int i = 0; i < mSources.length; i++)
			if(mSources[i].OnIdle())
				return true;
		foreach(CodeWindowManager mgr; mCodeWinMgrs)
			if(mgr.OnIdle())
				return true;
		
		if(mLastActiveView && mLastActiveView.mView)
		{
			int line, idx;
			mLastActiveView.mView.GetCaretPos(&line, &idx);
			if(tryJumpToDefinitionInCodeWindow(mLastActiveView.mCodeWinMgr.mSource, line, idx))
				return true;
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
		src = new Source(buffer);
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

private:
	Package              mPackage;
	Source[]             mSources;
	CodeWindowManager[]  mCodeWinMgrs;
	DBGMODE              mDbgMode;
	
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

	this(LanguageService langSvc, IVsCodeWindow pCodeWin, Source source)
	{
		mCodeWin = pCodeWin;
		if(mCodeWin)
		{
			mCodeWin.AddRef();
		}
		mSource = addref(source);
		mLangSvc = langSvc;
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

		// attach view filter to secondary view.
		textView = null;
		if(mCodeWin.GetSecondaryView(&textView) != S_OK)
			return E_FAIL;
		if(textView)
			OnNewView(textView);

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

		ViewFilter vf = new ViewFilter(this, pView);
		mViewFilters ~= vf;
		return S_OK;
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

bool jumpToDefinitionInCodeWindow(string symbol, string filename, int line, int col)
{
	IVsCodeDefView cdv = queryService!(SVsCodeDefView,IVsCodeDefView);
	if (cdv is null)
		return false;
	if (cdv.IsVisible() != S_OK)
		return false;

	CodeDefViewContext context = new CodeDefViewContext(symbol, filename, line, col);
	cdv.SetContext(context);
	return true;
}

///////////////////////////////////////////////////////////////////////////////

int GetUserPreferences(LANGPREFERENCES *langPrefs)
{
	IVsTextManager textmgr = queryService!(VsTextManager, IVsTextManager);
	if(!textmgr)
		return E_FAIL;
	scope(exit) release(textmgr);
	
	langPrefs.guidLang = g_languageCLSID;
	if(int rc = textmgr.GetUserPreferences(null, null, langPrefs, null))
		return rc;
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

class Source : DisposingComObject, IVsUserDataEvents, IVsTextLinesEvents, IVsTextMarkerClient
{
	Colorizer mColorizer;
	IVsTextLines mBuffer;
	CompletionSet mCompletionSet;
	MethodData mMethodData;
	ExpansionProvider mExpansionProvider;
	SourceEvents mSourceEvents;
	bool mOutlining;
	bool mStopOutlining;
	bool mVerifiedEncoding;
	IVsHiddenTextSession mHiddenTextSession;
	
	static struct LineChange { int oldLine, newLine; }
	LineChange[] mLineChanges;
	TextLineChange mLastTextLineChange;

	Parser mParser;
	ast.Module mAST;
	ParseError[] mParseErrors;
	wstring mParseText;
	NewHiddenRegion[] mOutlineRegions;

	int mParsingState;
	int mModificationCountAST;
	int mModificationCount;

	this(IVsTextLines buffer)
	{
		mBuffer = addref(buffer);
		mColorizer = new Colorizer(this);
		mSourceEvents = new SourceEvents(this, mBuffer);

		mOutlining = Package.GetGlobalOptions().autoOutlining;
		mModificationCountAST = -1;
	}
	~this()
	{
	}

	override void Dispose()
	{
		mExpansionProvider = release(mExpansionProvider);
		DismissCompletor();
		DismissMethodTip();
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
		if(mOutlining)
			CheckOutlining(pTextLineChange);
		return mColorizer.OnLinesChanged(pTextLineChange.iStartLine, pTextLineChange.iOldEndLine, pTextLineChange.iNewEndLine, fLast != 0);
	}
    
	void ClearLineChanges()
	{
		mLineChanges = mLineChanges.init;
	}
	
	override int OnChangeLineAttributes(in int iFirstLine, in int iLastLine)
	{
		return S_OK;
	}

	HRESULT ReColorizeLines (int iTopLine, int iBottomLine)
	{
		if(IVsTextColorState colorState = qi_cast!IVsTextColorState(mBuffer))
		{
			scope(exit) release(colorState);
			if(iBottomLine == -1)
				iBottomLine = GetLineCount() - 1;
			colorState.ReColorizeLines (iTopLine, iBottomLine);
		}
		return S_OK;
	}

	int adjustLineNumberSinceLastBuild(int line)
	{
		foreach(ref chg; mLineChanges)
			if(line >= chg.oldLine)
				line += chg.newLine - chg.oldLine;
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
		if(startParsing())
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
				htm.CreateHiddenTextSession(0, mBuffer, null, &mHiddenTextSession);
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
		foreach(txt; splitter(source, '\n'))
		{
			if(mModificationCountAST != mModificationCount)
				break;

			//wstring txt = GetText(ln, 0, ln, -1);
			if(txt.length > 0 && txt[$-1] == '\r')
				txt = txt[0..$-1];
			
			uint pos = 0;
			bool isSpaceOrComment = true;
			bool isComment = false;
			while(pos < txt.length)
			{
				uint prevpos = pos;
				int col = dLex.scan(state, txt, pos);
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
				isComment = isComment || (col == TokenCat.Comment);
				isSpaceOrComment = isSpaceOrComment && Lexer.isCommentOrSpace(col, txt[prevpos .. pos]);
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
		while(endIdx < txt.length && dLex.isIdentifierCharOrDigit(txt[endIdx]))
			endIdx++;
		while(startIdx > 0 && dLex.isIdentifierCharOrDigit(txt[startIdx-1]))
			startIdx--;
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
		TokenInfo[] lineInfo;

		int iState = mColorizer.GetLineState(line);
		if(iState == -1)
			return lineInfo;

		wstring text = GetText(line, 0, line, -1);
		if(ptext)
			*ptext = text;
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
	int ReplaceLineIndent(int line, LANGPREFERENCES* langPrefs)
	{
		wstring linetxt = GetText(line, 0, line, -1);
		int p, orgn = countVisualSpaces(linetxt, langPrefs.uTabSize, &p);
		int n = 0;
		if(p < linetxt.length)
			n = CalcLineIndent(line, 0, langPrefs);
		if(n < 0)
			n = 0;
		if(n == orgn)
			return S_OK;

		return doReplaceLineIndent(line, p, n, langPrefs);
	}
	
	int doReplaceLineIndent(int line, int idx, int n, LANGPREFERENCES* langPrefs)
	{
		int tabsz = (langPrefs.fInsertTabs && langPrefs.uTabSize > 0 ? langPrefs.uTabSize : n + 1);
		string spc = replicate("\t", n / tabsz) ~ replicate(" ", n % tabsz);
		wstring wspc = toUTF16(spc);

		TextSpan changedSpan;
		return mBuffer.ReplaceLines(line, 0, line, idx, wspc.ptr, wspc.length, &changedSpan);
	}

	struct LineTokenIterator
	{
		int line;
		int tok;
		Source src;
		
		wstring lineText;
		TokenInfo[] lineInfo;
		
		this(Source _src, int _line, int _tok)
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

		bool onCommentOrSpace()
		{
			return (lineInfo[tok].type == TokenCat.Comment ||
			       (lineInfo[tok].type == TokenCat.Text && isWhite(lineText[lineInfo[tok].StartIndex])));
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

		wstring getPrevToken(int n = 1)
		{
			LineTokenIterator it = this;
			foreach(i; 0..n)
				it.retreatOverComments();
			return it.getText();
		}
		wstring getNextToken(int n = 1)
		{
			LineTokenIterator it = this;
			foreach(i; 0..n)
				it.advanceOverComments();
			return it.getText();
		}
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

	int CalcLineIndent(int line, dchar ch, LANGPREFERENCES* langPrefs)
	{
		LineTokenIterator lntokIt = LineTokenIterator(this, line, 0);
		wstring startTok;
		if(ch != 0)
			startTok ~= ch;
		else
		{
			lntokIt.ensureNoComment(false);
			startTok = lntokIt.getText();
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
					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize;
				txt = lntokIt.getText();
				if(txt == "if")
					--cntIf;
				else if(txt == "else")
					++cntIf;
			}
			return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
		}
		bool findOpenBrace(ref LineTokenIterator it)
		{
			do
			{
				txt = it.getText();
				if(txt == "{" || txt == "[" || txt == "(")
					return true;
			}
			while(it.retreatOverBraces());
			return false;
		}
		
		int findPreviousCaseIndent()
		{
			do
			{
				txt = lntokIt.getText();
				if(txt == "{" || txt == "[") // emergency exit on pending opening brace
					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize;
				if(txt == "case" || txt == "default") // emergency exit on pending opening brace
					if(lntokIt.getPrevToken() != "goto")
						break;
			}
			while(lntokIt.retreatOverBraces());
			return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
		}

		int findCommaIndent()
		{
			wstring txt;
			int commaIndent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
			do
			{
				txt = lntokIt.getText();
				if(txt == "(")
					return visiblePosition(lntokIt.lineText, langPrefs.uTabSize, lntokIt.getIndex() + 1);
				if(txt == "[")
					return commaIndent;
				if(txt == ",")
					commaIndent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
				if(txt == "{")
				{
					// figure out if this is a struct initializer, enum declaration or a statement group
					if(lntokIt.retreatOverBraces())
					{
						wstring prev = txt;
						txt = lntokIt.getText();
						if(txt == "=") // struct initializer
							return commaIndent;
						do
						{
							txt = lntokIt.getText();
							if(txt == "{" || txt == "}" || txt == ";")
							{
								if(prev == "enum")
									return commaIndent;
								else
									break;
							}
							prev = txt;
						}
						while(lntokIt.retreatOverBraces());
					}
					return commaIndent + langPrefs.uTabSize;
				}
				if(isOpenBraceOrCase(lntokIt))
					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize;
				
				if(txt == "}" || txt == ";") // triggers the end of a statement, but not do {} while()
				{
					// indent once from line with first comma
					return commaIndent + langPrefs.uTabSize;
//					lntokIt.advanceOverComments();
//					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize;
				}
			}
			while(lntokIt.retreatOverBraces());

			return 0;
		}

		if(startTok == "else")
			return findMatchingIf();
		if(startTok == "case" || startTok == "default")
			return findPreviousCaseIndent();
		
		LineTokenIterator it = lntokIt;
		bool hasOpenBrace = findOpenBrace(it);
		if(hasOpenBrace && txt == "(")
			return visiblePosition(it.lineText, langPrefs.uTabSize, it.getIndex() + 1);

		if(startTok == "}" || startTok == "]")
		{
			if(hasOpenBrace)
				return countVisualSpaces(it.lineText, langPrefs.uTabSize);
			return 0;
		}
		
		wstring prevTok = lntokIt.getText();
		if(prevTok == ",")
			return findCommaIndent();
		
		int indent = 0, labelIndent = 0;
		bool newStmt = (prevTok == ";" || prevTok == "}" || prevTok == "{" || prevTok == ":");
		if(newStmt)// || prevTok == ":")
			if(dLex.isIdentifier(startTok) && lntokIt.getNextToken(2) == ":") // is it a jump label?
			{
				labelIndent = -langPrefs.uTabSize;
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
			indent = langPrefs.uTabSize;
		if(prevTok == "{" || prevTok == "[")
			return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize + labelIndent;

		bool skipLabel = false;
		do
		{
			txt = lntokIt.getText();
			if(txt == "(")
				return visiblePosition(lntokIt.lineText, langPrefs.uTabSize, lntokIt.getIndex() + 1);
			if(isOpenBraceOrCase(lntokIt))
				return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize + indent + labelIndent;
			
			if(txt == "}" || txt == ";") // triggers the end of a statement, but not do {} while()
			{
				// use indentation of next statement
				lntokIt.advanceOverComments();
				// skip labels
				wstring label = lntokIt.getText();
				if(!dLex.isIdentifier(label) || lntokIt.getNextToken() != ":")
					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + indent + labelIndent;
				lntokIt.retreatOverComments();
				newStmt = true;
			}
			if(!newStmt && isKeyword(toUTF8(txt))) // dLex.isIdentifier(txt))
			{
				return indent + countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
			}
			if(newStmt && txt == "else")
			{
				findMatchingIf();
				if(isOpenBraceOrCase(lntokIt))
					return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize + labelIndent;
			}
		}
		while(lntokIt.retreatOverBraces());

		return indent + labelIndent;
	}

	int ReindentLines(int startline, int endline)
	{
		LANGPREFERENCES langPrefs;
		if(int rc = GetUserPreferences(&langPrefs))
			return rc;
		if(langPrefs.IndentStyle != vsIndentStyleSmart)
			return S_FALSE;
		
		for(int line = startline; line <= endline; line++)
		{
			int rc = ReplaceLineIndent(line, &langPrefs);
			if(FAILED(rc))
				return rc;
		}
		return S_OK;
	}

	////////////////////////////////////////////////////////////////////////
	enum
	{
		AutoComment,
		ForceComment,
		ForceUncomment,
	}

	int CommentLines(int startline, int endline, int commentMode)
	{
		LANGPREFERENCES langPrefs;
		if(int rc = GetUserPreferences(&langPrefs))
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
	
	wstring FindIdentifierBackward(int line, int tok)
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
				if(toktype[p] == TokenCat.Identifier)
					return text[pos .. ppos];
				if(ppos > pos + 1 || !isWhite(text[pos]))
					return ""w;
				ppos = pos;
			}
			line--;
			tok = -1;
		}
		return ""w;
	}
	
	//////////////////////////////////////////////////////////////
	
	// create our own task pool to be able to destroy it (it keeps a the
	//  arguments to the last task, so they are never collected)
	__gshared TaskPool parseTaskPool;

	void runTask(T)(T dg)
	{
		if(!parseTaskPool)
		{
			int threads = defaultPoolThreads;
			if(threads < 1)
				threads = 1;
			parseTaskPool = new TaskPool(threads);
			parseTaskPool.isDaemon = true;
			parseTaskPool.priority(core.thread.Thread.PRIORITY_MIN);
		}
		auto task = task(&doParse);
		parseTaskPool.put(task);
	}
	
	bool startParsing()
	{
		if(!Package.GetGlobalOptions().parseSource && !mOutlining)
			return false;
		
		if(mParsingState > 1)
			return finishParsing();
		
		if(mModificationCountAST != mModificationCount)
			if(auto parser = mParser)
				parser.abort = true;

		if(mParsingState != 0 || mModificationCountAST == mModificationCount)
			return false;
		
		mParseText = GetText(); // should not be read from another thread
		mParsingState = 1;
		mModificationCountAST = mModificationCount;
		runTask(&doParse);
		
		return true;
	}
	
	bool finishParsing()
	{
		IVsEnumLineMarkers pEnum;
		if(mBuffer.EnumMarkers(0, 0, 0, 0, MARKER_CODESENSE_ERROR, EM_ENTIREBUFFER, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsTextLineMarker marker;
			while(pEnum.Next(&marker) == S_OK)
			{
				marker.Invalidate();
				marker.Release();
			}
		}
		for(int i = 0; i < mParseErrors.length; i++)
		{
			auto span = mParseErrors[0].span;
			IVsTextLineMarker marker;
			mBuffer.CreateLineMarker(MARKER_CODESENSE_ERROR, span.start.line - 1, span.start.index, 
									 span.end.line - 1, span.end.index, this, &marker);
		}
		
		if(mOutlining)
		{
			if(mStopOutlining)
			{
				mOutlineRegions = mOutlineRegions.init;
				mOutlining = false;
			}
			if(auto session = GetHiddenTextSession())
				if(DiffRegions(session, mOutlineRegions))
					session.AddHiddenRegions(chrNonUndoable, mOutlineRegions.length, mOutlineRegions.ptr, null);
			mOutlineRegions = mOutlineRegions.init;
		}
		mParseText = null;
		mParsingState = 0;
		ReColorizeLines (0, -1);
		return true;
	}
	
	void doParse()
	{
		if(Package.GetGlobalOptions().parseSource)
		{
			string txt = to!string(mParseText);
			
			mParser = new Parser;
			mParser.saveErrors = true;
			ast.Node n;
			try
			{
				n = mParser.parseModule(txt);
			}
			catch(ParseException e)
			{
				OutputDebugLog(e.msg);
			}
			catch(Throwable t)
			{
				OutputDebugLog(t.msg);
			}
			mAST = cast(ast.Module) n;
			mParseErrors = mParser.errors;
			mParser = null;
		}
		if(mOutlining)
		{
			mOutlineRegions = CreateOutlineRegions(mParseText, hrsExpanded);
		}
		mParsingState = 2;
	}
	
	bool hasParseError(ParserSpan span)
	{
		for(int i = 0; i < mParseErrors.length; i++)
			if(spanContains(span, mParseErrors[i].span.start.line-1, mParseErrors[i].span.start.index))
				return true;
		return false;
	}
	
	string getParseError(int line, int index)
	{
		for(int i = 0; i < mParseErrors.length; i++)
			if(vdc.util.textSpanContains(mParseErrors[i].span, line+1, index))
				return mParseErrors[i].msg;
		return null;
	}
	
	//////////////////////////////////////////////////////////////

	ExpansionProvider GetExpansionProvider()
	{
		if(!mExpansionProvider)
			mExpansionProvider = addref(new ExpansionProvider(this));
		return mExpansionProvider;
	}


	IVsTextLines GetTextLines() { return mBuffer; }

	CompletionSet GetCompletionSet()
	{
		if(!mCompletionSet)
			mCompletionSet = addref(new CompletionSet(null, this));
		return mCompletionSet;
	}

	MethodData GetMethodData()
	{
		if(!mMethodData)
			mMethodData = addref(new MethodData());
		return mMethodData;
	}

	bool IsCompletorActive()
	{
		if (mCompletionSet && mCompletionSet.mDisplayed)
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
					if(arrIndex(mExpressions, ident) < 0)
						mExpressions ~= ident;
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
		auto clone = new EnumProximityExpressions(this);
		*ppenum = addref(clone);
		return S_OK;
	}

	override int GetCount(ULONG *pceltCount)
	{
		*pceltCount = mExpressions.length;
		return S_OK;
	}
}

