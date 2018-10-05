// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.viewfilter;

import visuald.windows;
import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.dpackage;
import visuald.dproject;
import visuald.hierarchy;
import visuald.chiernode;
import visuald.dimagelist;
import visuald.completion;
import visuald.simpleparser;
import visuald.intellisense;
import visuald.searchsymbol;
import visuald.expansionprovider;
import visuald.dlangsvc;
import visuald.winctrl;
import visuald.tokenreplace;
import visuald.cppwizard;
import visuald.config;
import visuald.build;
import visuald.help;
import visuald.lexutil;

import vdc.lexer;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.textmgr120;
import sdk.vsi.stdidcmd;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vsshell90;
import sdk.vsi.vsdbgcmd;
import sdk.vsi.vsdebugguids;
import sdk.vsi.msdbg;
import sdk.win32.wtypes;

import stdext.array;
import stdext.path;
import stdext.string;
import stdext.ddocmacros;

import std.string;
import std.ascii;
import std.utf;
import std.conv;
import std.algorithm;
import std.array;
import std.file;
import std.path;

///////////////////////////////////////////////////////////////////////////////

interface IVsCustomDataTip : IUnknown
{
	static const GUID iid = uuid("80DD0557-F6FE-48e3-9651-398C5E7D8D78");

	HRESULT DisplayDataTip();
}

// version = tip;

class ViewFilter : DisposingComObject, IVsTextViewFilter, IOleCommandTarget,
                   IVsTextViewEvents, IVsExpansionEvents
{
	CodeWindowManager mCodeWinMgr;
	IVsTextView mView;
	uint mCookieTextViewEvents;
	IOleCommandTarget mNextTarget;

	int mLastHighlightBracesLine;
	ViewCol mLastHighlightBracesCol;

	static const GUID iid = { 0xd143496a, 0xc795, 0x428d, [ 0x8c, 0xfe, 0x96, 0x88, 0xcf, 0x19, 0x5e, 0x3f ] };

version(tip)
	TextTipData mTextTipData;

	this(CodeWindowManager mgr, IVsTextView view)
	{
		mCodeWinMgr = mgr;
		mView = addref(view);
		mCookieTextViewEvents = Advise!(IVsTextViewEvents)(mView, this);

		mView.AddCommandFilter(this, &mNextTarget);
		hookWindowProc(cast(HWND) mView.GetWindowHandle());

version(tip)
		mTextTipData = addref(newCom!TextTipData);
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
		unhookWindowProc();
		mCodeWinMgr = null;
	}

	WNDPROC mPrevProc;
	HWND mHwnd;

	static ViewFilter[HWND] sHooks;

	extern(Windows) static int WindowProcHook(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		WNDPROC proc;
		ViewFilter* pvf = hWnd in sHooks;
		if (pvf)
			proc = pvf.mPrevProc;
		if(!proc)
			proc = &DefWindowProcA;
		int res = proc(hWnd,uMsg,wParam,lParam);

		if(Package.GetGlobalOptions().showCoverageMargin)
			if(uMsg == WM_PAINT && pvf)
				pvf.mCodeWinMgr.mSource.mColorizer.drawCoverageOverlay(hWnd, wParam, lParam, pvf.mView);

		return res;
	}

	bool hookWindowProc(HWND hwnd)
	{
		if(mHwnd)
			return false;

		mPrevProc = cast(WNDPROC)GetWindowLongPtr(hwnd, GWL_WNDPROC);
		mHwnd = hwnd;
		sHooks[mHwnd] = this;
		SetWindowLongPtr(hwnd, GWL_WNDPROC, cast(uint) &WindowProcHook);
		return true;
	}

	bool unhookWindowProc()
	{
		if(!mHwnd)
			return false;

		SetWindowLongPtr(mHwnd, GWL_WNDPROC, cast(uint) mPrevProc);
		sHooks.remove(mHwnd);
		mHwnd = null;
		mPrevProc = null;
		return true;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(ViewFilter) (this, riid, pvObject))
			return S_OK;
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

		Package.GetLanguageService().OnExec();

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
				return HandleGotoDef(false);
			case cmdidGotoDecl:
				return HandleGotoDef(true);
			case cmdidFindReferences:
				return HandleFindReferences();
			case cmdidF1Help:
				return HandleHelp();
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
					initCompletion(true);
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

			case ECMD_COMPILE:
				return CompileDoc(false, false, false, false);

			case ECMD_GOTOBRACE:
				return GotoMatchingPair(false);
			case ECMD_GOTOBRACE_EXT:
				return GotoMatchingPair(true);

			case ECMD_OUTLN_STOP_HIDING_ALL:
				return mCodeWinMgr.mSource.StopOutlining();
			case ECMD_OUTLN_TOGGLE_ALL:
				return mCodeWinMgr.mSource.ToggleOutlining();

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

			case CmdConvSelection:
				return ConvertSelection();

			case CmdCompileAndRun:
				return CompileDoc(true, true, false, false);

			case CmdCompileAndDbg:
				return CompileDoc(true, false, true, false);

			case CmdCompileAndAsm:
				return CompileDoc(false, false, false, true);

			case CmdCollapseUnittest:
				return mCodeWinMgr.mSource.CollapseDisabled(true, false);

			case CmdCollapseDisabled:
				return mCodeWinMgr.mSource.CollapseDisabled(false, true);

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

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch (nCmdID)
			{
			case cmdidPasteNextTBXCBItem:
			case cmdidPaste:
				ReindentPastedLines();
				break;
			default:
				break;
			}
		}
		if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K)
		{
			switch (nCmdID)
			{
			case ECMD_RETURN:
				if(!wasCompletorActive)
				{
					HandleBraceCompletion('\n');
					HandleSmartIndent('\n');
				}
				break;

			case ECMD_LEFT:
			case ECMD_WORDPREV:
			case ECMD_RIGHT:
			case ECMD_WORDNEXT:
				stopCompletions();
				goto case ECMD_UP;

			case ECMD_BACKSPACE:
				if(mCodeWinMgr.mSource.IsCompletorActive())
					initCompletion(false);
				goto case;

			case ECMD_UP:
			case ECMD_DOWN:
				if(mCodeWinMgr.mSource.IsMethodTipActive())
					HandleMethodTip();
				break;

			case ECMD_TYPECHAR:
				dchar ch = pvaIn.uiVal;
				if(ch == '.' && Package.GetGlobalOptions().expandTrigger >= 1 && Package.GetGlobalOptions().expandFromSemantics)
					initCompletion(false);

				else if(mCodeWinMgr.mSource.IsCompletorActive() || Package.GetGlobalOptions().expandTrigger >= 2)
				{
					if(dLex.isIdentifierChar(ch))
						initCompletion(false);
					else
						stopCompletions();
				}

				if(ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '(' || ch == ')' ||
				   ch == '"' || ch == '`' || ch == '\'')
					HandleBraceCompletion(ch);

				if(ch == '{' || ch == '}' || ch == '[' || ch == ']' ||
				   ch == 'n' || ch == 't' || ch == 'y') // last characters of "in", "out" and "body"
					HandleSmartIndent(ch);

				if(mCodeWinMgr.mSource.IsMethodTipActive())
				{
					if(ch == ',' || ch == ')')
						HandleMethodTip();
				}
				else if(ch == '(')
				{
					LANGPREFERENCES3 langPrefs;
					if(GetUserPreferences(&langPrefs, null) == S_OK && langPrefs.fAutoListParams)
						_HandleMethodTip(false);
				}
				break;
			case ECMD_HANDLEIMEMESSAGE:
			case ECMD_PAGEUP:
			case ECMD_PAGEDN:
				break;
			default:
				if(nCmdID < ECMD_FINAL)
					stopCompletions();
				break;
			}
		}

		// delayed into idle: HighlightMatchingPairs();
		return rc;
	}

	//////////////////////////////

	HRESULT CompileDoc(bool rdmd, bool run, bool dbg, bool disasm)
	{
		IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
		if(!pIVsUIShellOpenDocument)
			return returnError(E_FAIL);
		scope(exit) release(pIVsUIShellOpenDocument);

		string fname = mCodeWinMgr.mSource.GetFileName();
		wchar* wfname = _toUTF16z(fname);
		string addopt;

		Config cfg = getProjectConfig(fname, true);
		scope(exit) release(cfg); // must not dispose because we need the builder

		CFileNode pFile;
		BSTR bstrSelText;
		string selText;
		if(mView.GetSelectedText(&bstrSelText) == S_OK && !disasm)
			selText = detachBSTR(bstrSelText);

		if(cfg)
		{
			string docName = toLower(fname);
			CHierNode node = searchNode(cfg.GetProject().GetRootNode(), delegate (CHierNode n) { return n.GetCanonicalName() == docName; });
			pFile = cast(CFileNode) node;
			assert(pFile);
		}
		else
		{
			// not in Visual D project, but in workspace project
			string platform, config = GetActiveSolutionConfig(&platform);
			if (config.empty)
				platform = "Win32", config = "Debug";

			string filename = normalizeDir(tempDir()) ~ "__compile__.vdproj";
			cfg = newCom!VCConfig(filename, "__compile__", platform, config).addref();
			cfg.GetProjectOptions().outdir = normalizeDir(tempDir()) ~ "__vdcompile";
			cfg.GetProjectOptions().release = false;

			Project prj = newCom!Project(Package.GetProjectFactory(), "__compile__", filename, platform, config);
			pFile = newCom!CFileNode(fname);
			prj.GetRootNode().AddTail(pFile);

			string modname = getModuleDeclarationName(fname);
			if(modname.length)
			{
				// add the path that seems to be the root of the package
				string ipath;
				while(findSkip(modname, "."))
					ipath ~= "/..";
				if(ipath.length)
					addopt ~= " -I" ~ normalizeDir(dirName(fname)) ~ ipath[1..$];
			}
		}

		bool eval = rdmd && selText.length;
		if(!eval)
		{
			if(!pFile || saveTextBuffer(fname) != S_OK)
				return returnError(E_FAIL);

			mCodeWinMgr.mSource.OnBufferSave(null); // save current modification position
		}

		auto symdebug = cfg.GetProjectOptions().symdebug;
		scope(exit) cfg.GetProjectOptions().symdebug = symdebug;

		if (disasm && symdebug == 0) // ensure debug info is enabled
			cfg.GetProjectOptions().symdebug = 3;

		string stool = pFile ? cfg.GetStaticCompileTool(pFile, cfg.getCfgName()) : "DMDsingle";
		if(stool == "DMD")
			stool = "DMDsingle";
		if(stool == "DMDsingle" && rdmd)
		{
			stool = "RDMD";
			if(selText.length)
			{
				string[] lines = splitLines(selText);
				foreach(ln; lines)
				{
					string line = strip(detab(ln));
					if(line.length)
						addopt ~= ` "--eval=` ~ replace(line, `"`, `\"`) ~ `"`;
				}
				stool = "RDMDeval";
			}
		}
		if(eval)
			addopt = " " ~ Package.GetGlobalOptions().compileAndRunOpts ~ addopt;
		else if(stool == "RDMD" && run)
			addopt = " --build-only " ~ Package.GetGlobalOptions().compileAndRunOpts ~ addopt;
		else if(stool == "RDMD" && dbg)
			addopt = " --build-only " ~ Package.GetGlobalOptions().compileAndDbgOpts ~ addopt;

		string cmd = cfg.GetCompileCommand(pFile, !dbg && !run && !disasm && !eval, stool, addopt);
		if(cmd.length)
		{
			cmd ~= "if %errorlevel% == 0 echo Compilation successful.\n";
			string workdir = cfg.GetProjectDir();
			string outfile = cfg.GetOutputFile(pFile, stool);
			outfile = makeFilenameAbsolute(outfile, workdir);
			string cmdfile = outfile ~ ".syntax";
			removeCachedFileTime(outfile);

			if(disasm)
			{
				string asmfile = outfile ~ ".asm";
				string linfile = outfile ~ ".lines";
				cmd ~= "if %errorlevel% neq 0 exit %ERRORLEVEL% /B\n";
				cmd ~= "echo Dumping disassembly\n";
				cmd ~= cfg.GetDisasmCommand(outfile, asmfile) ~ "\n";
				cmd ~= "if %errorlevel% neq 0 exit %ERRORLEVEL% /B\n";
				cmd ~= "echo Dumping line numbers\n";
				cmd ~= "\"" ~ Package.GetGlobalOptions().VisualDInstallDir ~ "cv2pdb\\dumplines.exe\" " ~ quoteFilename(outfile)
					~ " > " ~ quoteFilename(linfile) ~ "\n";
			}
			if(run && !eval)
			{
				cmd ~= "if %errorlevel% neq 0 exit %ERRORLEVEL% /B\n";
				cmd ~= quoteFilename(outfile) ~ "\n";
				cmd ~= "echo Execution result code: %ERRORLEVEL%\n";
			}

			auto pane = getVisualDOutputPane();
			scope(exit) release(pane);
			clearOutputPane();
			if(pane)
				pane.Activate();

			auto builder = new CBuilderThread(cfg);
			HRESULT hr = RunCustomBuildBatchFile(outfile, cmdfile, cmd, pane, builder);
			builder.Dispose();

			if(run && !eval)
				Package.GetGlobalOptions().addExecutionPath(workdir, null);

			if(hr == S_OK)
			{
				if(dbg && !eval)
					cfg._DebugLaunch(outfile, dirName(fname), null, Package.GetGlobalOptions().compileAndDbgEngine);
				if(disasm)
					mCodeWinMgr.mSource.setDisasmFiles(outfile ~ ".asm", outfile ~ ".lines");
			}
		}
		return S_OK;
	}

	//////////////////////////////

	void initCompletion(bool autoInsert)
	{
		CompletionSet cs = mCodeWinMgr.mSource.GetCompletionSet();
		Declarations decl = new Declarations;
		decl.StartExpansions(mView, mCodeWinMgr.mSource, autoInsert);
	}
	void moreCompletions()
	{
		CompletionSet cs = mCodeWinMgr.mSource.GetCompletionSet();
		Declarations decl = cs.mDecls;
		decl.MoreExpansions(mView, mCodeWinMgr.mSource);
	}
	void stopCompletions()
	{
		if(CompletionSet cs = mCodeWinMgr.mSource.GetCompletionSet())
			if(Declarations decl = cs.mDecls)
				decl.StopExpansions();
		mCodeWinMgr.mSource.DismissCompletor();
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
			case cmdidGotoDecl:
			case cmdidFindReferences:
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
			case ECMD_OUTLN_STOP_HIDING_ALL:
			case ECMD_OUTLN_TOGGLE_ALL:
			case ECMD_COMPILE:
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
			case CmdConvSelection:
			case CmdCompileAndRun:
			case CmdCompileAndDbg:
			case CmdCompileAndAsm:
			case CmdCollapseUnittest:
			case CmdCollapseDisabled:
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
		size_t idxpos = idx;
		if(Lexer.isStartingComment(txt, idxpos))
		{
			idx = cast(ViewCol) idxpos;
			tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(pos == idx)
			{
				int startState = iState;
				if(dLex.scan(iState, txt, pos) == TokenCat.Comment)
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
		if(Lexer.isEndingComment(txt, idxpos))
		{
			idx = cast(ViewCol) idxpos;
			tokidx = mCodeWinMgr.mSource.FindLineToken(line, idx, iState, pos);
			if(tokidx >= 0)
			{
				int startState = iState;
				uint startpos = pos;
				if(dLex.scan(iState, txt, pos) == TokenCat.Comment)
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
							if(lineInfo[tokidx].type != TokenCat.Comment)
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
		int type = dLex.scan(iState, txt, pos);
		if(type == TokenCat.String)
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
		int toktype = dLex.scan(iState, text, pos);
		if(toktype != TokenCat.Operator)
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
	int ConvertSelection()
	{
		if(convertSelection(mView))
			return S_OK;
		return S_FALSE;
	}

	//////////////////////////////////////////////////////////////
	int HandleSmartIndent(dchar ch)
	{
		LANGPREFERENCES3 langPrefs;
		if(int rc = GetUserPreferences(&langPrefs, mView))
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
		wstring trimmed;
		if(std.ascii.isAlpha(ch) && ((trimmed = strip(linetxt)) == "in" || trimmed == "out" || trimmed == "body"))
			return ReindentLines();
		if(idx > p || (ch != '\n' && linetxt[p] != ch))
			return S_FALSE; // do nothing if not at beginning of line

		Source.CacheLineIndentInfo cacheInfo;
		int n = mCodeWinMgr.mSource.CalcLineIndent(line, ch, &langPrefs, cacheInfo);
		if(n < 0 || n == orgn)
			return S_OK;

		if(ch == '\n')
			return mView.SetCaretPos(line, n);
		else
			return mCodeWinMgr.mSource.doReplaceLineIndent(line, p, n, &langPrefs);
	}

	int ReindentLines()
	{
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		int hr = GetSelectionForward(mView, &iStartLine, &iStartIndex, &iEndLine, &iEndIndex);
		if(FAILED(hr)) // S_FALSE if no selection, but caret-coordinates returned
			return hr;
		return ReindentLines(iStartLine, iEndLine);
	}

	int ReindentLines(int iStartLine, int iEndLine)
	{
		if(iEndLine < iStartLine)
			std.algorithm.swap(iStartLine, iEndLine);

		IVsCompoundAction compAct = qi_cast!IVsCompoundAction(mView);
		if(compAct)
			compAct.OpenCompoundAction("ReindentLines"w.ptr);

		int hr = mCodeWinMgr.mSource.ReindentLines(mView, iStartLine, iEndLine);

		if(compAct)
		{
			compAct.CloseCompoundAction();
			compAct.Release();
		}
		return hr;
	}

	int ReindentPastedLines()
	{
		if(Package.GetGlobalOptions().pasteIndent)
			with(mCodeWinMgr.mSource.mLastTextLineChange)
				if(iStartLine != iNewEndLine)
					return ReindentLines(iStartLine, iNewEndLine);
		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	int HandleBraceCompletion(dchar ch)
	{
		// character ch already inserted, caret placed right after it
		LANGPREFERENCES3 langPrefs;
		if(int rc = GetUserPreferences(&langPrefs, mView))
			return rc;
		if(!langPrefs.fBraceCompletion)
			return S_FALSE;

		int line, idx;
		if(int rc = mView.GetCaretPos(&line, &idx))
			return rc;

		if(int rc = mCodeWinMgr.mSource.AutoCompleteBrace(line, idx, ch, langPrefs))
			return rc;

		// restore caret position, it has been moved by the insertion
		if(int rc = mView.SetCaretPos(line, idx))
			return rc;

		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	int CommentLines(int commentMode)
	{
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		int hr = GetSelectionForward(mView, &iStartLine, &iStartIndex, &iEndLine, &iEndIndex);
		if(FAILED(hr)) // S_FALSE if no selection, but caret-coordinates returned
			return hr;
		if(iEndIndex == 0 && iEndLine > iStartLine)
			iEndLine--;

		IVsCompoundAction compAct = qi_cast!IVsCompoundAction(mView);
		if(compAct)
			compAct.OpenCompoundAction("CommentLines"w.ptr);

		hr = mCodeWinMgr.mSource.CommentLines(mView, iStartLine, iEndLine, commentMode);
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
	int HandleGotoDef(bool decl)
	{
		int line, idx;
		if(mView.GetCaretPos(&line, &idx) != S_OK)
			return S_FALSE;

		string file = mCodeWinMgr.mSource.GetFileName();
		wstring impw = mCodeWinMgr.mSource.GetImportModule(line, idx, false);
		if(impw.length)
		{
			string imp = to!string(impw);
			imp = replace(imp, ".", "\\") ~ ".d";
			HRESULT hr = OpenFileInSolution(imp, -1, 0, file, false); // also searches import paths
			if(hr != S_OK)
			{
				imp ~= "i";
				hr = OpenFileInSolution(imp, -1, 0, file, false);
				if(hr != S_OK)
				{
					imp = imp[0 .. $-3] ~ "\\package.d";
					hr = OpenFileInSolution(imp, -1, 0, file, false);
				}
			}
			if (hr == S_OK)
				return hr;
		}

		if(Package.GetGlobalOptions().semanticGotoDef)
		{
			TextSpan span;
			span.iStartLine  = span.iEndLine  = line;
			span.iStartIndex = span.iEndIndex = idx;
			if (!mCodeWinMgr.mSource.GetTipSpan(&span))
				return S_FALSE;
			mLastGotoDecl = decl;
			mLastGotoDef = to!string(mCodeWinMgr.mSource.GetText(span.iStartLine, span.iStartIndex, span.iEndLine, span.iEndIndex));
			Package.GetLanguageService().GetDefinition(mCodeWinMgr.mSource, &span, &GotoDefinitionCallBack);
			return S_FALSE;
		}
		else
		{
			string word = toUTF8(GetWordAtCaret());
			if(word.length <= 0)
				return S_FALSE;

			return GotoDefinitionJSON(file, word);
		}
	}

version(all)
	HRESULT GotoDefinitionCPP(string word)
	{
		if(auto objmgr = queryService!(IVsObjectManager))
		{
			scope(exit) release(objmgr);
			if(auto objmgr2 = qi_cast!IVsObjectManager2(objmgr))
			{
				scope(exit) release(objmgr2);
				IVsEnumLibraries2 enumLibs;
				if(objmgr2.EnumLibraries(&enumLibs) == S_OK)
				{
					VSOBSEARCHCRITERIA2 searchOpts;
					searchOpts.szName = _toUTF16z(word);
					searchOpts.eSrchType = SO_ENTIREWORD;
					searchOpts.grfOptions = VSOBSO_CASESENSITIVE;

					scope(exit) release(enumLibs);
					DWORD fetched;
					IVsLibrary2 lib;
					while(enumLibs.Next(1, &lib, &fetched) == S_OK && fetched == 1)
					{
						scope(exit) release(lib);
						if(auto slib = qi_cast!IVsSimpleLibrary2(lib))
						{
							scope(exit) release(slib);
							IVsSimpleObjectList2 reslist;
							if(slib.GetList2(LLT_MEMBERS, LLF_USESEARCHFILTER, &searchOpts, &reslist) == S_OK)
							{
								scope(exit) release(reslist);
								ULONG items;
								if(reslist.GetItemCount(&items) == S_OK && items > 0)
								{
									BOOL ok;
									for(ULONG it = 0; it < items; it++)
										if(reslist.CanGoToSource(it, GS_DEFINITION, &ok) == S_OK && ok)
											if(reslist.GoToSource(it, GS_DEFINITION) == S_OK)
												return S_OK;
								}
							}
						}
					}
				}
			}
		}
		return S_FALSE;
	}
else
	HRESULT GotoDefinitionCPP()
	{
		if(auto navmgr = queryService!(SVsSymbolicNavigationManager, IVsSymbolicNavigationManager))
		{
			scope(exit) release(navmgr);

			string word = toUTF8(GetWordAtCaret());

			IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
			if(!pIVsUIShellOpenDocument)
				return returnError(E_FAIL);
			scope(exit) release(pIVsUIShellOpenDocument);

			string fname = mCodeWinMgr.mSource.GetFileName();
			wchar* wfname = _toUTF16z(fname);
			string addopt;

			IVsUIHierarchy pUIH;
			uint itemid;
			IServiceProvider pSP;
			VSDOCINPROJECT docInProj;
			if(pIVsUIShellOpenDocument.IsDocumentInAProject(wfname, &pUIH, &itemid, &pSP, &docInProj) != S_OK)
				return S_OK;

			scope(exit) release(pSP);
			scope(exit) release(pUIH);

			if(!pUIH)
				return returnError(E_FAIL);
			Project proj = qi_cast!Project(pUIH);
			scope(exit) release(proj);

			BOOL handled;
			HRESULT hr = navmgr.OnBeforeNavigateToSymbol(proj, itemid, _toUTF16z(word), &handled);
			if(hr == S_OK && handled)
				return hr;
		}
		return S_FALSE;
	}

	HRESULT GotoDefinitionJSON(string file, string word)
	{
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

		string deffile = defs[0].filename;
		int    defline = defs[0].line;

		HRESULT hr = OpenFileInSolution(deffile, defline, 0, file, true);
		if(hr != S_OK)
			showStatusBarText(format("Cannot open %s(%d) for definition of '%s'", deffile, defline, word));
		return hr;
	}

	extern(D)
	void GotoDefinitionCallBack(uint request, string fname, sdk.vsi.sdk_shared.TextSpan span)
	{
		bool extrn = fname.startsWith("EXTERN:");
		if (extrn)
			fname = fname[7..$];

		if (extrn && !mLastGotoDecl)
		{
			string word = split(mLastGotoDef, ".")[$-1];
			if(GotoDefinitionCPP(word) == S_OK)
				return;
		}
		if (fname.length)
		{
			HRESULT hr = OpenFileInSolution(fname, span.iStartLine, span.iStartIndex, null, false);
			if(hr != S_OK)
				showStatusBarText(format("Cannot open %s(%d) for goto definition", fname, span.iStartLine));
		}
		else
		{
			string word = split(mLastGotoDef, ".")[$-1];
			GotoDefinitionJSON(mCodeWinMgr.mSource.GetFileName(), word);
			//showStatusBarText("No definition found for '" ~ mLastGotoDef ~ "'");
		}
	}

	//////////////////////////////////////////////////////////////
	int HandleFindReferences()
	{
		int line, idx;
		if(mView.GetCaretPos(&line, &idx) != S_OK)
			return S_FALSE;

		Package.GetLanguageService().GetReferences(mCodeWinMgr.mSource, "", line, idx, &FindReferencesCallBack);
		return S_FALSE;
	}

	extern(D)
	void FindReferencesCallBack(uint request, string filename, string tok, int line, int idx, string[] exps)
	{
		if(IVsFindSymbol fs = queryService!(IVsObjectSearch, IVsFindSymbol))
		{
			scope(exit) release(fs);

			VSOBSEARCHCRITERIA2 criteria;
			criteria.dwCustom = 0; // FindReferencesResults;
			criteria.eSrchType = SO_ENTIREWORD,
			criteria.grfOptions = VSOBSO_LISTREFERENCES,
			criteria.pIVsNavInfo = null,
			criteria.szName = "Find All References";

			if (auto lib = Package.s_instance.GetLibrary())
				lib.mLastFindReferencesResult = exps;

			fs.DoSearch(&GUID_VsSymbolScope_All, &criteria);
		}
	}

	//////////////////////////////////////////////////////////////
	int HandleHelp()
	{
		string word = toUTF8(GetWordAtCaret());
		if(word.length <= 0)
			return S_FALSE;

		if(!openHelp(word))
			showStatusBarText(text("No documentation found for '", word, "'."));

		return S_OK;
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
		string word = toUTF8(src.FindMethodIdentifierBackward(otherLine, tok, &line, &idx));
		if(word.length <= 0)
		{
			line = otherLine;
			idx = otherIndex;
			if(!tryUpper)
				return S_FALSE;
			goto stepUp;
		}

		span.iStartIndex = idx;
		span.iStartLine = line;
		span.iEndIndex = idx + 1;
		span.iEndLine = line;

		mPendingMethodTipWord = word;
		mPendingMethodTipComma = cntComma;
		mPendingRequest = Package.GetLanguageService().GetTip(mCodeWinMgr.mSource, &span, &OnGetMethodTipText);
		return S_OK;
	}

	extern(D) void OnGetMethodTipText(uint request, string filename, string text, TextSpan span)
	{
		Definition[] defs;
		string[] funcs = split(text, "\a");
		if(funcs.empty)
		{
			defs = Package.GetLibInfos().findDefinition(mPendingMethodTipWord);
		}
		else
		{
			foreach(fn; funcs)
			{
				Definition def;
				def.name = mPendingMethodTipWord;
				int pos = fn.indexOf("\n");
				if(pos >= 0)
				{
					def.help = fn[pos + 1 .. $];
					if(def.help.startsWith("(Deduced Type"))
						if(!findSkip(def.help, "\n"))
							def.help = "";
					fn = fn[0 .. pos];
				}
				if(fn.endsWith("\r"))
					fn = fn[0..$-1];
				if(fn.endsWith(":"))
					fn = fn[0..$-1];
				def.setType(fn);
				defs ~= def;
			}
		}
		RefreshMethodTip(defs, span);
	}

	int RefreshMethodTip(Definition[] defs, TextSpan span)
	{
		if(defs.length == 0)
			return S_FALSE;

		MethodData md = mCodeWinMgr.mSource.GetMethodData();
		span.iEndLine = span.iStartLine;
		span.iEndIndex = span.iStartIndex + 1;
		md.Refresh(mView, defs, mPendingMethodTipComma, span);

		return S_OK;
	}

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

		HRESULT resFwd = TIP_S_ONLYIFNOMARKER; // enable and prefer TextMarker tooltips
		TextSpan span = *pSpan;
		if(!mCodeWinMgr.mSource.GetTipSpan(pSpan))
			return resFwd;

		// when implementing IVsTextViewFilter, VS2010 will no longer ask the debugger
		//  for tooltips, so we have to do it ourselves
		if(IVsDebugger srpVsDebugger = queryService!(IVsDebugger))
		{
			scope(exit) release(srpVsDebugger);

			HRESULT hr = srpVsDebugger.GetDataTipValue(mCodeWinMgr.mSource.mBuffer, pSpan, null, pbstrText);
			if(hr == 0x45001) // always returned when debugger active, so no other tooltips then
			{
				if(IVsCustomDataTip tip = qi_cast!IVsCustomDataTip(srpVsDebugger))
				{
					scope(exit) release(tip);
					if(SUCCEEDED (tip.DisplayDataTip()))
						return S_OK;
				}
				else
					return hr;
			} // return hr; // this triggers HandoffNoDefaultTipToDebugger
		}

version(none) // quick info tooltips not good enough yet
{
		string word = toUTF8(mCodeWinMgr.mSource.GetText(pSpan.iStartLine, pSpan.iStartIndex, pSpan.iEndLine, pSpan.iEndIndex));
		if(word.length <= 0)
			return resFwd;

		Definition[] defs = Package.GetLibInfos().findDefinition(word);
		if(defs.length == 0)
			return resFwd;

		string msg = word;
		foreach(def; defs)
		{
			string m = "\n" ~ def.kind ~ "\t" ~ def.filename;
			if(def.line > 0)
				m ~= ":" ~ to!(string)(def.line);
			msg ~= m;
		}
		*pbstrText = allocBSTR(msg);
}
		if(Package.GetGlobalOptions().showTypeInTooltip)
		{
			if(mPendingSpan == span && mTipRequest == mPendingRequest)
			{
				*pbstrText = allocBSTR(mTipText);
				*pSpan = mTipSpan;
			}
			else
			{
				if(mPendingSpan != span)
				{
					mPendingSpan = span;
					mPendingRequest = Package.GetLanguageService().GetTip(mCodeWinMgr.mSource, &span, &OnGetTipText);
				}
				return E_PENDING;
			}
		}

		return resFwd;
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

	//////////////////////////////
	TextSpan mPendingSpan;
	uint mPendingRequest;
	int mPendingMethodTipComma;
	string mPendingMethodTipWord;
	TextSpan mTipSpan;
	string mTipText;
	uint mTipRequest;
	string mLastGotoDef;
	bool mLastGotoDecl;

	extern(D) void OnGetTipText(uint request, string filename, string text, TextSpan span)
	{
		text = replace(text, "\a", "\n\n");
		mTipText = phobosDdocExpand(text);

		mTipSpan = span;
		mTipRequest = request;

		version(tip)
		{
			mTextTipData.Init(mView, "Huu: " ~ text);
			mTextTipData.UpdateView();
		}
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
		auto uuid = uuid_coclass_VsTextTipWindow;
		mTipWindow = VsLocalCreateInstance!IVsTextTipWindow (&uuid, CLSCTX_INPROC_SERVER);
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

	HRESULT GetTipText(/+[out, custom(uuid_IVsTextTipData, "optional")]+/ BSTR *pbstrText,
		/+[out]+/ BOOL *pfGetFontInfo)
	{
		if(pbstrText)
			*pbstrText = allocBSTR(mTipText);
		if(pfGetFontInfo)
			*pfGetFontInfo = FALSE;
		return S_OK;
	}

	// NOTE: *pdwFontAttr will already have been memset-ed to zeroes, so you can set only the indices that are not normal
    HRESULT GetTipFontInfo(in int cChars, /+[out, size_is(cChars)]+/ ULONG *pdwFontAttr)
	{
		// needs *pfGetFontInfo = TRUE; above
		// 1 for bold
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

	HRESULT OnDismiss()
	{
		mTextView = null;
		mDisplayed = false;
		return S_OK;
	}

	HRESULT UpdateView()
	{
		if (mTextView && mTipWindow)
		{
			mTextView.UpdateTipWindow(mTipWindow, UTW_CONTENTCHANGED);
			mDisplayed = true;
		}
		return S_OK;
	}
}
