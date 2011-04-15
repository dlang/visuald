// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.viewfilter;

import visuald.windows;
import std.string;
import std.ctype;
import std.utf;
import std.conv;
import std.algorithm;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.dpackage;
import visuald.dimagelist;
import visuald.completion;
import visuald.simpleparser;
import visuald.intellisense;
import visuald.searchsymbol;
import visuald.expansionprovider;
import visuald.dlangsvc;
import visuald.winctrl;
import visuald.tokenreplace;

import vdc.lexer;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsshell;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;

///////////////////////////////////////////////////////////////////////////////

version = tip;

class ViewFilter : DisposingComObject, IVsTextViewFilter, IOleCommandTarget, 
                   IVsTextViewEvents, IVsExpansionEvents
{
	CodeWindowManager mCodeWinMgr;
	IVsTextView mView;
	uint mCookieTextViewEvents;
	IOleCommandTarget mNextTarget;

	int mLastHighlightBracesLine;
	ViewCol mLastHighlightBracesCol;
	
version(tip)
	TextTipData mTextTipData;
	
	this(CodeWindowManager mgr, IVsTextView view)
	{
		mCodeWinMgr = mgr;
		mView = addref(view);
		mCookieTextViewEvents = Advise!(IVsTextViewEvents)(mView, this);

		mView.AddCommandFilter(this, &mNextTarget);
		
version(tip)
		mTextTipData = addref(new TextTipData);
	}
	~this()
	{
	}

	override void Dispose()
	{
		if(mView)
		{
			mView.RemoveCommandFilter(this);

			if(mCookieTextViewEvents)
				Unadvise!(IVsTextViewEvents)(mView, mCookieTextViewEvents);
			mView = release(mView);
		}
version(tip)
		if(mTextTipData)
		{
			 // we need to break the circular reference TextTipData<->IVsMethodTipWindow
			mTextTipData.Dispose();
			mTextTipData = release(mTextTipData);
		}
		mCodeWinMgr = null;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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
			case cmdidPasteNextTBXCBItem:
				if(PasteFromRing() == S_OK)
					return S_OK;
				break;
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
				
			case ECMD_GOTOBRACE:
				return GotoMatchingPair(false);
			case ECMD_GOTOBRACE_EXT:
				return GotoMatchingPair(true);
			
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
				{
					if(ch == ',' || ch == ')')
						HandleMethodTip();
				}
				else if(ch == '(')
				{
					LANGPREFERENCES langPrefs;
					if(GetUserPreferences(&langPrefs) == S_OK && langPrefs.fAutoListParams)
						_HandleMethodTip(false);
				}
				break;
			default:
				break;
			}
		}

		// delayed into idle: HighlightMatchingPairs();
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
			case cmdidPasteNextTBXCBItem:
				return OLECMDF_SUPPORTED | OLECMDF_ENABLED;
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
			case ECMD_GOTOBRACE:
			case ECMD_GOTOBRACE_EXT:
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
		int iState, tokidx;
		uint pos;
		if(Lexer.isStartingComment(txt, idx))
		{
			tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(pos == idx)
			{
				int startState = iState;
				if(Lexer.scan(iState, txt, pos) == TokenColor.Comment)
				{
					//if(iState == Lexer.toState(Lexer.State.kNestedComment, 1, 0) ||
					if(iState == Lexer.State.kWhite)
					{
						// terminated on same line
						otherLine = line;
						otherIndex = pos - 2; //assume 2 character comment extro 
						return S_OK;
					}
					if(Lexer.isCommentState(Lexer.scanState(iState)))
					{
						if(mCodeWinMgr.mSource.FindEndOfComment(startState, iState, line, pos))
						{
							otherLine = line;
							otherIndex = pos - 2; //assume 2 character comment extro 
							return S_OK;
						}
					}
				}
			}
		}
		if(Lexer.isEndingComment(txt, idx))
		{
			tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(tokidx >= 0)
			{
				int startState = iState;
				uint startpos = pos;
				if(Lexer.scan(iState, txt, pos) == TokenColor.Comment)
				{
					if(startState == iState ||
					   mCodeWinMgr.mSource.FindStartOfComment(startState, line, startpos))
					{
						otherLine = line;
						otherIndex = startpos;
						return S_OK;
					}
				}
/+
				int prevpos = pos;
				int prevline = line;
				Lexer.scan(iState, txt, pos);
				if(pos == idx + 2 && iState == Lexer.State.kWhite)
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
+/
			}
		}
		return S_FALSE;
	}
	
	int HighlightString(wstring txt, int line, ref ViewCol idx, out int otherLine, out int otherIndex)
	{
		int iState;
		uint pos;
		auto src = mCodeWinMgr.mSource;
		int tokidx = src.FindLineToken(line, idx, iState, pos);
		if(tokidx < 0)
			return S_FALSE;
		
		uint startPos = pos;
		int startState = iState;
		int type = Lexer.scan(iState, txt, pos);
		if(type == TokenColor.String)
		{
			Lexer.State sstate;
			sstate = Lexer.scanState(startState);
			if(idx == startPos && !Lexer.isStringState(sstate))
			{
				if(src.FindEndOfString(startState, iState, line, pos))
				{
					otherLine = line;
					otherIndex = pos - 1;
					return S_OK;
				}
				return S_FALSE;
			}
			sstate = Lexer.scanState(iState);
			if(idx == pos - 1 && !Lexer.isStringState(sstate))
			{
				if(src.FindStartOfString(startState, line, startPos))
				{
					otherLine = line;
					otherIndex = startPos;
					return S_OK;
				}
			}
		}
		return S_FALSE;
	}
	
	int HighlightMatchingPairs()
	{
		int line, otherLine;
		ViewCol idx, otherIndex;
		int highlightLen;
		bool checkMismatch;

		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;
		if(FindMatchingPairs(line, idx, otherLine, otherIndex, highlightLen, checkMismatch) != S_OK)
			return S_OK;
		
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

		if(highlightLen == 1 && checkMismatch)
		{
			wstring txt = mCodeWinMgr.mSource.GetText(line, idx, line, idx + 1);
			wstring otxt = mCodeWinMgr.mSource.GetText(otherLine, otherIndex, otherLine, otherIndex + 1);
			if(!otxt.length || !Lexer.isBracketPair(txt[0], otxt[0]))
				showStatusBarText("mismatched bracket " ~ otxt);
		}

		return hr;
	}

	int FindMatchingPairs(int line, ref ViewCol idx, out int otherLine, out ViewCol otherIndex,
				  		  out int highlightLen, out bool checkMismatch)
	{
		wstring txt = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
		if(txt.length <= idx)
			return S_FALSE;
		
		highlightLen = 1;
		checkMismatch = true;
		if(HighlightComment(txt, line, idx, otherLine, otherIndex) == S_OK)
			highlightLen = 2;
		else if(HighlightString(txt, line, idx, otherLine, otherIndex) == S_OK)
			checkMismatch = false;
		else if(!Lexer.isOpeningBracket(txt[idx]) && 
		        !Lexer.isClosingBracket(txt[idx]))
			return S_FALSE;
		else if(!FindMatchingBrace(line, idx, otherLine, otherIndex))
		{
			// showStatusBarText("no matching bracket found"w);
			return S_FALSE;
		}
		return S_OK;
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
		int toktype = Lexer.scan(iState, text, pos);
		if(toktype != TokenColor.Operator)
			return false;

		if(Lexer.isOpeningBracket(text[ppos]))
			return mCodeWinMgr.mSource.FindClosingBracketForward(line, iState, pos, otherLine, otherIndex);
		else if(Lexer.isClosingBracket(text[ppos]))
			return mCodeWinMgr.mSource.FindOpeningBracketBackward(line, tok, otherLine, otherIndex);
		return false;
	}

	int FindClosingMatchingPairs(out int line, out ViewCol idx, out int otherLine, out ViewCol otherIndex,
				  				 out int highlightLen, out bool checkMismatch)
	{
		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;
		int caretLine = line;
		int caretIndex = idx;
		
		while(line >= 0)
		{
			wstring text = mCodeWinMgr.mSource.GetText(line, 0, line, -1);
			if(idx < 0)
				idx = text.length;
			
			while(--idx >= 0)
			{
				if(Lexer.isOpeningBracket(text[idx]) || 
				   text[idx] == '\"' || text[idx] == '`' || text[idx] == '/')
				{
					if(FindMatchingPairs(line, idx, otherLine, otherIndex, highlightLen, checkMismatch) == S_OK)
						if(otherLine > caretLine || 
						   (otherLine == caretLine && otherIndex > caretIndex))
							return S_OK;
				}
			}
			line--;
		}
		
		return S_FALSE;
	}
	
	int GotoMatchingPair(bool select)
	{
		int line, otherLine;
		ViewCol idx, otherIndex;
		int highlightLen;
		bool checkMismatch;

		if(mView.GetCaretPos(&line, &idx) != S_OK)
			return S_FALSE;
		if(FindMatchingPairs(line, idx, otherLine, otherIndex, highlightLen, checkMismatch) != S_OK)
			if(FindClosingMatchingPairs(line, idx, otherLine, otherIndex, highlightLen, checkMismatch) != S_OK)
				return S_OK;
		
		mView.SetCaretPos(otherLine, otherIndex);

		TextSpan span;
		span.iStartLine = otherLine;
		span.iStartIndex = otherIndex;
		span.iEndLine = otherLine;
		span.iEndIndex = otherIndex + highlightLen;
		
		mView.EnsureSpanVisible(span);
		if(select)
			mView.SetSelection (line, idx, otherLine, otherIndex + highlightLen);
			
		return S_OK;
	}
	
	//////////////////////////////
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
		
		int line, idx, len;
		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;
		if(ch != '\n')
			idx--;
		else if(mCodeWinMgr.mSource.mBuffer.GetLengthOfLine(line, &len) == S_OK && len > 0)
			return ReindentLines();

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
			compAct.OpenCompoundAction("ReindentLines"w.ptr);
		
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
	int PasteFromRing()
	{
		if(auto svc = queryService!(IVsToolbox, IVsToolboxClipboardCycler))
		{
			scope(exit) release(svc);
			wstring[] entries;
			int[] entryIndex;
			int cntEntries = 0;
			
			svc.BeginCycle();
			IVsToolboxUser tbuser = qi_cast!IVsToolboxUser(mView);
			scope(exit) release(tbuser);
			BOOL itemsAvailable;
			if(svc.AreDataObjectsAvailable(tbuser, &itemsAvailable) == S_OK && itemsAvailable)
			{
				IDataObject firstDataObject;
				IDataObject pDataObject;
				while(entries.length < 30 && 
					  svc.GetAndSelectNextDataObject(tbuser, &pDataObject) == S_OK)
				{
					scope(exit) release(pDataObject);
			
					if(pDataObject is firstDataObject)
						break;
					if(!firstDataObject)
						firstDataObject = addref(pDataObject);
						
					FORMATETC fmt;
					fmt.cfFormat = CF_UNICODETEXT;
					fmt.ptd = null;
					fmt.dwAspect = DVASPECT_CONTENT;
					fmt.lindex = -1;
					fmt.tymed = TYMED_HGLOBAL;
    
					STGMEDIUM medium;
					if(pDataObject.GetData(&fmt, &medium) == S_OK)
					{
						if(medium.tymed == TYMED_HGLOBAL)
						{
							wstring s = UtilGetStringFromHGLOBAL(medium.hGlobal);
							.GlobalFree(medium.hGlobal);

							s = createPasteString(s);
							if(!contains(entries, s))
							{
								entries ~= s;
								entryIndex ~= cntEntries;
							}
						}
					}
					cntEntries++;
				}
				release(firstDataObject);
				
				if(entries.length > 0)
				{
					TextSpan span;
					if(mView.GetCaretPos (&span.iStartLine, &span.iStartIndex) == S_OK)
					{
						span.iEndLine = span.iStartLine;
						span.iEndIndex = span.iStartIndex;
						mView.EnsureSpanVisible(span);
						POINT pt;
						if(mView.GetPointOfLineColumn (span.iStartLine, span.iStartIndex, &pt) == S_OK)
						{
							int height;
							mView.GetLineHeight (&height);
							pt.y += height;
							
							HWND hwnd = cast(HWND) mView.GetWindowHandle();
							ClientToScreen(hwnd, &pt);
							for(int k = 0; k < 10 && k < entries.length; k++)
								entries[k] = entries[k] ~ "\t(&" ~ cast(wchar)('0' + ((k + 1) % 10)) ~ ")";
							int sel = PopupContextMenu(hwnd, pt, entries);
							
							if(sel >= 0 && sel < entryIndex.length)
							{
								int cnt = entryIndex[sel];
								svc.BeginCycle();
								for(int i = 0; i <= cnt; i++)
								{
									if(svc.GetAndSelectNextDataObject(tbuser, &pDataObject) == S_OK)
										release(pDataObject);
								}
								return E_NOTIMPL; // forward to VS for insert
							}
						}
					}
				}
				return S_OK; // do not pass to VS, insert cancelled
			}
		}
		return E_NOTIMPL; // forward to VS for insert
	}

	//////////////////////////////////////////////////////////////
	int RemoveUnittests()
	{
		int endLine, endCol;
		mCodeWinMgr.mSource.GetLastLineIndex(endLine, endCol);
		wstring wtxt = mCodeWinMgr.mSource.GetText(0, 0, endLine, endCol);
		ReplaceOptions opt;
version(none)
{
		string txt = to!string(wtxt);
		string rtxt = replaceTokenSequence(txt, "unittest { $any }", "", opt, null);
		if(txt == rtxt)
			return S_OK;
		wstring wrtxt = to!wstring(rtxt);
}
else
		wstring wrtxt = replaceTokenSequence(wtxt, 1, 0, "unittest { $any }", "", opt, null);
		
		TextSpan changedSpan;
		return mCodeWinMgr.mSource.mBuffer.ReplaceLines(0, 0, endLine, endCol, wrtxt.ptr, wrtxt.length, &changedSpan);
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
		
	int _HandleMethodTip(bool tryUpper = true)
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
			if(!tryUpper)
				return S_FALSE;
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
		// not working without debugger, see Package.SetSite: QueryService(&IVsDebugger)
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
		mCodeWinMgr.mLangSvc.mLastActiveView = this;
		return S_OK;
	}

	override int OnKillFocus(IVsTextView pView)
	{
		mixin(LogCallMix);
		if(mCodeWinMgr.mLangSvc.mLastActiveView is this)
			mCodeWinMgr.mLangSvc.mLastActiveView = null;
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

	bool OnIdle()
	{
		int line;
		ViewCol idx;

		if(int rc = mView.GetCaretPos(&line, &idx))
			return false;
		if(mLastHighlightBracesLine == line && mLastHighlightBracesCol == idx)
			return false;
			
		mLastHighlightBracesLine = line;
		mLastHighlightBracesCol = idx;
		HighlightMatchingPairs();
		
version(tip)
{
		string msg = mCodeWinMgr.mSource.getParseError(line, idx);
		if(msg.length)
		{
			mTextTipData.Init(mView, msg);
			mTextTipData.UpdateView();
		}
		else
			mTextTipData.Dismiss();
}
		return true;
	}
}

class TextTipData : DisposingComObject, IVsTextTipData
{
	IVsTextTipWindow mTipWindow;
	IVsTextView mTextView;
	string mTipText;
	bool mDisplayed;
	
	this()
	{
		mTipText = "Tipp";
		mTipWindow = VsLocalCreateInstance!IVsTextTipWindow (&uuid_coclass_VsTextTipWindow, sdk.win32.wtypes.CLSCTX_INPROC_SERVER);
		if (mTipWindow)
			mTipWindow.SetTextTipData(this);
	}
	
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsTextTipData) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void Init(IVsTextView textView, string tip)
	{
		Close();
		mTextView = textView;
		mTipText = tip;
		mDisplayed = false;
	}
	
	void Close()
	{
		Dismiss();
	}

	void Dismiss()
	{
		if (mDisplayed && mTextView)
			mTextView.UpdateTipWindow(mTipWindow, UTW_DISMISS);
		OnDismiss();
	}

	override void Dispose()
	{
		Close();
		if (mTipWindow)
			mTipWindow.SetTextTipData(null);
		mTipWindow = release(mTipWindow);
	}

	HRESULT GetTipText (/+[out, custom(uuid_IVsTextTipData, "optional")]+/ BSTR *pbstrText, 
		/+[out]+/ BOOL *pfGetFontInfo)
	{
		if(pbstrText)
			*pbstrText = allocBSTR(mTipText);
		if(pfGetFontInfo)
			*pfGetFontInfo = FALSE;
		return S_OK;
	}

	// NOTE: *pdwFontAttr will already have been memset-ed to zeroes, so you can set only the indices that are not normal
    HRESULT GetTipFontInfo (in int cChars, /+[out, size_is(cChars)]+/ ULONG *pdwFontAttr)
	{
		return E_NOTIMPL;
	}
	
	HRESULT GetContextStream(/+[out]+/ int *piPos, /+[out]+/ int *piLength)
	{
		int line, idx, vspace, endpos;
		if(HRESULT rc = mTextView.GetCaretPos(&line, &idx))
			return rc;
		if(HRESULT rc = mTextView.GetNearestPosition(line, idx, piPos, &vspace))
			return rc;

		*piLength = 1;
		return S_OK;
	}
	
	HRESULT OnDismiss ()
	{
		mTextView = null;
		mDisplayed = false;
		return S_OK;
	}
	
	HRESULT UpdateView ()
	{
		if (mTextView && mTipWindow)
		{
			mTextView.UpdateTipWindow(mTipWindow, UTW_CONTENTCHANGED);
			mDisplayed = true;
		}
		return S_OK;
	}
}
