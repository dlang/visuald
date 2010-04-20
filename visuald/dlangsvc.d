// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module dlangsvc;

// import diamond;

import std.c.windows.windows;
import std.c.windows.com;
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
import simplelexer;
import dpackage;
import expansionprovider;
import completion;
import intellisense;

import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.vsshell;
import sdk.vsi.singlefileeditor;
import sdk.vsi.fpstfmt;

///////////////////////////////////////////////////////////////////////////////

class LanguageService : DisposingComObject, 
                        IVsLanguageInfo, 
                        IVsLanguageDebugInfo, 
                        IVsProvideColorableItems, 
                        IVsLanguageContextProvider, 
                        IServiceProvider, 
//                        ISynchronizeInvoke, 
                        IVsDebuggerEvents, 
                        IVsFormatFilterProvider
{
	this(Package pkg)
	{
		mPackage = pkg;
	}

	~this()
	{
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsLanguageInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProvideColorableItems) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLanguageDebugInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsDebuggerEvents) (this, riid, pvObject))
			return S_OK;
		
		return super.QueryInterface(riid, pvObject);
	}

	// IDisposable
	override void Dispose()
	{
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
		*pbstrName = null;
		*piLineOffset = 0;
		return S_OK;
	}

	override HRESULT GetProximityExpressions(IVsTextBuffer pBuffer, in int iLine, in int iCol, in int cLines, IVsEnumBSTR* ppEnum)
	{
		scope auto text = new ComPtr!(IVsTextLines)(pBuffer);
		if(!text.ptr)
			return E_FAIL;
		Source src = GetSource(text.ptr);
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
		mixin(LogCallMix);
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

	HRESULT QueryInterface(IID* riid, void** pvObject)
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
		if(iLine >= mLineState.length)
			return -1;
		return mLineState[iLine];
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

	HRESULT QueryInterface(IID* riid, void** pvObject)
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

struct TokenInfo
{
	TokenColor type;
	int StartIndex;
	int EndIndex;
}

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

class Source : DisposingComObject, IVsUserDataEvents, IVsTextLinesEvents
{
	Colorizer mColorizer;
	IVsTextLines mBuffer;
	CompletionSet mCompletionSet;
	ExpansionProvider mExpansionProvider;
	uint mCookieUserDataEvents;
	uint mCookieTextLinesEvents;

	this(IVsTextLines buffer)
	{
		mColorizer = new Colorizer;
		mBuffer = buffer;
		if(mBuffer)
		{
			mBuffer.AddRef();
			mCookieUserDataEvents = Advise!(IVsUserDataEvents)(mBuffer, this);
			mCookieTextLinesEvents = Advise!(IVsTextLinesEvents)(mBuffer, this);
		}
	}
	~this()
	{
	}

	void Dispose()
	{
		mExpansionProvider = release(mExpansionProvider);
		DismissCompletor();
		mCompletionSet = release(mCompletionSet);
		if(mBuffer)
		{
			if(mCookieUserDataEvents)
				Unadvise!(IVsUserDataEvents)(mBuffer, mCookieUserDataEvents);
			if(mCookieTextLinesEvents)
				Unadvise!(IVsTextLinesEvents)(mBuffer, mCookieTextLinesEvents);
			mBuffer = release(mBuffer);
		}
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
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
		int index = this.GetTokenInfoAt(lineInfo, idx, info);
		if (index < 0)
			return false;
		if (index < lineInfo.length - 1 && info.EndIndex == idx)
			if (lineInfo[index + 1].type == TokenColor.Identifier)
				info = lineInfo[++index];

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
			return type != TokenColor.Comment;
		return (type == TokenColor.Keyword || type == TokenColor.Identifier || type == TokenColor.String || type == TokenColor.Literal);
	}

	TokenInfo[] GetLineInfo(int line)
	{
		TokenInfo[] lineInfo;

		int iState = mColorizer.GetLineState(line);
		if(iState < 0)
			return lineInfo;

		wstring text = GetText(line, 0, line, -1);
		for(uint pos = 0; pos < text.length; )
		{
			TokenInfo info;
			info.StartIndex = pos;
			info.type = cast(TokenColor) SimpleLexer.scan(iState, text, pos);
			info.EndIndex = pos;
			lineInfo ~= info;
		}
		return lineInfo;
	}

	static int GetTokenInfoAt(TokenInfo[] infoArray, int col, ref TokenInfo info)
	{
		for (int i = 0, len = infoArray.length; i < len; i++)
		{
			int start = infoArray[i].StartIndex;
			int end = infoArray[i].EndIndex;

			if (i == 0 && start > col)
				return -1;

			if (col >= start && col <= end)
			{
				info = infoArray[i];
				return i;
			}
		}
		return -1;
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
	int ReplaceLineIndent(int line, LANGPREFERENCES* langPrefs)
	{
		wstring linetxt = GetText(line, 0, line, -1);
		int p, orgn = countVisualSpaces(linetxt, langPrefs.uTabSize, &p);
		int n = 0;
		if(p < linetxt.length)
			n = CalcLineIndent(line, linetxt[p], langPrefs);
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
	
	int CalcLineIndent(int line, dchar ch, LANGPREFERENCES* langPrefs)
	{
		for(int ln = line - 1; ln >= 0; --ln)
		{
			wstring txt = GetText(ln, 0, ln, -1);
			
			TokenInfo[] lineInfo = GetLineInfo(ln);
			int inf = lineInfo.length - 1;
			for( ; inf >= 0; inf--)
				if(lineInfo[inf].type != TokenColor.Comment &&
				   (lineInfo[inf].type != TokenColor.Text || !isspace(txt[lineInfo[inf].StartIndex])))
					break;
			if(inf < 0)
				continue;

			wstring lastTok = txt[lineInfo[inf].StartIndex .. lineInfo[inf].EndIndex];
			
			int p, n = countVisualSpaces(txt, langPrefs.uTabSize, &p);

			if(lastTok == ";"w || lastTok == "}"w)
			{
				int otherLine, otherIndex;
				if(FindOpeningBracketBackward(line, 0, otherLine, otherIndex))
				{
					txt = GetText(otherLine, 0, otherLine, -1);
					n = countVisualSpaces(txt, langPrefs.uTabSize, &p);
					n += langPrefs.uIndentSize;
				}
			}
			else if(lastTok != ","w && ch != '{')
				n += langPrefs.uIndentSize;
			if(ch == '}')
				n -= langPrefs.uIndentSize;
			
			return n;
		}
		return -1;
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

	//////////////////////////////////////////////////////////////

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

	bool FindOpeningBracketBackward(int line, int tok, out int otherLine, out int otherIndex)
	{
		int level = 1;
		while(line >= 0)
		{
			wstring text = GetText(line, 0, line, -1);
			int[] tokpos;
			int[] toktype;
			uint pos = 0;
			int iState = mColorizer.GetLineState(line);
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
					if(SimpleLexer.isClosingBracket(text[pos]))
						level++;
					else if(SimpleLexer.isOpeningBracket(text[pos]))
						if(--level <= 0)
						{
							otherLine = line;
							otherIndex = pos;
							return true;
						}
			}
			line--;
			tok = -1;
		}
		return false;
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

	bool IsCompletorActive()
	{
		if (mCompletionSet && mCompletionSet.mDisplayed)
			return true;
		return false;
	}

	void DismissCompletor()
	{
		if (mCompletionSet && mCompletionSet.mDisplayed)
			mCompletionSet.Close();
		//if (this.methodData != null && this.methodData.IsDisplayed)
		//	this.methodData.Close();
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

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsTextViewFilter) (this, riid, pvObject))
			return S_OK;
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
		mixin(LogCallMix);
		logCall("nCmdID = %s", cmd2string(*pguidCmdGroup, nCmdID));

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

			case ECMD_FORMATSELECTION:
				return ReindentLines();
				
			case ECMD_COMPLETEWORD:
			case ECMD_AUTOCOMPLETE:
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
		return OLECMDERR.E_NOTSUPPORTED;
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
				else if(ch == '{' || ch == '}')
					HandleSmartIndent(ch);
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
		if(!decl.ImportExpansions(mView, mCodeWinMgr.mSource))
			decl.NearbyExpansions(mView, mCodeWinMgr.mSource);
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
			case ECMD_FORMATSELECTION:
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
		return E_FAIL;
	}

	int HighlightMatchingBraces()
	{
		int line;
		ViewCol idx;

		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;

		wstring txt = mCodeWinMgr.mSource.GetText(line, idx, line, idx + 1);
		if(txt.length == 0)
			return S_OK;
		if(!SimpleLexer.isOpeningBracket(txt[0]) && !SimpleLexer.isClosingBracket(txt[0]))
			return S_OK;

		int otherLine, otherIndex;
		if(!FindMatchingBrace(line, idx, otherLine, otherIndex))
			return S_OK;

		TextSpan[2] spans;
		spans[0].iStartLine = line;
		spans[0].iStartIndex = idx;
		spans[0].iEndLine = line;
		spans[0].iEndIndex = idx + 1;

		spans[1].iStartLine = otherLine;
		spans[1].iStartIndex = otherIndex;
		spans[1].iEndLine = otherLine;
		spans[1].iEndIndex = otherIndex + 1;

		// HIGHLIGHTMATCHINGBRACEFLAGS.USERECTANGLEBRACES
		return mView.HighlightMatchingBrace(0, 2, spans.ptr);
	}

	bool FindMatchingBrace(int line, int idx, out int otherLine, out int otherIndex)
	{
		int iState = mCodeWinMgr.mSource.mColorizer.GetLineState(line);
		if(iState < 0)
			return false;

		wstring text = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
		uint pos = 0;
		int tok = 0;
		for( ; pos < text.length && pos < idx; tok++)
			SimpleLexer.scan(iState, text, pos);
		if(pos >= text.length || pos > idx)
			return false;

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
		return mCodeWinMgr.mSource.ReindentLines(iStartLine, iEndLine);
	}
		
	//////////////////////////////////////////////////////////////
	int HandleGotoDef()
	{
		string word = toUTF8(GetWordAtCaret());
		if(word.length <= 0)
			return S_FALSE;

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
			return S_FALSE;

		// Get the IVsUIShellOpenDocument service so we can ask it to open a doc window
		IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
		if(!pIVsUIShellOpenDocument)
			return returnError(E_FAIL);
		scope(exit) release(pIVsUIShellOpenDocument);
		
		auto wstrPath = _toUTF16z(defs[0].filename);
		BSTR bstrAbsPath;
		
		HRESULT hr;
		hr = pIVsUIShellOpenDocument.SearchProjectsForRelativePath(RPS_UseAllSearchStrategies, wstrPath, &bstrAbsPath);
		if(hr != S_OK)
		{
			// search import paths
			string file = mCodeWinMgr.mSource.GetFileName();
			string[] imps = GetImportPaths(file);
			foreach(imp; imps)
			{
				file = normalizeDir(imp) ~ defs[0].filename;
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
		
		return textmgr.NavigateToLineAndColumn(textBuffer, &LOGVIEWID_Primary, defs[0].line, 0, defs[0].line, 0);
	}

	// IVsTextViewFilter //////////////////////////////////////
	override int GetWordExtent(in int iLine, in CharIndex iIndex, in uint dwFlags, /* [out] */ TextSpan *pSpan)
	{
		mixin(LogCallMix);

		int startIdx, endIdx;
		if(!mCodeWinMgr.mSource.GetWordExtent(iLine, iIndex, dwFlags, startIdx, endIdx))
			return E_FAIL;

		pSpan.iStartLine = iLine;
		pSpan.iStartIndex = startIdx;
		pSpan.iEndLine = iLine;
		pSpan.iEndIndex = endIdx;
		return S_OK;
	}

	override int GetDataTipText( /* [out][in] */ TextSpan *pSpan, /* [out] */ BSTR *pbstrText)
	{
		// currently disabled to show data breakpoints while debugging
		if(mCodeWinMgr.mLangSvc.IsDebugging())
			return E_NOTIMPL;

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

	HRESULT QueryInterface(IID* riid, void** pvObject)
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

