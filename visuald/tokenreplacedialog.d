// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.tokenreplacedialog;

import visuald.windows;
import visuald.winctrl;
import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.wmmsg;
import visuald.dpackage;
import visuald.dimagelist;
import visuald.tokenreplace;
import visuald.register;

import sdk.win32.commctrl;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import dte80a = sdk.vsi.dte80a;
import dte80 = sdk.vsi.dte80;

import std.algorithm;
import std.conv;

import stdext.array;

private IVsWindowFrame sWindowFrame;
private	TokenReplacePane sSearchPane;

const int  kPaneMargin = 0;
const int  kBackMargin = 4;

bool showTokenReplaceWindow(bool replace)
{
	if(!sWindowFrame)
	{
		auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
		if(!pIVsUIShell)
			return false;

		sSearchPane = newCom!TokenReplacePane();
		const(wchar)* caption = "Visual D Token Search/Replace"w.ptr;
		HRESULT hr;
		hr = pIVsUIShell.CreateToolWindow(CTW_fInitNew, 0, sSearchPane, 
										  &GUID_NULL, &g_tokenReplaceWinCLSID, &GUID_NULL, 
										  null, caption, null, &sWindowFrame);
		if(!SUCCEEDED(hr))
		{
			sSearchPane = null;
			return false;
		}
	}
	if(FAILED(sWindowFrame.Show()))
		return false;
	BOOL fHandled;
	sSearchPane._OnSetFocus(0, 0, 0, fHandled);
	return fHandled != 0;
}

bool findNextTokenReplace(bool up)
{
	if(!sSearchPane)
		return false;
	return sSearchPane._DoFindNext(up) == 0;
}

bool closeTokenReplaceWindow()
{
	sWindowFrame = release(sWindowFrame);
	sSearchPane = null;
	return true;
}

class TokenReplaceWindowBack : Dialog
{
	this(Window parent, TokenReplacePane pane)
	{
		mPane = pane;
		super(parent);
	}
	
	override LRESULT WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam) 
	{
		BOOL fHandled;
		LRESULT rc = mPane._WindowProc(hWnd, uMsg, wParam, lParam, fHandled);
		if(fHandled)
			return rc;
		
		return super.WindowProc(hWnd, uMsg, wParam, lParam);
	}
	
	TokenReplacePane mPane;
}

class TokenReplacePane : DisposingComObject, IVsWindowPane
{
	IServiceProvider mSite;

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsWindowPane) (this, riid, pvObject))
			return S_OK;
		
		// avoid debug output
		if(*riid == IVsCodeWindow.iid || *riid == IServiceProvider.iid || *riid == IVsTextView.iid)
			return E_NOINTERFACE;
		
		return super.QueryInterface(riid, pvObject);
	}
	
	override void Dispose()
	{
		mSite = release(mSite);
	}
	
	HRESULT SetSite(/+[in]+/ IServiceProvider pSP)
	{
		mixin(LogCallMix2);
		mSite = release(mSite);
		mSite = addref(pSP);
		return S_OK;
	}
	
	HRESULT CreatePaneWindow(in HWND hwndParent, in int x, in int y, in int cx, in int cy,
	                         /+[out]+/ HWND *hwnd)
	{
		mixin(LogCallMix2);

		_wndParent = new Window(hwndParent);
		_wndBack = new TokenReplaceWindowBack(_wndParent, this);

		BOOL fHandled;
		_OnInitDialog(WM_INITDIALOG, 0, 0, fHandled);
		_CheckSize();

		_wndBack.setVisible(true);
		return S_OK;
	}
	HRESULT GetDefaultSize(/+[out]+/ SIZE *psize)
	{
		mixin(LogCallMix2);
		psize.cx = 300;
		psize.cy = 200;
		return S_OK;
	}
	HRESULT ClosePane()
	{
		mixin(LogCallMix2);
		if(_wndParent)
		{
			_WriteStateToRegistry();

			_wndParent.Dispose();
			_wndParent = null;
			_wndBack = null;
			_wndToolbar = null;
			
			_wndFindLabel = null;
			_wndFindText = null;
			_wndReplaceLabel = null;
			_wndReplaceText = null;
			_wndMatchCase = null;
			_wndMatchBraces = null;
			_wndIncComment = null;
			_wndReplaceCase = null;
			_wndDirectionUp = null;
			_wndLookInLabel = null;
			_wndLookIn = null;
			_wndNext = null;
			_wndReplace = null;
			_wndReplaceAll = null;
			_wndClose = null;
			
			if(_himlToolbar)
				ImageList_Destroy(_himlToolbar);

			mDlgFont = deleteDialogFont(mDlgFont);
		}
		return S_OK;
	}
	HRESULT LoadViewState(/+[in]+/ IStream pstream)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}
	HRESULT SaveViewState(/+[in]+/ IStream pstream)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}
	HRESULT TranslateAccelerator(MSG* msg)
	{
		if(msg.message == WM_TIMER)
			_CheckSize();
		
		if(msg.message == WM_TIMER || msg.message == WM_SYSTIMER)
			return E_NOTIMPL; // do not flood debug output
		
		logMessage("TranslateAccelerator", msg.hwnd, msg.message, msg.wParam, msg.lParam);
		
		BOOL fHandled;
		LRESULT hrRet = _HandleMessage(msg.hwnd, msg.message, msg.wParam, msg.lParam, fHandled);

		if(fHandled)
			return cast(HRESULT)hrRet;
		return E_NOTIMPL;
	}

	///////////////////////////////////////////////////////////////////

	// the following has been ported from the FlatSolutionExplorer project
private:
	Window _wndParent;
	TokenReplaceWindowBack _wndBack;
	ToolBar _wndToolbar;
	HIMAGELIST _himlToolbar;
	ReplaceOptions _options;
	
	HFONT mDlgFont;
	int mTextHeight;
	int mTextWidth;
	Label         _wndFindLabel;
	MultiLineText _wndFindText;
	Label         _wndReplaceLabel;
	MultiLineText _wndReplaceText;
	CheckBox      _wndMatchCase;
	CheckBox      _wndMatchBraces;
	CheckBox      _wndIncComment;
	CheckBox      _wndReplaceCase;
	CheckBox      _wndDirectionUp;
	Label         _wndLookInLabel;
	ComboBox      _wndLookIn;
	Button        _wndNext;
	Button        _wndReplace;
	Button        _wndReplaceAll;
	Button        _wndClose;
		
	static HINSTANCE getInstance() { return Widget.getInstance(); }

	LRESULT _WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
	{
		if(uMsg != WM_NOTIFY)
			logMessage("_WindowProc", hWnd, uMsg, wParam, lParam);
		
		return _HandleMessage(hWnd, uMsg, wParam, lParam, fHandled);
	}
	
	LRESULT _HandleMessage(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
	{
		switch(uMsg)
		{
		case WM_CREATE:
		case WM_INITDIALOG:
			return _OnInitDialog(uMsg, wParam, lParam, fHandled);
		case WM_DESTROY:
			return _OnDestroy(uMsg, wParam, lParam, fHandled);
		case WM_SIZE:
			if(hWnd == _wndBack.hwnd)
				return _OnSize(uMsg, wParam, lParam, fHandled);
			break;
		case WM_KEYDOWN:
		case WM_SYSKEYDOWN:
			return _OnKeyDown(uMsg, wParam, lParam, fHandled);
		case WM_NCACTIVATE:
		case WM_SETFOCUS:
			return _OnSetFocus(uMsg, wParam, lParam, fHandled);
		case WM_COMMAND:
			ushort id = LOWORD(wParam);
			ushort code = HIWORD(wParam);
			
//			if(id == IDC_FINDTEXT && code == EN_CHANGE)
//				return _OnFileWheelChanged(id, code, hWnd, fHandled);
			
			if(code == BN_CLICKED)
			{
				switch(id)
				{
				case IDC_FINDCLOSE:
					sWindowFrame.Hide();
					return 0;
				case IDC_FINDNEXT:
					return _OnFindNext();
					
				case IDC_REPLACE:
					return _OnReplace();
				case IDC_REPLACEALL:
					return _OnReplaceAll();
				default:
					break;
				}
			}
			break;
/+
		case WM_NCCALCSIZE:
			return _OnCalcSize(uMsg, wParam, lParam, fHandled);
		case WM_CONTEXTMENU:
			return _OnContextMenu(uMsg, wParam, lParam, fHandled);
		case WM_NOTIFY:
			if (nmhdr.idFrom == IDC_TOOLBAR && nmhdr.code == TBN_GETINFOTIP)
				return _OnToolbarGetInfoTip(wParam, nmhdr, fHandled);
			break;
+/
		default:
			break;
		}
		return 0;
	}

	LRESULT _OnInitDialog(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		if(_wndFindLabel)
			return S_OK;

		updateEnvironmentFont();
		if(!mDlgFont)
			mDlgFont = newDialogFont();

		int fHeight, fWidth;
		GetFontMetrics(mDlgFont, fWidth, fHeight);
		mTextHeight = fHeight + 4;
		mTextWidth = fWidth;

		_wndFindLabel   = new Label(_wndBack, "Fi&nd what:", -1);
		_wndFindText    = new MultiLineText(_wndBack, "", IDC_FINDTEXT);
		_wndReplaceLabel = new Label(_wndBack, "Re&place with:", -1);
		_wndReplaceText = new MultiLineText(_wndBack, "", IDC_REPLACETEXT);
		_wndMatchCase   = new CheckBox(_wndBack, "Match &case", IDC_FINDMATCHCASE);
		_wndMatchBraces = new CheckBox(_wndBack, "Match &braces", IDC_FINDMATCHBRACES);
		_wndIncComment  = new CheckBox(_wndBack, "&Include preceding spaces and comments", IDC_FINDINCCOMMENT);
		_wndDirectionUp = new CheckBox(_wndBack, "Search &up", IDC_FINDDIRECTION);
		_wndReplaceCase = new CheckBox(_wndBack, "&Keep Case", IDC_REPLACECASE);
		_wndLookInLabel = new Label(_wndBack, "&Look in:", -1);
		_wndLookIn      = new ComboBox(_wndBack, [ "Current Document", "Current Selection"
			/*, "Current Project", "Current Solution"*/ ], false, IDC_FINDLOOKIN);
		_wndNext        = new Button(_wndBack, "&Find Next", IDC_FINDNEXT);
		_wndReplace     = new Button(_wndBack, "&Replace", IDC_REPLACE);
		_wndReplaceAll  = new Button(_wndBack, "Replace &All", IDC_REPLACEALL);
		_wndClose       = new Button(_wndBack, "Close", IDC_FINDCLOSE);
		
		_wndMatchCase  .AddWindowStyle(WS_TABSTOP);
		_wndMatchBraces.AddWindowStyle(WS_TABSTOP);
		_wndIncComment .AddWindowStyle(WS_TABSTOP);
		_wndDirectionUp.AddWindowStyle(WS_TABSTOP);
		
		_ReadStateFromRegistry();
		
		RECT r;
		_wndBack.GetClientRect(&r);
		_layoutViews(r.right - r.left, r.bottom - r.top);
		// _InitializeToolbar();
		return S_OK;
	}

	LRESULT _OnDestroy(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		if (_himlToolbar)
		{
			_wndToolbar.SendMessage(TB_SETIMAGELIST, 0, cast(LPARAM)null);
			ImageList_Destroy(_himlToolbar);
			_himlToolbar = null;
		}

		fHandled = TRUE;
		// return CComCompositeControl<CFlatSolutionExplorer>::OnDestroy(uiMsg, wParam, lParam, fHandled);
		return 0;
	}

	LRESULT _OnKeyDown(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		UINT vKey = LOWORD(wParam);
		switch(vKey)
		{
			case VK_ESCAPE:
				sWindowFrame.Hide();
				break;
			default:
				break;
		}
		return 0;
	}
	
	void _CheckSize()
	{
		RECT r, br;
		_wndParent.GetClientRect(&r);
		_wndBack.GetClientRect(&br);
		if(br.right - br.left != r.right - r.left - 2*kPaneMargin || 
		   br.bottom - br.top != r.bottom - r.top - 2*kPaneMargin)
			_wndBack.setRect(kPaneMargin, kPaneMargin, 
							 r.right - r.left - 2*kPaneMargin, r.bottom - r.top - 2*kPaneMargin);
	}

	// Adjust child control sizes
	void _layoutViews(int cw, int ch)
	{
		int top = kBackMargin; // kToolBarAtTop ? kToolBarHeight : 1;
		int bot = ch - kBackMargin;
		int lineh = mTextHeight;
		int combh = mTextHeight + 4;
		int lblspacing = 1;
		int spacing = 3;
		int btnw = mTextWidth * 10;
		int btnh = mTextHeight + 6;
		int x = kBackMargin;
		int w = cw - 2 * kBackMargin;
		_wndReplaceAll  .setRect(x + w - btnw,                  bot - btnh, btnw, btnh);
		_wndReplace     .setRect(x + w - btnw - spacing - btnw, bot - btnh, btnw, btnh);
		bot -= btnh + spacing;
		_wndClose       .setRect(x + w - btnw,                  bot - btnh, btnw, btnh);
		_wndNext        .setRect(x + w - btnw - spacing - btnw, bot - btnh, btnw, btnh);
		bot -= btnh + spacing + spacing;
		
		_wndLookIn      .setRect(x, bot - combh, w, combh); bot -= combh + lblspacing;
		_wndLookInLabel .setRect(x, bot - lineh, w, lineh); bot -= lineh + spacing;
version(none)
{
		_wndReplaceCase .setRect(x, bot - lineh, w, lineh); bot -= lineh + spacing;
}
else
{
		_wndReplaceCase.setVisible(false);
}
		int cbw = mTextWidth * 15;

		_wndDirectionUp .setRect(x + cbw, bot - lineh, w - cbw, lineh); // bot -= lineh + spacing;
		_wndMatchBraces .setRect(x,       bot - lineh,     cbw, lineh); bot -= lineh + spacing;
		_wndIncComment  .setRect(x + cbw, bot - lineh, w - cbw, lineh); // bot -= lineh + spacing;
		_wndMatchCase   .setRect(x,       bot - lineh,     cbw, lineh); bot -= lineh + spacing;

		_wndFindLabel   .setRect(x, top, w, lineh); top += lineh + lblspacing;
		int th = max(0, bot - top - spacing - lineh - spacing) / 2;
		_wndFindText    .setRect(x, top, w, th);    top += th + spacing;
		_wndReplaceLabel.setRect(x, top, w, lineh); top += lineh + lblspacing;
		_wndReplaceText .setRect(x, top, w, bot - top);
	}
	
	LRESULT _OnSize(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		int cx = LOWORD(lParam);
		int cy = HIWORD(lParam);

		_layoutViews(cx, cy);
		return 0;
	}

	LRESULT _OnSetFocus(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		// Skip the CComCompositeControl handling
		// CComControl<CFlatSolutionExplorer, CAxDialogImpl<CFlatSolutionExplorer>>::OnSetFocus(uiMsg, wParam, lParam, fHandled);

		if(_wndFindText)
		{
			_wndFindText.SetFocus();
			_wndFindText.SendMessage(EM_SETSEL, 0, cast(LPARAM)-1);
			fHandled = TRUE;
		}
		return 0;
	}

	void _OptionsToDialog()
	{
		_wndReplaceCase .setChecked(_options.keepCase);
		_wndIncComment  .setChecked(_options.includePretext);
		_wndMatchBraces .setChecked(_options.matchBrackets);
		_wndMatchCase   .setChecked(_options.matchCase);
	}
	
	void _DialogToOptions()
	{
		_options.keepCase       = _wndReplaceCase .isChecked();
		//_wndDirectionUp
		_options.includePretext = _wndIncComment  .isChecked();
		_options.matchBrackets  = _wndMatchBraces .isChecked();
		_options.matchCase      = _wndMatchCase   .isChecked();
	}
	
	RegKey _GetCurrentRegKey(bool write)
	{
		GlobalOptions opt = Package.GetGlobalOptions();
		opt.getRegistryRoot();
		wstring regPath = opt.regUserRoot ~ regPathToolsOptions;
		regPath ~= "\\TokenReplaceWindow"w;
		return new RegKey(opt.hUserKey, regPath, write);
	}
	
	bool _WriteStateToRegistry()
	{
		try
		{
			_DialogToOptions();
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set("keepCase"w, _options.keepCase);
			keyWinOpts.Set("matchCase"w, _options.matchCase);
			keyWinOpts.Set("includePretext"w, _options.includePretext);
			keyWinOpts.Set("matchBrackets"w, _options.matchBrackets);
			
			keyWinOpts.Set("directionUp"w, _wndDirectionUp.isChecked());
			keyWinOpts.Set("findText"w, _wndFindText.getWText());
			keyWinOpts.Set("replaceText"w, _wndReplaceText.getWText());
			keyWinOpts.Set("lookIn"w, _wndLookIn.getSelection());
		}
		catch(Exception e)
		{
			return false;
		}
		return true;
	}
	
	bool _ReadStateFromRegistry()
	{
		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(false);
			_options.keepCase       = keyWinOpts.GetDWORD("keepCase"w, _options.keepCase) != 0;
			_options.matchCase      = keyWinOpts.GetDWORD("matchCase"w, _options.matchCase) != 0;
			_options.includePretext = keyWinOpts.GetDWORD("includePretext"w, _options.includePretext) != 0;
			_options.matchBrackets  = keyWinOpts.GetDWORD("matchBrackets"w, _options.matchBrackets) != 0;
			
			_wndDirectionUp.setChecked(keyWinOpts.GetDWORD("directionUp"w, _wndDirectionUp.isChecked()) != 0);
			_wndFindText.setText(keyWinOpts.GetString("findText"w, _wndFindText.getWText()));
			_wndReplaceText.setText(keyWinOpts.GetString("replaceText"w, _wndReplaceText.getWText()));
			_wndLookIn.setSelection(keyWinOpts.GetDWORD("lookIn"w, _wndLookIn.getSelection()));
			_OptionsToDialog();
		}
		catch(Exception e)
		{
			return false;
		}
		return true;
	}
	
	// replaceMode -1: find last, 0: find first, 1:replace once if full match, 2+: replace all
	int _ReplaceNextInSpan(IVsTextLines buffer, IVsTextView view, int replaceMode,
						   int startLine, int startCol, int endLine, int endCol)
	{
		BSTR text;
		if(buffer.GetLineText(startLine, startCol, endLine, endCol, &text) != S_OK)
			return 0;
		wstring wtxt = wdetachBSTR(text);

		_options.findOnly = (replaceMode <= 0);
		_options.findMultiple = (replaceMode < 0);
		
		wstring search = _wndFindText.getWText();
		wstring replace = _wndReplaceText.getWText();
		ReplaceRange[] ranges;
		wstring ntxt = replaceTokenSequence(wtxt, startLine, startCol, search, replace, _options, &ranges);
		if(ranges.length == 0)
			return 0;
		
		if(replaceMode <= 0)
		{
			size_t idx = replaceMode < 0 ? ranges.length - 1 : 0;
			if(view)
				view.SetSelection(ranges[idx].startlineno, ranges[idx].startcolumn,
								  ranges[idx].endlineno,   ranges[idx].endcolumn);
			else
				NavigateTo(buffer, ranges[idx].startlineno, ranges[idx].startcolumn,
				                   ranges[idx].endlineno,   ranges[idx].endcolumn);
		}
		else
		{
			if(replaceMode == 1)
			{
				if(ranges.length > 1)
					return 0;
				if(ranges[0].startlineno != startLine || ranges[0].startcolumn != startCol ||
				   ranges[0].endlineno != endLine || ranges[0].endcolumn != endCol)
					return 0;
			}
			IVsCompoundAction compAct = qi_cast!IVsCompoundAction(view);
			if(compAct)
				compAct.OpenCompoundAction("Replace tokens"w.ptr);
			scope(exit) if(compAct)
			{
				compAct.CloseCompoundAction();
				compAct.Release();
			}
			
			int lastReplaceLine, lastReplaceColumn;
			int diffLines, diffColumns;
			for(int i = 0; i < ranges.length; i++)
			{
				int startlineno = ranges[i].startlineno + diffLines;
				int startcolumn = ranges[i].startcolumn;
				int endlineno   = ranges[i].endlineno + diffLines;
				int endcolumn   = ranges[i].endcolumn;

				if(startlineno == lastReplaceLine)
					startcolumn += diffColumns;
				if(endlineno == lastReplaceLine)
					endcolumn += diffColumns;

				TextSpan changedSpan;
				if(buffer.ReplaceLines(startlineno, startcolumn, endlineno, endcolumn, 
									   ranges[i].replacementText.ptr, ranges[i].replacementText.ilength,
									   &changedSpan) != S_OK)
					return i;
				
				diffLines += (changedSpan.iEndLine - changedSpan.iStartLine) - (endlineno - startlineno);
				diffColumns = changedSpan.iEndIndex - endcolumn;
			}
		}
		return ranges.ilength;
	}
	
	LRESULT _OnFindNext()
	{
		bool up = _wndDirectionUp.isChecked();
		return _DoFindNext(up);
	}
	
	LRESULT _DoFindNext(bool up)
	{
		IVsTextView view;
		scope(exit) release(view);
		if(IVsTextLines buffer = GetCurrentTextBuffer(&view))
		{
			_DialogToOptions();
			scope(exit) release(buffer);

			int startLine, startCol;
			int endLine, endCol;
			if(view)
				if(!up || view.GetSelection(&startLine, &startCol, &endLine, &endCol) != S_OK)
					view.GetCaretPos (&startLine, &startCol); // caret usually at end of selection
			buffer.GetLastLineIndex(&endLine, &endCol);
			try
			{
				int found;
				if(up)
				{
					if(startLine > 0 || startCol > 0)
						found = _ReplaceNextInSpan(buffer, view, -1, 0, 0, startLine, startCol);
					if(found == 0)
						found = _ReplaceNextInSpan(buffer, view, -1, 0, 0, endLine, endCol);
				}
				else
				{
					found = _ReplaceNextInSpan(buffer, view, 0, startLine, startCol, endLine, endCol);
					if(found == 0)
						if(startLine > 0 || startCol > 0)
							found = _ReplaceNextInSpan(buffer, view, 0, 0, 0, endLine, endCol);
				}
				if(found == 0)
				{
					string s = createPasteString(to!string(_wndFindText.getWText()));
					showStatusBarText("Token sequence not found: " ~ s);
				}
			}
			catch(Exception e)
			{
				showStatusBarText("Token replace: " ~ e.msg);
			}
		}
		return 0;
	}
	
	LRESULT _OnReplace()
	{
		IVsTextView view;
		scope(exit) release(view);
		if(IVsTextLines buffer = GetCurrentTextBuffer(&view))
		{
			_DialogToOptions();
			scope(exit) release(buffer);

			try
			{
				int startLine, startCol;
				int endLine, endCol;
				if(view && view.GetSelection(&startLine, &startCol, &endLine, &endCol) == S_OK)
					_ReplaceNextInSpan(buffer, view, 1, startLine, startCol, endLine, endCol);
				_OnFindNext();
			}
			catch(Exception e)
			{
				showStatusBarText("Token replace: " ~ e.msg);
			}
		}
		return 0;
	}

	LRESULT _OnReplaceAll()
	{
		IVsTextView view;
		scope(exit) release(view);
		if(IVsTextLines buffer = GetCurrentTextBuffer(&view))
		{
			_DialogToOptions();
			scope(exit) release(buffer);

			bool selOnly = (_wndLookIn.getSelection() == 1);
			int startLine, startCol;
			int endLine, endCol;
			if(!selOnly || !view || view.GetSelection(&startLine, &startCol, &endLine, &endCol) != S_OK)
				buffer.GetLastLineIndex(&endLine, &endCol);
			try
			{
				int found = _ReplaceNextInSpan(buffer, view, 2, startLine, startCol, endLine, endCol);
				if(found == 0)
				{
					string s = createPasteString(to!string(_wndFindText.getWText()));
					showStatusBarText("Token sequence not found: " ~ s);
				}
				else if(found == 1)
					showStatusBarText("1 token sequence replaced."w);
				else
					showStatusBarText(text(found, " token sequences replaced."));
			}
			catch(Exception e)
			{
				showStatusBarText("Token replace: " ~ e.msg);
			}
		}
		return 0;
	}
}
