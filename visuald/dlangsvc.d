// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module dlangsvc;

// import diamond;

import windows;
import std.string;
import std.ctype;
import std.utf;
import std.conv;
version(D_Version2) import std.algorithm;
else import std.math2;

import comutil;
import logutil;
import hierutil;
import fileutil;
import stringutil;
import pkgutil;
import simplelexer;
import dpackage;
import dimagelist;
import expansionprovider;
import completion;
import intellisense;
import searchsymbol;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.textmgr90;
import sdk.vsi.vsshell;
import sdk.vsi.singlefileeditor;
import sdk.vsi.fpstfmt;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;

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
                        IVsFormatFilterProvider
{
	static const GUID iid = g_languageCLSID;
		
	this(Package pkg)
	{
		mPackage = pkg;
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
		
		return super.QueryInterface(riid, pvObject);
	}

	// IDisposable
	override void Dispose()
	{
		closeSearchWindow();

		foreach(Source src; mSources)
			src.Release();
		mSources = mSources.init;
		
		foreach(CodeWindowManager mgr; mCodeWinMgrs)
			mgr.Release();
		mCodeWinMgrs = mCodeWinMgrs.init;
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
	override HRESULT GetColorableItem(in int iIndex, IVsColorableItem* ppItem)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetItemCount(int* piCount)
	{
		return E_NOTIMPL;
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

	//////////////////////////////////////////////////////////////

	Source GetSource(IVsTextLines buffer)
	{
		Source src;
		for(int i = 0; i < mSources.length; i++)
		{
			src = mSources[i];
			if(src.mBuffer is buffer)
				goto L_found;
		}

		src = new Source(buffer);
		mSources ~= src;
		src.AddRef();
	L_found:
		return src;
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
	uint                 mCookieDebuggerEvents;
}

///////////////////////////////////////////////////////////////////////////////

class Colorizer : DComObject, IVsColorizer 
{
	// mLineState keeps track of evaluated states, assuming the interesting lines have been processed
	//  after the last changes
	int[] mLineState;

	~this()
	{
	}

	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsColorizer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsColorizer //////////////////////////////////////
	override int GetStateMaintenanceFlag(BOOL* pfFlag)
	{
		*pfFlag = true;
		return S_OK;
	}

	override int GetStartState(int* piStartState)
	{
		*piStartState = 0;
		return S_OK;
	}

	override int ColorizeLine(in int iLine, in int iLength, in wchar* pText, in int iState, uint* pAttributes)
	{
		SaveLineState(iLine, iState);

		wstring text = to_cwstring(pText, iLength);
		uint pos = 0;
		while(pos < iLength)
		{
			uint prevpos = pos;
			int type = SimpleLexer.scan(iState, text, pos);
			while(prevpos < pos)
				pAttributes[prevpos++] = type;
		}
		pAttributes[iLength] = TokenColor.Text;

		return S_OK;
	}

	override int GetStateAtEndOfLine(in int iLine, in int iLength, in wchar* pText, in int iState)
	{
		SaveLineState(iLine, iState);

		wstring text = to_cwstring(pText, iLength);
		uint pos = 0;
		while(pos < iLength)
			SimpleLexer.scan(iState, text, pos);
		return iState;
	}

	override int CloseColorizer()
	{
		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	void SaveLineState(int iLine, int state)
	{
		if(iLine >= mLineState.length)
		{
			int i = mLineState.length;
			mLineState.length = iLine + 100;
			for( ; i < mLineState.length; i++)
				mLineState[i] = -1;
		}
		mLineState[iLine] = state;
	}

	int GetLineState(int iLine)
	{
		int state = -1;
		if(iLine >= 0 && iLine < mLineState.length)
			state = mLineState[iLine];
		assert(state >= 0);
		return state;
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

	void Dispose()
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

	HRESULT QueryInterface(in IID* riid, void** pvObject)
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
	
	void Dispose()
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

	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsUserDataEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTextLinesEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsUserDataEvents //////////////////////////////////////
	override int OnUserDataChange( /* [in] */ in GUID* riidKey,
	                      /* [in] */ in VARIANT vtNewValue)
	{
		return mSource.OnUserDataChange(riidKey, vtNewValue);
	}

	// IVsTextLinesEvents //////////////////////////////////////
	override int OnChangeLineText( /* [in] */ in TextLineChange *pTextLineChange,
	                      /* [in] */ in BOOL fLast)
	{
		return mSource.OnChangeLineText(pTextLineChange, fLast);
	}
    
	override int OnChangeLineAttributes( /* [in] */ in int iFirstLine,/* [in] */ in int iLastLine)
	{
		return mSource.OnChangeLineAttributes(iFirstLine, iLastLine);
	}
}

class Source : DisposingComObject, IVsUserDataEvents, IVsTextLinesEvents
{
	Colorizer mColorizer;
	IVsTextLines mBuffer;
	CompletionSet mCompletionSet;
	MethodData mMethodData;
	ExpansionProvider mExpansionProvider;
	SourceEvents mSourceEvents;
	
	this(IVsTextLines buffer)
	{
		mColorizer = new Colorizer;
		mBuffer = addref(buffer);
		mSourceEvents = new SourceEvents(this, mBuffer);
	}
	~this()
	{
	}

	void Dispose()
	{
		mExpansionProvider = release(mExpansionProvider);
		DismissCompletor();
		DismissMethodTip();
		mCompletionSet = release(mCompletionSet);
		mMethodData = release(mMethodData);
		mSourceEvents.Dispose();
		mBuffer = release(mBuffer);
	}

	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsUserDataEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTextLinesEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsUserDataEvents //////////////////////////////////////
	override int OnUserDataChange( /* [in] */ in GUID* riidKey,
	                      /* [in] */ in VARIANT vtNewValue)
	{
		return S_OK;
	}

	// IVsTextLinesEvents //////////////////////////////////////
	override int OnChangeLineText( /* [in] */ in TextLineChange *pTextLineChange,
	                      /* [in] */ in BOOL fLast)
	{
		return S_OK;
	}
    
	override int OnChangeLineAttributes( /* [in] */ in int iFirstLine,/* [in] */ in int iLastLine)
	{
		return S_OK;
	}

	///////////////////////////////////////////////////////////////////////////////
	wstring GetText(int startLine, int startCol, int endLine, int endCol)
	{
		if(endCol == -1)
			mBuffer.GetLengthOfLine(endLine, &endCol);

		BSTR text;
		mBuffer.GetLineText(startLine, startCol, endLine, endCol, &text);
		return wdetachBSTR(text);
	}

	bool GetWordExtent(int line, int idx, WORDEXTFLAGS flags, out int startIdx, out int endIdx)
	{
		startIdx = endIdx = idx;

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
			if (lineInfo[index + 1].type == TokenColor.Identifier)
				info = lineInfo[++index];
		if (index > 0 && info.StartIndex == idx)
			if (lineInfo[index - 1].type == TokenColor.Identifier)
				info = lineInfo[--index];

		// don't do anything in comment or text or literal space, unless we
		// are doing intellisense in which case we want to match the entire value
		// of quoted strings.
		TokenColor type = info.type;
		if ((flags != WORDEXT_FINDTOKEN || type != TokenColor.String) && 
		    (type == TokenColor.Comment || type == TokenColor.Text || type == TokenColor.String || type == TokenColor.Literal))
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

	static bool MatchToken(WORDEXTFLAGS flags, TokenInfo info)
	{
		TokenColor type = info.type;
		if ((flags & WORDEXT_FINDTOKEN) != 0)
			return type != TokenColor.Comment && type != TokenColor.String;
		return (type == TokenColor.Keyword || type == TokenColor.Identifier || type == TokenColor.Literal);
	}

	int GetLineCount()
	{
		int lineCount;
		mBuffer.GetLineCount(&lineCount);
		return lineCount;
	}
	
	TokenInfo[] GetLineInfo(int line, wstring *ptext = null)
	{
		TokenInfo[] lineInfo;

		int iState = mColorizer.GetLineState(line);
		if(iState < 0)
			return lineInfo;

		wstring text = GetText(line, 0, line, -1);
		if(ptext)
			*ptext = text;
		lineInfo = ScanLine(iState, text);
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
				if((!skipComments || infoArray[idx].type != TokenColor.Comment) &&
				   (infoArray[idx].type != TokenColor.Text || !isspace(text[infoArray[idx].StartIndex])))
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
				if(lineInfo[inf].type != TokenColor.Comment &&
				   (lineInfo[inf].type != TokenColor.Text || !isspace(txt[lineInfo[inf].StartIndex])))
				{
					wchar ch = txt[lineInfo[inf].StartIndex];
					if(level == 0)
						if(ch == ';' || ch == '}' || ch == '{' || ch == ':')
							return true;

					if(testNextFn && lineInfo[inf].type == TokenColor.Identifier)
						fn = txt[lineInfo[inf].StartIndex .. lineInfo[inf].EndIndex];
					testNextFn = false;
					
					if(SimpleLexer.isClosingBracket(ch))
						level++;
					else if(SimpleLexer.isOpeningBracket(ch) && level > 0)
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
		if(n < 0 || n == orgn)
			return S_OK;

		return doReplaceLineIndent(line, p, n, langPrefs);
	}
	
	int doReplaceLineIndent(int line, int idx, int n, LANGPREFERENCES* langPrefs)
	{
		int tabsz = (langPrefs.fInsertTabs && langPrefs.uTabSize > 0 ? langPrefs.uTabSize : n + 1);
		string spc = repeat("\t", n / tabsz) ~ repeat(" ", n % tabsz);
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
			return (lineInfo[tok].type == TokenColor.Comment ||
			       (lineInfo[tok].type == TokenColor.Text && isspace(lineText[lineInfo[tok].StartIndex])));
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
	}
	
	// calculate the indentation of the given line
	// - if ch != 0, assume it being inserted at the beginning of the line
	// - find the beginning of the previous statement
	//   - if the first token on the line is "else", remember "if" as a stop marker
	//   - set iterator tokIt to the last token of the previous line
	//   - if *tokIt is ';', move back one
	//   - while *tokIt is not the stop marker or '{' or ';'
	//     - move back one matching braces
	// - if the token before the given line is not ';' or '}', indent by one level more

	/*
	"if",
	"else",
	"while",
	"for",
	"synchronized",
	"scope",
	"version",
	"debug",
	*/
	// keywords that always start a statement/declaration
	wstring[] startKeywords = 
	[ 
		"if",
		"while",
		"do",
		"switch",
		"case",
		"default",
		"try",
		"with",
		"foreach",
		"foreach_reverse",
		"scope",
		"version",
		"debug",
		"delete",
		"throw",
		"module",
		"pragma",
		"template",
		"unittest",
	];
	wstring[] contKeywords = 
	[ 
		"else",
		"catch",
		"finally",
	];	
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
		wstring txt, matchStmt;
		int skipIf = 0;
		int indent;

		if(!lntokIt.retreatOverComments())
			return 0;
		
		wstring prevTok = lntokIt.getText();
		
		bool newStmt = (prevTok == ";" || prevTok == "}");
		if(newStmt)
			lntokIt.retreatOverBraces();
		else
			indent = langPrefs.uTabSize;
		
		while(lntokIt.retreatOverBraces())
		{
			txt = lntokIt.getText();
			if(txt == "(")
				return visiblePosition(txt, langPrefs.uTabSize, lntokIt.getIndex() + 1);
			if(txt == "{" || txt == "[")
				return countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize) + langPrefs.uTabSize;
			
			if(txt == "else")
				skipIf++;
			else if(txt == "if")
				skipIf--;
			else if(txt == "}" || txt == ";")
			{
				LineTokenIterator it = lntokIt;
				it.advanceOverComments();
				txt = it.getText();
				if(skipIf <= 0)
					return indent + countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
			}
		}
		
		version(none)
		{
		while(lntokIt.retreatOverBraces())
		{
			wstring txt = lntokIt.getText();
			version(none) if(matchStmt.length && txt == matchStmt)
			{
				indent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
				break;
			}
			if(contains(startKeywords, txt))
			{
				if(txt != "if" || skipIf == 0)
				{
					indent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
					break;
				}
				skipIf--;
			}
			if(txt == ";" || txt == "}")
			{
				lntokIt.advanceOverComments();
				txt = lntokIt.getText();
				if(txt != "else")
				{
					indent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
					indent += langPrefs.uIndentSize;
					break;
				}
				skipIf++;
				lntokIt.retreatOverComments();
			}
			if(txt == "{")
			{
				indent = countVisualSpaces(lntokIt.lineText, langPrefs.uTabSize);
				indent += langPrefs.uIndentSize;
				break;
			}
		}
		if(prevTok != "" && prevTok != ","w && prevTok != ";"w && prevTok != "}"w && startTok != "{")
			indent += langPrefs.uIndentSize;
		if(startTok == "}" || startTok == "]")
			indent -= langPrefs.uIndentSize;
		}
		return indent;
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
	int CommentLines(int startline, int endline)
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

		if (line > endline)
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
		else
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
		if(state < 0)
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

			SimpleLexer.scan(state, text, p);
			if(p > idx)
				return tok;
			
			tok++;
		}
		return -1;
	}

	// continuing from FindLineToken		
	bool FindEndOfComment(ref int iState, ref int line, ref uint pos)
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
				int toktype = SimpleLexer.scan(iState, text, pos);
				if(toktype != TokenColor.Comment)
				{
					if(ppos == 0)
					{
						pos = plinepos;
						line--;
					}
					else
						pos = ppos;
					return true;
				}
			}
			plinepos = pos;
			pos = 0;
			line++;
		}
		return false;
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
		int toktype = SimpleLexer.scan(iState, text, pos);
		if(toktype != TokenColor.Text)
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
				int type = SimpleLexer.scan(iState, text, pos);
				if(type == TokenColor.Text)
					if(SimpleLexer.isOpeningBracket(text[ppos]))
						level++;
					else if(SimpleLexer.isClosingBracket(text[ppos]))
						if(--level <= 0)
						{
							otherLine = line;
							otherIndex = ppos;
							return true;
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
			if(iState < 0)
				break;
			
			while(pos < text.length)
			{
				tokpos ~= pos;
				toktype ~= SimpleLexer.scan(iState, text, pos);
			}
			int p = (tok >= 0 ? tok : tokpos.length) - 1; 
			for( ; p >= 0; p--)
			{
				pos = tokpos[p];
				if(toktype[p] == TokenColor.Text)
				{
					if(pCountComma && text[pos] == ',')
						(*pCountComma)++;
					else if(SimpleLexer.isClosingBracket(text[pos]))
						level++;
					else if(SimpleLexer.isOpeningBracket(text[pos]))
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
			if(iState < 0)
				break;
			
			while(pos < text.length)
			{
				tokpos ~= pos;
				toktype ~= SimpleLexer.scan(iState, text, pos);
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
			if(iState < 0)
				break;
			
			while(pos < text.length)
			{
				tokpos ~= pos;
				toktype ~= SimpleLexer.scan(iState, text, pos);
			}
			int p = (tok >= 0 ? tok : tokpos.length) - 1;
			uint ppos = (p >= tokpos.length - 1 ? text.length : tokpos[p+1]);
			for( ; p >= 0; p--)
			{
				pos = tokpos[p];
				if(toktype[p] == TokenColor.Identifier)
					return text[pos .. ppos];
				if(ppos > pos + 1 || !isspace(text[pos]))
					return ""w;
				ppos = pos;
			}
			line--;
			tok = -1;
		}
		return ""w;
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

class ViewFilter : DisposingComObject, IVsTextViewFilter, IOleCommandTarget, 
                   IVsTextViewEvents, IVsExpansionEvents
{
	CodeWindowManager mCodeWinMgr;
	IVsTextView mView;
	uint mCookieTextViewEvents;
	IOleCommandTarget mNextTarget;

	this(CodeWindowManager mgr, IVsTextView view)
	{
		mCodeWinMgr = mgr;
		mView = addref(view);
		mCookieTextViewEvents = Advise!(IVsTextViewEvents)(mView, this);

		mView.AddCommandFilter(this, &mNextTarget);
	}
	~this()
	{
	}

	void Dispose()
	{
		if(mView)
		{
			mView.RemoveCommandFilter(this);

			if(mCookieTextViewEvents)
				Unadvise!(IVsTextViewEvents)(mView, mCookieTextViewEvents);
			mView = release(mView);
		}
		mCodeWinMgr = null;
	}

	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		// do not implement, VS2010 will not show Data tooltips in debugger if it is
		//if(queryInterface!(IVsTextViewFilter) (this, riid, pvObject))
		//	return S_OK;
		if(queryInterface!(IVsTextViewEvents) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IOleCommandTarget) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsExpansionEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IOleCommandTarget //////////////////////////////////////
	override int QueryStatus( /* [unique][in] */ in GUID *pguidCmdGroup,
	                 /* [in] */ in uint cCmds,
	                 /* [out][in][size_is] */ OLECMD *prgCmds,
	                 /* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
		// mixin(LogCallMix);

		for (uint i = 0; i < cCmds; i++) 
		{
			int rc = QueryCommandStatus(pguidCmdGroup, prgCmds[i].cmdID);
			if(rc == E_FAIL) 
			{
				if(mNextTarget)
					return mNextTarget.QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);
				return rc;
			}
			prgCmds[i].cmdf = cast(uint)rc;
		}
		return S_OK;
	}

	override int Exec( /* [unique][in] */ in GUID *pguidCmdGroup,
	          /* [in] */ in uint nCmdID,
	          /* [in] */ in uint nCmdexecopt,
	          /* [unique][in] */ in VARIANT *pvaIn,
	          /* [unique][out][in] */ VARIANT *pvaOut)
	{
		if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K && nCmdID == 1627 /*OutputPaneCombo*/) 
			return OLECMDERR_E_NOTSUPPORTED; // do not litter output
		
		debug 
		{
			bool logit = true;
			if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K)
			{
				switch(nCmdID)
				{
				case ECMD_HANDLEIMEMESSAGE:
					logit = false;
					break;
				default:
					break;
				}
			}
			else if(*pguidCmdGroup == guidVSDebugCommand)
			{
				switch(nCmdID)
				{
				case cmdidOutputPaneCombo:
				case cmdidProcessList:
				case cmdidThreadList:
				case cmdidStackFrameList:
					logit = false;
					break;
				default:
					break;
				}
			}
			if(logit)
				logCall("%s.Exec(this=%s, pguidCmdGroup=%s, nCmdId=%d: %s)", 
				        this, cast(void*) this, _toLog(pguidCmdGroup), nCmdID, cmd2string(*pguidCmdGroup, nCmdID));
		}
		
		ushort lo = (nCmdexecopt & 0xffff);
		ushort hi = (nCmdexecopt >> 16);

		bool wasCompletorActive = mCodeWinMgr.mSource.IsCompletorActive();
		bool gotEnterKey = false;
		ExpansionProvider ep = GetExpansionProvider();
		if(ep)	//if (ep.InTemplateEditingMode)
			if (ep.HandlePreExec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut))
				return S_OK;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97) 
		{
			switch (nCmdID) 
			{
			case cmdidGotoDefn:
				return HandleGotoDef();
			default:
				break;
			}
		}
		if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K) 
		{
			switch (nCmdID) 
			{
			case ECMD_RETURN:
				gotEnterKey = true;
				break;

			case ECMD_INVOKESNIPPETFROMSHORTCUT:
				return HandleSnippet();

			case ECMD_PARAMINFO:
				return HandleMethodTip();
				
			case ECMD_FORMATSELECTION:
				return ReindentLines();
			
			case ECMD_COMMENTBLOCK:
			case ECMD_COMMENT_BLOCK:
				return CommentLines();
				
			case ECMD_COMPLETEWORD:
			case ECMD_AUTOCOMPLETE:
				if(mCodeWinMgr.mSource.IsCompletorActive())
					moreCompletions();
				else
					initCompletion();
				return S_OK;

			case ECMD_SURROUNDWITH:
				if (mView && ep)
					//ep.DisplayExpansionBrowser(mView, "Insert Snippet", ["type1", "type2"], true, ["kind1", "kind2"], true);
					ep.DisplayExpansionBrowser(mView, "Surround with", [], true, [], true);
				break;
			case ECMD_INSERTSNIPPET:
				if (mView && ep)
					//ep.DisplayExpansionBrowser(mView, "Insert Snippet", ["type1", "type2"], true, ["kind1", "kind2"], true);
					ep.DisplayExpansionBrowser(mView, "Insert Snippet", [], false, [], false);
				break;
			default:
				break;
			}
		}
		if(g_commandSetCLSID == *pguidCmdGroup)
		{
			switch (nCmdID) 
			{
			case CmdShowScope:
				return showCurrentScope();
			
			case CmdShowMethodTip:
				return HandleMethodTip();
				
			default:
				break;
			}
		}
/+
		switch (lo) 
		{
                case OLECMDEXECOPT.OLECMDEXECOPT_SHOWHELP:
			if((nCmdexecopt >> 16) == VsMenus.VSCmdOptQueryParameterList) {
                        return QueryParameterList(ref guidCmdGroup, nCmdId, nCmdexecopt, pvaIn, pvaOut);
                    }
                    break;
                default:
                    // On every command, update the tip window if it's active.
                    if(this.textTipData != null && this.textTipData.IsActive())
                        textTipData.CheckCaretPosition(this.textView);

                    int rc = 0;
                    try {
                        rc = ExecCommand(ref guidCmdGroup, nCmdId, nCmdexecopt, pvaIn, pvaOut);
                    } catch (COMException e) {
                        int hr = e.ErrorCode;
                        // We silently fail on the following errors because the user has
                        // most likely already been prompted with things like source control checkout
                        // dialogs and so forth.
                        if(hr != (int)TextBufferErrors.BUFFER_E_LOCKED &&
                            hr != (int)TextBufferErrors.BUFFER_E_READONLY &&
                            hr != (int)TextBufferErrors.BUFFER_E_READONLY_REGION &&
                            hr != (int)TextBufferErrors.BUFFER_E_SCC_READONLY) {
                            throw;
                        }
                    }

                    return rc;
		}
		return OLECMDERR_E_NOTSUPPORTED;
+/
		int rc = mNextTarget.Exec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);

		if (ep)
			if (ep.HandlePostExec(pguidCmdGroup, nCmdID, nCmdexecopt, gotEnterKey, pvaIn, pvaOut))
				return rc;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K) 
		{
			switch (nCmdID) 
			{
			case ECMD_RETURN:
				if(!wasCompletorActive)
					HandleSmartIndent('\n');
				break;

			case ECMD_LEFT:
			case ECMD_RIGHT:
			case ECMD_BACKSPACE:
				if(mCodeWinMgr.mSource.IsCompletorActive())
					initCompletion();
				// fall through
			case ECMD_UP:
			case ECMD_DOWN:
				if(mCodeWinMgr.mSource.IsMethodTipActive())
					HandleMethodTip();
				break;
				
			case ECMD_TYPECHAR:
				dchar ch = pvaIn.lVal;
				//if(ch == '.')
				//	initCompletion();
				//else
				if(mCodeWinMgr.mSource.IsCompletorActive())
				{
					if(isalnum(ch) || ch == '_')
						initCompletion();
					else
						mCodeWinMgr.mSource.DismissCompletor();
				}
				
				if(ch == '{' || ch == '}')
					HandleSmartIndent(ch);
				
				if(mCodeWinMgr.mSource.IsMethodTipActive())
					if(ch == ',' || ch == ')')
						HandleMethodTip();
				break;
			default:
    				break;
			}
		}

		HighlightMatchingBraces();
		return rc;
	}

	//////////////////////////////

	void initCompletion()
	{
		CompletionSet cs = mCodeWinMgr.mSource.GetCompletionSet();
		Declarations decl = new Declarations;
		decl.StartExpansions(mView, mCodeWinMgr.mSource);
		cs.Init(mView, decl, false);
	}
	void moreCompletions()
	{
		CompletionSet cs = mCodeWinMgr.mSource.GetCompletionSet();
		Declarations decl = cs.mDecls;
		decl.MoreExpansions(mView, mCodeWinMgr.mSource);
		cs.Init(mView, decl, false);
	}
		
	int QueryCommandStatus(in GUID *guidCmdGroup, uint cmdID)
	{
		if(*guidCmdGroup == CMDSETID_StandardCommandSet97) 
		{
			switch (cmdID) 
			{
			case cmdidGotoDefn:
			//case VsCommands.GotoDecl:
			//case VsCommands.GotoRef:
				return OLECMDF_SUPPORTED | OLECMDF_ENABLED;
			default:
				break;
			}
		}
		if(*guidCmdGroup == CMDSETID_StandardCommandSet2K) 
		{
			switch (cmdID) 
			{
			case ECMD_PARAMINFO:
			case ECMD_FORMATSELECTION:
			case ECMD_COMMENTBLOCK:
			case ECMD_COMMENT_BLOCK:
			case ECMD_COMPLETEWORD:
			case ECMD_INSERTSNIPPET:
			case ECMD_INVOKESNIPPETFROMSHORTCUT:
			case ECMD_SURROUNDWITH:
			case ECMD_AUTOCOMPLETE:
				return OLECMDF_SUPPORTED | OLECMDF_ENABLED;
			default:
				break;
			}
		}
		if(g_commandSetCLSID == *guidCmdGroup)
		{
			switch (cmdID) 
			{
			case CmdShowScope:
			case CmdShowMethodTip:
				return OLECMDF_SUPPORTED | OLECMDF_ENABLED;
			default:
				break;
			}
		}
		return E_FAIL;
	}

	int HighlightComment(wstring txt, int line, ref ViewCol idx, out int otherLine, out int otherIndex)
	{
		if(SimpleLexer.isStartingComment(txt, idx))
		{
			int iState;
			uint pos;
			int tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(pos == idx)
			{
				SimpleLexer.scan(iState, txt, pos);
				//if(iState == SimpleLexer.toState(SimpleLexer.State.kNestedComment, 1, 0) ||
				if(iState == SimpleLexer.State.kWhite)
				{
					// terminated on same line
					otherLine = line;
					otherIndex = pos - 2; //assume 2 character comment extro 
					return S_OK;
				}
				if(SimpleLexer.scanState(iState) == SimpleLexer.State.kNestedComment ||
				   SimpleLexer.scanState(iState) == SimpleLexer.State.kBlockComment)
				{
					if(mCodeWinMgr.mSource.FindEndOfComment(iState, line, pos))
					{
						otherLine = line;
						otherIndex = pos - 2; //assume 2 character comment extro 
						return S_OK;
					}
				}
			}
		}
		else if(SimpleLexer.isEndingComment(txt, idx))
		{
			int iState;
			uint pos;
			int tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(tokidx >= 0)
			{
				int prevpos = pos;
				int prevline = line;
				SimpleLexer.scan(iState, txt, pos);
				if(pos == idx + 2 && iState == SimpleLexer.State.kWhite)
				{
					while(line > 0)
					{
						TokenInfo[] lineInfo = mCodeWinMgr.mSource.GetLineInfo(line);
						if(tokidx < 0)
							tokidx = lineInfo.length - 1;
						while(tokidx >= 0)
						{
							if(lineInfo[tokidx].type != TokenColor.Comment)
							{
								otherLine = prevline;
								otherIndex = prevpos;
								return S_OK;
							}
							prevpos = lineInfo[tokidx].StartIndex;
							prevline = line;
							tokidx--;
						}
						line--;
					}
				}
			}
		}
		return S_FALSE;
	}
	
	int HighlightMatchingBraces()
	{
		int line;
		ViewCol idx;

		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;
		wstring txt = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
		if(txt.length <= idx)
			return S_OK;
		
		int otherLine, otherIndex;
		int highlightLen = 1;
		if(HighlightComment(txt, line, idx, otherLine, otherIndex) == S_OK)
			highlightLen = 2;
		else if(!SimpleLexer.isOpeningBracket(txt[idx]) && 
		        !SimpleLexer.isClosingBracket(txt[idx]))
			return S_OK;
		else if(!FindMatchingBrace(line, idx, otherLine, otherIndex))
		{
			showStatusBarText("no matching bracket found"w);
			return S_OK;
		}

		TextSpan[2] spans;
		spans[0].iStartLine = line;
		spans[0].iStartIndex = idx;
		spans[0].iEndLine = line;
		spans[0].iEndIndex = idx + highlightLen;

		spans[1].iStartLine = otherLine;
		spans[1].iStartIndex = otherIndex;
		spans[1].iEndLine = otherLine;
		spans[1].iEndIndex = otherIndex + highlightLen;

		// HIGHLIGHTMATCHINGBRACEFLAGS.USERECTANGLEBRACES
		HRESULT hr = mView.HighlightMatchingBrace(0, 2, spans.ptr);

		if(highlightLen == 1)
		{
			wstring otxt = mCodeWinMgr.mSource.GetText(otherLine, otherIndex, otherLine, otherIndex + 1);
			if(!otxt.length || !SimpleLexer.isBracketPair(txt[idx], otxt[0]))
				showStatusBarText("mismatched bracket " ~ otxt);
		}

		return hr;
	}

	bool FindMatchingBrace(int line, int idx, out int otherLine, out int otherIndex)
	{
		int iState;
		uint pos;
		int tok = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
		if(tok < 0)
			return false;

		wstring text = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
		uint ppos = pos;
		int toktype = SimpleLexer.scan(iState, text, pos);
		if(toktype != TokenColor.Text)
			return false;

		if(SimpleLexer.isOpeningBracket(text[ppos]))
			return mCodeWinMgr.mSource.FindClosingBracketForward(line, iState, pos, otherLine, otherIndex);
		else if(SimpleLexer.isClosingBracket(text[ppos]))
			return mCodeWinMgr.mSource.FindOpeningBracketBackward(line, tok, otherLine, otherIndex);
		return false;
	}

	wstring GetWordAtCaret()
	{
		int line, idx;
		if(mView.GetCaretPos(&line, &idx) != S_OK)
			return "";
		int startIdx, endIdx;
		if(!mCodeWinMgr.mSource.GetWordExtent(line, idx, WORDEXT_CURRENT, startIdx, endIdx))
			return "";
		return mCodeWinMgr.mSource.GetText(line, startIdx, line, endIdx);
	}
	
	ExpansionProvider GetExpansionProvider()
	{
		return mCodeWinMgr.mSource.GetExpansionProvider();
	}

	int HandleSnippet()
	{
		int line, idx;
		if(mView.GetCaretPos(&line, &idx) != S_OK)
			return S_FALSE;
		int startIdx, endIdx;
		if(!mCodeWinMgr.mSource.GetWordExtent(line, idx, WORDEXT_CURRENT, startIdx, endIdx))
			return S_FALSE;
		
		wstring shortcut = mCodeWinMgr.mSource.GetText(line, startIdx, line, endIdx);
		TextSpan ts = TextSpan(startIdx, line, endIdx, line);
		
		string title, path;
		ExpansionProvider ep = GetExpansionProvider();
		return ep.InvokeExpansionByShortcut(mView, shortcut, ts, true, title, path);
	}

	//////////////////////////////////////////////////////////////
	int showCurrentScope()
	{
		TextSpan span;
		if(mView.GetCaretPos(&span.iStartLine, &span.iStartIndex) != S_OK)
			return S_FALSE;

		int line = span.iStartLine;
		int idx = span.iStartIndex;
		int iState;
		uint pos;
		int tok = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);

		wstring curScope;
		int otherLine, otherIndex;
		Source src = mCodeWinMgr.mSource;
		while(src.FindOpeningBracketBackward(line, tok, otherLine, otherIndex))
		{
			tok = mCodeWinMgr.mSource.FindLineToken(line, otherIndex, iState, pos);
			
			wstring bracket = src.GetText(otherLine, otherIndex, otherLine, otherIndex + 1);
			if(bracket == "{"w)
			{
				wstring fn;
				src.findStatementStart(otherLine, otherIndex, fn);
				wstring name = src.getScopeIdentifer(otherLine, otherIndex, fn);
				if(name.length && name != "{")
				{
					if(curScope.length)
						curScope = "." ~ curScope;
					curScope = name ~ curScope;
				}
			}
			line = otherLine;
		}

		if(curScope.length)
			showStatusBarText("Scope: " ~ curScope);
		else
			showStatusBarText("Scope: at module scope"w);
		
		return S_OK;
	}
	
	//////////////////////////////////////////////////////////////
	int HandleSmartIndent(dchar ch)
	{
		LANGPREFERENCES langPrefs;
		if(int rc = GetUserPreferences(&langPrefs))
			return rc;
		if(langPrefs.IndentStyle != vsIndentStyleSmart)
			return S_FALSE;
		
		int line, idx;
		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;
		if(ch != '\n')
			idx--;

		wstring linetxt = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
		int p, orgn = countVisualSpaces(linetxt, langPrefs.uTabSize, &p);
		if(idx > p || (ch != '\n' && linetxt[p] != ch))
			return S_FALSE; // do nothing if not at beginning of line

		int n = mCodeWinMgr.mSource.CalcLineIndent(line, ch, &langPrefs);
		if(n < 0 || n == orgn)
			return S_OK;
			
		return mCodeWinMgr.mSource.doReplaceLineIndent(line, p, n, &langPrefs);
	}

	int ReindentLines()
	{
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		int hr = mView.GetSelection(&iStartLine, &iStartIndex, &iEndLine, &iEndIndex);
		if(FAILED(hr)) // S_FALSE if no selection, but caret-coordinates returned
			return hr;

		IVsCompoundAction compAct = qi_cast!IVsCompoundAction(mView);
		if(compAct)
			compAct.OpenCompoundAction("RedindentLines"w.ptr);
		
		hr = mCodeWinMgr.mSource.ReindentLines(iStartLine, iEndLine);

		if(compAct)
		{
			compAct.CloseCompoundAction();
			compAct.Release();
		}
		return hr;
	}
		
	//////////////////////////////////////////////////////////////
	int CommentLines()
	{
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		int hr = mView.GetSelection(&iStartLine, &iStartIndex, &iEndLine, &iEndIndex);
		if(FAILED(hr)) // S_FALSE if no selection, but caret-coordinates returned
			return hr;
		if(iEndIndex == 0 && iEndLine > iStartLine)
			iEndLine--;
		
		IVsCompoundAction compAct = qi_cast!IVsCompoundAction(mView);
		if(compAct)
			compAct.OpenCompoundAction("CommentLines"w.ptr);
		
		hr = mCodeWinMgr.mSource.CommentLines(iStartLine, iEndLine);
		if(compAct)
		{
			compAct.CloseCompoundAction();
			compAct.Release();
		}
		return hr;
	}
		
	//////////////////////////////////////////////////////////////
	int HandleGotoDef()
	{
		string word = toUTF8(GetWordAtCaret());
		if(word.length <= 0)
			return S_FALSE;

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
		{
			showStatusBarText("No definition found for '" ~ word ~ "'");
			return S_FALSE;
		}

		if(defs.length > 1)
		{
			showStatusBarText("Multiple definitions found for '" ~ word ~ "'");
			showSearchWindow(false, word);
			return S_FALSE;
		}

		string file = mCodeWinMgr.mSource.GetFileName();
		HRESULT hr = OpenFileInSolution(defs[0].filename, defs[0].line, file);
		if(hr != S_OK)
			showStatusBarText(format("Cannot open %s(%d) for definition of '%s'", defs[0].filename, defs[0].line, word));

		return hr;
	}

	//////////////////////////////////////////////////////////////
	int HandleMethodTip()
	{
		int rc = _HandleMethodTip();
		if(rc != S_OK)
			mCodeWinMgr.mSource.DismissMethodTip();
		return rc;
	}
		
	int _HandleMethodTip()
	{
		TextSpan span;
		if(mView.GetCaretPos(&span.iStartLine, &span.iStartIndex) != S_OK)
			return S_FALSE;

		int line = span.iStartLine;
		int idx = span.iStartIndex;
		int iState;
		uint pos;
		int tok = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);

	stepUp:
		int otherLine, otherIndex, cntComma;
		Source src = mCodeWinMgr.mSource;
		if(!src.FindOpeningBracketBackward(line, tok, otherLine, otherIndex, &cntComma))
			return S_FALSE;
		
		wstring bracket = src.GetText(otherLine, otherIndex, otherLine, otherIndex + 1);
		if(bracket != "("w)
			return S_FALSE;

		tok = mCodeWinMgr.mSource.FindLineToken(otherLine, otherIndex, iState, pos);
		string word = toUTF8(src.FindIdentifierBackward(otherLine, tok));
		if(word.length <= 0)
		{
			line = otherLine;
			idx = otherIndex;
			goto stepUp;
		}

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
			return S_FALSE;
		
		MethodData md = src.GetMethodData();
		span.iEndLine = span.iStartLine;
		span.iEndIndex = span.iStartIndex + 1;
		md.Refresh(mView, defs, cntComma, span);
		
		return S_OK;
	}
	
	// not implemented, VS2010 will not show Data tooltips in debugger if it is
	// IVsTextViewFilter //////////////////////////////////////
	override int GetWordExtent(in int iLine, in CharIndex iIndex, in uint dwFlags, /* [out] */ TextSpan *pSpan)
	{
		mixin(LogCallMix);

		int startIdx, endIdx;
		if(!mCodeWinMgr.mSource.GetWordExtent(iLine, iIndex, dwFlags, startIdx, endIdx))
			return S_FALSE;

		pSpan.iStartLine = iLine;
		pSpan.iStartIndex = startIdx;
		pSpan.iEndLine = iLine;
		pSpan.iEndIndex = endIdx;
		return S_OK;
	}

	override int GetDataTipText( /* [out][in] */ TextSpan *pSpan, /* [out] */ BSTR *pbstrText)
	{
		mixin(LogCallMix);

		// currently disabled to show data breakpoints while debugging
		if(mCodeWinMgr.mLangSvc.IsDebugging())
			return E_NOTIMPL;
		//return TIP_S_ONLYIFNOMARKER;
		
	version(none) // disabled until useful
	{
		if(HRESULT hr = GetWordExtent(pSpan.iStartLine, pSpan.iStartIndex, WORDEXT_CURRENT, pSpan))
			return hr;

		string word = toUTF8(mCodeWinMgr.mSource.GetText(pSpan.iStartLine, pSpan.iStartIndex, pSpan.iEndLine, pSpan.iEndIndex));
		if(word.length <= 0)
			return S_FALSE;

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
			return S_FALSE;

		string msg = word ~ "\n";
		foreach(def; defs)
		{
			string m = def.kind ~ "\t" ~ def.filename ~ ":" ~ to!(string)(def.line) ~ "\n";
			msg ~= m;
		}
		*pbstrText = allocBSTR(msg);
		return S_OK; // E_NOTIMPL;
	}
	else
	{
		return E_NOTIMPL;
	}

	}

	override int GetPairExtents(in int iLine, in CharIndex iIndex, /* [out] */ TextSpan *pSpan)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	// IVsTextViewEvents //////////////////////////////////////
	override int OnSetFocus(IVsTextView pView)
	{
		mixin(LogCallMix);
		return S_OK;
	}

	override int OnKillFocus(IVsTextView pView)
	{
		mixin(LogCallMix);
		return S_OK;
	}

	override int OnSetBuffer(IVsTextView pView, IVsTextLines pBuffer)
	{
		mixin(LogCallMix);
		return S_OK;
	}

	override int OnChangeScrollInfo(IVsTextView pView, in int iBar,
	                       in int iMinUnit, in int iMaxUnits,
	                       in int iVisibleUnits, in int iFirstVisibleUnit)
	{
		// mixin(LogCallMix);
		return S_OK;
	}

	override int OnChangeCaretLine(IVsTextView pView, in int iNewLine, in int iOldLine)
	{
		// mixin(LogCallMix);
		return S_OK;
	}

	// IVsExpansionEvents //////////////////////////////////////
	override int OnAfterSnippetsUpdate()
	{
		mixin(LogCallMix);
		return S_OK;
	}

	override int OnAfterSnippetsKeyBindingChange(in uint dwCmdGuid, in uint dwCmdId, in BOOL fBound)
	{
		mixin(LogCallMix);
		return S_OK;
	}

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
			if(iState < 0)
				break;

			wstring text = src.GetText(line, 0, line, -1);
			uint pos = 0;
			wstring ident;
			while(pos < text.length)
			{
				uint ppos = pos;
				int type = SimpleLexer.scan(iState, text, pos);
				wstring txt = text[ppos .. pos];
				if(type == TokenColor.Identifier || txt == "this"w)
				{
					ident ~= txt;
					if(ident.length > 4 && ident[0..5] == "this."w)
						ident = "this->"w ~ ident[5..$];
					if(array_find(mExpressions, ident) < 0)
						mExpressions ~= ident;
				}
				else if (type == TokenColor.Text && txt == "."w)
					ident ~= "."w;
				else
					ident = ""w;
			}
		}
		if(array_find(mExpressions, "this"w) < 0)
			mExpressions ~= "this"w;
	}

	this(EnumProximityExpressions epe)
	{
		mExpressions = epe.mExpressions;
		mPos = epe.mPos;
	}

	HRESULT QueryInterface(in IID* riid, void** pvObject)
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

