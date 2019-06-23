// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.cppwizard;

import visuald.windows;
import visuald.winctrl;
import visuald.comutil;
import visuald.register;
import visuald.pkgutil;
import visuald.hierutil;
import visuald.logutil;
import visuald.fileutil;
import visuald.stringutil;
import visuald.wmmsg;
import visuald.dpackage;
import visuald.dimagelist;

import c2d.tokutil;
import c2d.cpp2d;

import sdk.win32.commctrl;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import dte80a = sdk.vsi.dte80a;
import dte80 = sdk.vsi.dte80;

import stdext.file;
import stdext.string;

import std.algorithm;
import std.conv;
import std.string;
import core.thread;

private IVsWindowFrame sWindowFrame;
private	CppWizardPane sWizardPane;

const int  kPaneMargin = 0;
const int  kBackMargin = 4;

class Cpp2D : Cpp2DConverter
{
	override void writemsg(string s)
	{
		writeToBuildOutputPane(s ~ "\n");
	}
}

bool createCppWizardWindow()
{
	if(!sWindowFrame)
	{
		auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
		if(!pIVsUIShell)
			return false;

		sWizardPane = newCom!CppWizardPane();
		const(wchar)* caption = "Visual D C++ Conversion Wizard"w.ptr;
		HRESULT hr;
		hr = pIVsUIShell.CreateToolWindow(CTW_fInitNew, 0, sWizardPane, 
										  &GUID_NULL, &g_CppWizardWinCLSID, &GUID_NULL, 
										  null, caption, null, &sWindowFrame);
		if(!SUCCEEDED(hr))
		{
			sWizardPane = null;
			return false;
		}
	}
	return true;
}

bool showCppWizardWindow()
{
	if(!createCppWizardWindow())
		return false;

	if(FAILED(sWindowFrame.Show()))
		return false;
	BOOL fHandled;
	sWizardPane._OnSetFocus(0, 0, 0, fHandled);
	return fHandled != 0;
}

bool closeCppWizardWindow()
{
	sWindowFrame = release(sWindowFrame);
	sWizardPane = null;
	return true;
}

bool convertSelection(IVsTextView view)
{
	IVsTextLines buffer;
	if(FAILED(view.GetBuffer(&buffer)) || !buffer)
		return false;
	scope(exit) release(buffer);

	if(!createCppWizardWindow())
		return false;
	return sWizardPane.runTextConversion(view, buffer, true);
}

class CppWizardWindowBack : Dialog
{
	this(Window parent, CppWizardPane pane)
	{
		mPane = pane;
		super(parent);
	}

	override int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam) 
	{
		BOOL fHandled;
		LRESULT rc = mPane._WindowProc(hWnd, uMsg, wParam, lParam, fHandled);
		if(fHandled)
			return rc;

		return super.WindowProc(hWnd, uMsg, wParam, lParam);
	}

	CppWizardPane mPane;
}

class CppWizardPane : DisposingComObject, IVsWindowPane
{
	IServiceProvider mSite;

	this()
	{
		_ReadStateFromRegistry();
	}

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

	HRESULT SetSite(/+[in]+/ IServiceProvider psp)
	{
		mixin(LogCallMix2);
		mSite = release(mSite);
		mSite = addref(psp);
		return S_OK;
	}

	HRESULT CreatePaneWindow(in HWND hwndParent, in int x, in int y, in int cx, in int cy,
	                         /+[out]+/ HWND *hwnd)
	{
		mixin(LogCallMix2);

		_wndParent = new Window(hwndParent);
		_wndBack = new CppWizardWindowBack(_wndParent, this);

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

			_wndFilesLabel = null;
			_wndFilesText = null;
			_wndCodeHdrLabel = null;
			_wndCodeHdrText = null;
			_wndReplaceLabel = null;
			_wndReplacePreText = null;
			_wndReplacePostText = null;
			_wndInputTypeLabel = null;
			_wndInputType = null;

			_wndKeywordPrefixLabel = null;
			_wndKeywordPrefixText = null;
			_wndPackagePrefixLabel = null;
			_wndPackagePrefixText = null;
			_wndOutputDirLabel = null;
			_wndOutputDirText = null;
			_wndInputDirLabel = null;
			_wndInputDirText = null;

			_wndVersionsLabel = null;
			_wndVersionsText = null;
			_wndExpansionsLabel = null;
			_wndExpansionsText = null;
			_wndValueTypesLabel = null;
			_wndValueTypesText = null;
			_wndClassTypesLabel = null;
			_wndClassTypesText = null;

			_wndWriteIntermediate = null;

			_wndLoad = null;
			_wndSave = null;
			_wndConvert = null;

			mDlgFont = deleteDialogFont(mDlgFont);

			if(_himlToolbar)
				ImageList_Destroy(_himlToolbar);
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
		HRESULT hrRet = _HandleMessage(msg.hwnd, msg.message, msg.wParam, msg.lParam, fHandled);

		if(fHandled)
			return hrRet;
		return E_NOTIMPL;
	}

	///////////////////////////////////////////////////////////////////

	// the following has been ported from the FlatSolutionExplorer project
private:
	C2DIni        _options;

	Window _wndParent;
	CppWizardWindowBack _wndBack;
	ToolBar       _wndToolbar;
	HIMAGELIST    _himlToolbar;
	HFONT mDlgFont;
	int mTextHeight;
	int mTextWidth;

	Label         _wndInputTypeLabel;
	ComboBox      _wndInputType;

	Label         _wndKeywordPrefixLabel;
	Text          _wndKeywordPrefixText;
	Label         _wndPackagePrefixLabel;
	Text          _wndPackagePrefixText;

	Label         _wndOutputDirLabel;
	Text          _wndOutputDirText;
	Label         _wndInputDirLabel;
	Text          _wndInputDirText;

	Label         _wndFilesLabel;
	MultiLineText _wndFilesText;
	Label         _wndCodeHdrLabel;
	MultiLineText _wndCodeHdrText;
	Label         _wndReplaceLabel;
	MultiLineText _wndReplacePreText;
	MultiLineText _wndReplacePostText;
	Label         _wndVersionsLabel;
	MultiLineText _wndVersionsText;
	Label         _wndExpansionsLabel;
	MultiLineText _wndExpansionsText;
	Label         _wndValueTypesLabel;
	MultiLineText _wndValueTypesText;
	Label         _wndClassTypesLabel;
	MultiLineText _wndClassTypesText;

	CheckBox      _wndWriteIntermediate;

	Button        _wndLoad;
	Button        _wndSave;
	Button        _wndConvert;

	static HINSTANCE getInstance() { return Widget.getInstance(); }

	int _WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
	{
		if(uMsg != WM_NOTIFY)
			logMessage("_WindowProc", hWnd, uMsg, wParam, lParam);

		return _HandleMessage(hWnd, uMsg, wParam, lParam, fHandled);
	}

	int _HandleMessage(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
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

				if(id == IDC_WIZ_INPUTTPYE && code == CBN_SELCHANGE)
					_UpdateEnableState();

				if(code == BN_CLICKED)
				{
					switch(id)
					{
						case IDC_WIZ_LOAD:
							string file = getOpenFileDialog(hWnd, "Load Conversion Config", "", "Conversion Files|*.c2d|");
							if(file.length)
							{
								tryWithExceptionToBuildOutputPane( (){
									_options.readFromFile(file);
								}, file);
								_OptionsToDialog();
							}
							return 0;
						case IDC_WIZ_SAVE:
							string file = getSaveFileDialog(hWnd, "Save Conversion Config", "", "Conversion Files|*.c2d|");
							if(file.length)
							{
								_DialogToOptions();
								tryWithExceptionToBuildOutputPane( (){
									_options.writeToFile(file);
								}, file);
							}
							return 0;
						case IDC_WIZ_CONVERT:
							runConversion();
							//sWindowFrame.Hide();
							return 0;

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
		if(_wndInputTypeLabel)
			return S_OK;
		updateEnvironmentFont();
		if(!mDlgFont)
			mDlgFont = newDialogFont();
		int fHeight, fWidth;
		GetFontMetrics(mDlgFont, fWidth, fHeight);
		mTextHeight = fHeight + 4;
		mTextWidth = fWidth;

		_wndInputTypeLabel = new Label(_wndBack, "&Convert:", -1);
		_wndInputType      = new ComboBox(_wndBack, [ "Input files", "Current Document", 
		                                              "Current Selection" ], false, IDC_WIZ_INPUTTPYE);

		_wndFilesLabel   = new Label(_wndBack, "Fi&les and directories:", -1);
		_wndFilesText    = new MultiLineText(_wndBack, "", IDC_WIZ_INPUTFILES);

		_wndCodeHdrLabel = new Label(_wndBack, "Source Code Header:", -1);
		_wndCodeHdrText  = new MultiLineText(_wndBack, "", IDC_WIZ_CODEHDR);

		_wndKeywordPrefixLabel = new Label(_wndBack, "Keyword Prefix:", -1);
		_wndKeywordPrefixText  = new Text(_wndBack, "", IDC_WIZ_KEYWORDPREFIX);

		_wndPackagePrefixLabel = new Label(_wndBack, "Package Prefix:", -1);
		_wndPackagePrefixText  = new Text(_wndBack, "", IDC_WIZ_PACKAGEPREFIX);

		_wndOutputDirLabel = new Label(_wndBack, "Output Dir:", -1);
		_wndOutputDirText  = new Text(_wndBack, "", IDC_WIZ_OUTPUTDIR);

		_wndInputDirLabel  = new Label(_wndBack, "Input Dir:", -1);
		_wndInputDirText   = new Text(_wndBack, "", IDC_WIZ_INPUTDIR);

		_wndReplaceLabel    = new Label(_wndBack, "Pre and Post Token Re&placements (pattern => replacement):", -1);
		_wndReplacePreText  = new MultiLineText(_wndBack, "", IDC_WIZ_REPLACEPRE);
		_wndReplacePostText = new MultiLineText(_wndBack, "", IDC_WIZ_REPLACEPOST);

		_wndWriteIntermediate = new CheckBox(_wndBack, "Write intermediate files", IDC_WIZ_WRITEINTERMED);

		_wndVersionsLabel = new Label(_wndBack, "Version Conditionals:", -1);
		_wndVersionsText  = new MultiLineText(_wndBack, "", IDC_WIZ_VERSIONS);

		_wndExpansionsLabel = new Label(_wndBack, "Preprocessor expansions:", -1);
		_wndExpansionsText  = new MultiLineText(_wndBack, "", IDC_WIZ_EXPANSIONS);

		_wndValueTypesLabel = new Label(_wndBack, "Value types:", -1);
		_wndValueTypesText  = new MultiLineText(_wndBack, "", IDC_WIZ_VALUETYPES);
		_wndClassTypesLabel = new Label(_wndBack, "Reference types:", -1);
		_wndClassTypesText  = new MultiLineText(_wndBack, "", IDC_WIZ_CLASSTYPES);

		_wndLoad        = new Button(_wndBack, "&Load", IDC_WIZ_LOAD);
		_wndSave        = new Button(_wndBack, "&Save", IDC_WIZ_SAVE);
		_wndConvert     = new Button(_wndBack, "&Convert", IDC_WIZ_CONVERT);

		_OptionsToDialog();

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

		// ##InputType######## ##KWPrefex###
		// ##OutputDir######## X Add2Startup
		// ##InputDir#######################
		// +-Files-------------------------\
		// \-------------------------------+
		// +-Replace Pre--\+-Replace Post--\
		// \--------------+\---------------+
		// +-Versions-----\+-Expansions----\
		// \----------.---+\---------------+
		// +-ValueTypes---\+-RefTypes------\
		// \----------.---+\---------------+
		//                   Load Save Conv

		int lblwidth = mTextWidth * 10;
		int kwpwidth = mTextWidth * 22;
		_wndInputTypeLabel.setRect(x, top + 2, lblwidth, lineh);
		_wndInputType.setRect(x + lblwidth, top, w - lblwidth, combh);
		top += combh + 2 + spacing;

		_wndInputDirLabel.setRect(x,           top, lblwidth, lineh);
		_wndInputDirText.setRect(x + lblwidth, top, w - lblwidth, lineh);
		top += lineh + spacing;

		_wndConvert.setRect(x + w - btnw - 0 * (spacing + btnw), bot - btnh, btnw, btnh);
		_wndSave   .setRect(x + w - btnw - 1 * (spacing + btnw), bot - btnh, btnw, btnh);
		_wndLoad   .setRect(x + w - btnw - 2 * (spacing + btnw), bot - btnh, btnw, btnh);
		bot -= btnh + spacing + spacing;

		int plblwidth = mTextWidth * 13;
		int tw = max(0, w - spacing) / 2;
		_wndKeywordPrefixLabel.setRect(x, bot - lineh, plblwidth, lineh);
		_wndKeywordPrefixText.setRect(x + plblwidth, bot - lineh, tw - plblwidth - spacing, lineh);
		_wndPackagePrefixLabel.setRect(x + tw, bot - lineh, plblwidth, lineh);
		_wndPackagePrefixText.setRect(x + tw + plblwidth, bot - lineh, tw - plblwidth - spacing, lineh);
		bot -= lineh + spacing;

//		_wndLookIn      .setRect(x, bot - combh, w, combh); bot -= combh + lblspacing;
//		_wndLookInLabel .setRect(x, bot - lineh, w, lineh); bot -= lineh + spacing;

		int th = max(0, bot - top - (4 * spacing + lineh)) / 4;
		int txth = max(0, th - lineh + lblspacing - spacing);

		_wndCodeHdrLabel.setRect(x + tw, top, w - tw, lineh);
		_wndFilesLabel.setRect(x, top, w - spacing, lineh); top += lineh + lblspacing;
		_wndCodeHdrText.setRect(x + tw, top, w - tw, txth);
		_wndFilesText.setRect(x, top, tw - spacing, txth);   top += txth + spacing;

		_wndOutputDirLabel.setRect(x,           top, lblwidth, lineh);
		_wndOutputDirText.setRect(x + lblwidth, top, w - kwpwidth - lblwidth - 10, lineh);
		_wndWriteIntermediate.setRect(w - kwpwidth, top, kwpwidth, lineh);
		top += lineh + spacing + spacing;

		_wndVersionsLabel.setRect(x + w - tw, top, tw, lineh);
		_wndExpansionsLabel.setRect(x, top, tw, lineh);
		top += lineh + lblspacing;
		_wndVersionsText.setRect(x + w - tw, top, tw, txth);
		_wndExpansionsText.setRect(x, top, tw, txth);
		top += txth + spacing;

		_wndReplaceLabel.setRect(x, top, w, lineh); top += lineh + lblspacing;
		_wndReplacePreText.setRect(x, top, tw, txth);
		_wndReplacePostText.setRect(x + w - tw, top, tw, txth);  top += txth + spacing;

		_wndValueTypesLabel.setRect(x, top, tw, lineh);
		_wndClassTypesLabel.setRect(x + w - tw, top, tw, lineh);
		top += lineh + lblspacing;
		_wndValueTypesText.setRect(x, top, tw, bot - top);
		_wndClassTypesText.setRect(x + w - tw, top, tw, bot - top);
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

		if(_wndFilesText)
		{
			//_wndFilesText.SetFocus();
			//_wndFilesText.SendMessage(EM_SETSEL, 0, cast(LPARAM)-1);
			fHandled = TRUE;
		}
		return 0;
	}

	void _UpdateEnableState()
	{
		int sel = _wndInputType.getSelection();
		bool files = (sel == 0);
		_wndWriteIntermediate.setEnabled(files);
		_wndOutputDirText.setEnabled(files);
		_wndInputDirText.setEnabled(files);
		_wndFilesText.setEnabled(files);
		_wndCodeHdrText.setEnabled(files);
	}

	void _OptionsToDialog()
	{
		_wndWriteIntermediate.setChecked(_options.writeIntermediate);
		_wndInputType.setSelection(_options.inputType);

		_wndFilesText.setText(_options.inputFiles);
		_wndCodeHdrText.setText(_options.codePrefix);
		_wndReplacePreText.setText(_options.replaceTokenPre);
		_wndReplacePostText.setText(_options.replaceTokenPost);
		_wndKeywordPrefixText.setText(_options.keywordPrefix);
		_wndPackagePrefixText.setText(_options.packagePrefix);
		_wndVersionsText.setText(_options.versionDefines);
		_wndExpansionsText.setText(_options.expandConditionals);
		_wndValueTypesText.setText(_options.userValueTypes);
		_wndClassTypesText.setText(_options.userClassTypes);
		_wndOutputDirText.setText(_options.outputDir);
		_wndInputDirText.setText(_options.inputDir);

		_UpdateEnableState();
	}

	void _DialogToOptions()
	{
		_options.inputType = _wndInputType.getSelection();
		_options.writeIntermediate = _wndWriteIntermediate.isChecked();

		_options.inputFiles = _wndFilesText.getText();
		_options.codePrefix = _wndCodeHdrText.getText();
		_options.replaceTokenPre = _wndReplacePreText.getText();
		_options.replaceTokenPost = _wndReplacePostText.getText();
		_options.keywordPrefix = _wndKeywordPrefixText.getText();
		_options.packagePrefix = _wndPackagePrefixText.getText();
		_options.versionDefines = _wndVersionsText.getText();
		_options.expandConditionals = _wndExpansionsText.getText();
		_options.userValueTypes = _wndValueTypesText.getText();
		_options.userClassTypes = _wndClassTypesText.getText();
		_options.outputDir = _wndOutputDirText.getText();
		_options.inputDir = _wndInputDirText.getText();
	}

	RegKey _GetCurrentRegKey(bool write)
	{
		GlobalOptions opt = Package.GetGlobalOptions();
		opt.getRegistryRoot();
		wstring regPath = opt.regUserRoot ~ regPathToolsOptions;
		regPath ~= "\\WizardWindow"w;
		return new RegKey(opt.hUserKey, regPath, write);
	}

	bool _WriteStateToRegistry()
	{
		try
		{
			_DialogToOptions();

			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			string s = _options.writeToText();
			keyWinOpts.Set("Options"w, to!wstring(s));
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
			wstring s = keyWinOpts.GetString("Options"w, ""w);
			_options = _options.init;
			_options.readFromText(to!string(s));
		}
		catch(Exception e)
		{
			return false;
		}
		return true;
	}

	string mLastCText;
	string mLastDText;

	bool runTextConversion()
	{
		IVsTextView view;
		scope(exit) release(view);
		IVsTextLines buffer = GetCurrentTextBuffer(&view);
		if(!buffer)
			return false;
		scope(exit) release(buffer);
		if(!view)
			return false;
		return runTextConversion(view, buffer, _options.inputType != 1);
	}

	bool runTextConversion(IVsTextView view, IVsTextLines buffer, bool selection)
	{
		int startLine, startCol;
		int endLine, endCol;
		HRESULT hr;
		if(selection)
			hr = GetSelectionForward(view, &startLine, &startCol, &endLine, &endCol);
		else
			hr = buffer.GetLastLineIndex(&endLine, &endCol);
		if(hr != S_OK)
			return false;

		BSTR text;
		if(buffer.GetLineText(startLine, startCol, endLine, endCol, &text) != S_OK)
			return false;
		string txt = detachBSTR(text);
		if(txt == mLastDText)
			txt = mLastCText;

		auto c2d = new Cpp2D;
		_options.toC2DOptions(/*c2d.cpp2d.*/options);
		string ntxt = c2d.main(txt);

		if(ntxt !is null && txt != ntxt)
		{
			mLastCText = txt;
			mLastDText = ntxt;

			wstring wntxt = to!wstring(ntxt);
			TextSpan changedSpan;
			if(buffer.ReplaceLines(startLine, startCol, endLine, endCol, 
								   wntxt.ptr, wntxt.length, &changedSpan) != S_OK)
				return false;
		}
		return true;
	}

	bool runFileConversion()
	{
		void run()
		{
			_options.toC2DOptions(/*c2d.cpp2d.*/options);

			string[] filespecs = tokenizeArgs(_options.inputFiles);
			string[] files = expandFileList(filespecs, _options.inputDir);

			try
			{
				auto c2d = new Cpp2D;
				c2d.main(files);
			}
			catch(Throwable e)
			{
				string msg = e.toString();
				writeToBuildOutputPane(msg);
			}
		}

		clearOutputPane();
		auto thrd = new Thread(&run);
		thrd.start();
		return true;
	}

	bool runConversion()
	{
		try
		{
			_DialogToOptions();

			if(_options.inputType == 0)
				return runFileConversion();
			return runTextConversion();
		}
		catch(Throwable e)
		{
			string msg = e.toString();
			writeToBuildOutputPane(msg);
			logCall("EXCEPTION: " ~ msg);
			return false;
		}
	}
}
