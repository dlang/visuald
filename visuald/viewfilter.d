// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module viewfilter;

import windows;
import std.string;
import std.ctype;
import std.utf;
import std.conv;
import std.algorithm;

import comutil;
import logutil;
import hierutil;
import fileutil;
import stringutil;
import pkgutil;
import dpackage;
import dimagelist;
import completion;
import simplelexer;
import simpleparser;
import intellisense;
import searchsymbol;
import expansionprovider;
import dlangsvc;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;

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
				return CommentLines(Source.ForceComment);
			case ECMD_UNCOMMENTBLOCK:
			case ECMD_UNCOMMENT_BLOCK:
				return CommentLines(Source.ForceUncomment);
				
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
				
			case CmdToggleComment:
				return CommentLines(Source.AutoComment);
				
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
			case ECMD_UNCOMMENTBLOCK:
			case ECMD_UNCOMMENT_BLOCK:
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
			case CmdToggleComment:
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
		if(toktype != TokenColor.Operator)
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

		if(iEndLine < iStartLine)
			std.algorithm.swap(iStartLine, iEndLine);
		
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
	int CommentLines(int commentMode)
	{
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		int hr = mView.GetSelection(&iStartLine, &iStartIndex, &iEndLine, &iEndIndex);
		if(FAILED(hr)) // S_FALSE if no selection, but caret-coordinates returned
			return hr;
		if(iEndLine < iStartLine)
		{
			std.algorithm.swap(iStartLine, iEndLine);
			std.algorithm.swap(iStartIndex, iEndIndex);
		}
		if(iEndIndex == 0 && iEndLine > iStartLine)
			iEndLine--;
		
		IVsCompoundAction compAct = qi_cast!IVsCompoundAction(mView);
		if(compAct)
			compAct.OpenCompoundAction("CommentLines"w.ptr);
		
		hr = mCodeWinMgr.mSource.CommentLines(iStartLine, iEndLine, commentMode);
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

