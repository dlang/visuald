// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.winctrl;

import visuald.windows;
import visuald.logutil;

import std.conv;
import std.utf;
import std.string;
import std.ascii;
import std.array;
import std.exception;
import std.algorithm;
import sdk.port.base;
import sdk.win32.prsht;
import sdk.win32.commctrl;

private Widget[Widget] createdWindows; // collection of all windows with HWND to avoid garbage collection
alias AssociativeArray!(Widget, Widget) _wa1; // fully instantiate type info

private HINSTANCE hInst;
private HFONT winFont;

LOGFONTW dialogLogFont = { lfHeight : -9, lfCharSet : 1, lfFaceName : "Segoe UI" };

HFONT getDialogFont()
{
	if(winFont)
		return winFont;
	return newDialogFont();
}

int GetDesktopDPI()
{
	HWND hwnd = GetDesktopWindow();
	HDC hDDC = GetDC(hwnd);
	int dpi = GetDeviceCaps(hDDC, LOGPIXELSY);
	ReleaseDC(hwnd, hDDC);
	return dpi;
}

HFONT newDialogFont()
{
	// GetStockObject(DEFAULT_GUI_FONT);

	//int nHeight = -MulDiv(dialogFontSize, GetDesktopDPI(), 72);

	//winFont = CreateFontA(int cHeight, int cWidth, int cEscapement, int cOrientation, int cWeight, DWORD bItalic,
	//                      DWORD bUnderline, DWORD bStrikeOut, DWORD iCharSet, DWORD iOutPrecision, DWORD iClipPrecision,
	//                      DWORD iQuality, DWORD iPitchAndFamily, LPCSTR pszFaceName);

	winFont = CreateFontIndirectW(&dialogLogFont);
	assert(winFont);
	return winFont;
}

HFONT deleteDialogFont(HFONT font)
{
	if(font is null)
		return null;
	if(winFont is font)
		winFont = null;

	DeleteObject(font);
	return null;
}

class Widget
{
	HWND hwnd;
	bool attached;

	Widget parent;
	Widget[] children;

	this()
	{
	}
	this(Widget p)
	{
		if(p)
			p.addChild(this);
	}

	bool createWidget(Widget parent, string classname, string text, uint style, uint exstyle, int id)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		hwnd = CreateWindowExW(exstyle, toUTF16z(classname), toUTF16z(text), style,
					CW_USEDEFAULT, CW_USEDEFAULT, 10, 10,
					parenthwnd, cast(HMENU)id, hInst, null);
		assert(hwnd !is null, "Failed to create " ~ classname ~ " window");
		if(!hwnd)
			return false;

		SetWindowLongA(hwnd, GWL_USERDATA, cast(int)cast(void*)this);
		return true;
	}

	void Dispose()
	{
		while(children.length)
		{
			Widget child = children[0];
			child.Dispose();
			delChild(child);
		}

		if(hwnd)
		{
			if(!attached)
			{
				BOOL ok = DestroyWindow(hwnd);
				assert(ok);
			}
			hwnd = null;
		}
	}

	void addChild(Widget child)
	{
		children ~= child;
		child.parent = this;
	}

	void delChild(Widget child)
	{
		assert(child.parent is this);
		for(int i = 0; i < children.length; i++)
			if(children[i] is child)
			{
				children = children[0 .. i] ~ children[i+1 .. $];
				child.parent = null;
				break;
			}
	}

	// coordinates relative to parent (child window) or screen (top level window)
	bool getRect(ref int left, ref int top, ref int w, ref int h)
	{
		RECT r;
		if(!.GetWindowRect(hwnd, &r))
			return false;
		if(HWND ph = GetParent(hwnd))
		{
			RECT pr;
			if(!.GetWindowRect(ph, &pr))
				return false;
			r.left -= pr.left;
			r.right -= pr.left;
			r.top -= pr.top;
			r.bottom -= pr.top;
		}
		left = r.left;
		top = r.top;
		w = r.right - r.left;
		h = r.bottom - r.top;
		return true;
	}

	// coordinates relative to parent (child window) or screen (top level window)
	void setRect(int left, int top, int w, int h)
	{
		BOOL ok = MoveWindow(hwnd, left, top, w, h, true);
		assert(ok, "Failed to move window in setRect");
	}

	void setVisible(bool visible)
	{
		ShowWindow(hwnd, visible ? SW_SHOW : SW_HIDE); // ignore bool result
	}

	void setEnabled(bool enable)
	{
		EnableWindow(hwnd, enable);
	}

	void SetFocus()
	{
		.SetFocus(hwnd);
	}

	void SetRedraw(bool enable)
	{
		SendMessage(WM_SETREDRAW, enable);
	}

	int SendMessage(int msg, WPARAM wp = 0, LPARAM lp = 0)
	{
		return .SendMessage(hwnd, msg, wp, lp);
	}

	void InvalidateRect(RECT* r, bool erase)
	{
		.InvalidateRect(hwnd, r, erase);
	}

	string GetWindowText()
	{
		WCHAR[256] txt;
		int len = GetWindowTextW(hwnd, txt.ptr, txt.length);
		if(len < txt.length)
			return toUTF8(txt[0..len]);

		scope buffer = new wchar[len+1];
		len = GetWindowTextW(hwnd, buffer.ptr, len+1);
		return toUTF8(buffer[0..len]);
	}
	bool SetWindowText(string txt)
	{
		return SetWindowTextW(hwnd, toUTF16z(txt)) != 0;
	}

	bool GetWindowRect(RECT* r)
	{
		return .GetWindowRect(hwnd, r) != 0;
	}

	bool GetClientRect(RECT* r)
	{
		return .GetClientRect(hwnd, r) != 0;
	}

	bool ScreenToClient(POINT *lpPoint)
	{
		return .ScreenToClient(hwnd, lpPoint) != 0;
	}

	bool ScreenToClient(RECT *rect)
	{
		POINT pnt = { rect.left, rect.top };
		if (.ScreenToClient(hwnd, &pnt) == 0)
			return false;
		rect.right += pnt.x - rect.left;
		rect.bottom += pnt.y - rect.top;
		rect.left = pnt.x;
		rect.top = pnt.y;
		return true;
	}

	bool SetWindowPos(HWND hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags)
	{
		return .SetWindowPos(hwnd, hWndInsertAfter, X, Y, cx, cy, uFlags) != 0;
	}

	bool SetWindowPos(HWND hWndInsertAfter, RECT* r, uint uFlags)
	{
		return .SetWindowPos(hwnd, hWndInsertAfter, r.left, r.top, r.right - r.left, r.bottom - r.top, uFlags) != 0;
	}

	bool SetWindowStyle(int style)
	{
		return SetWindowLongA(hwnd, GWL_STYLE, style) != 0;
	}

	bool AddWindowStyle(int flag, int clear = 0)
	{
		DWORD style = GetWindowLongA(hwnd, GWL_STYLE);
		return SetWindowLongA(hwnd, GWL_STYLE, (style & ~clear) | flag) != 0;
	}

	bool DelWindowStyle(int flag)
	{
		DWORD style = GetWindowLongA(hwnd, GWL_STYLE);
		return SetWindowLongA(hwnd, GWL_STYLE, style & ~flag) != 0;
	}

	bool SetWindowExStyle(int style)
	{
		return SetWindowLongA(hwnd, GWL_EXSTYLE, style) != 0;
	}

	bool AddWindowExStyle(int flag, int clear = 0)
	{
		DWORD style = GetWindowLongA(hwnd, GWL_EXSTYLE);
		return SetWindowLongA(hwnd, GWL_EXSTYLE, (style & ~clear) | flag) != 0;
	}

	bool DelWindowExStyle(int flag)
	{
		DWORD style = GetWindowLongA(hwnd, GWL_EXSTYLE);
		return SetWindowLongA(hwnd, GWL_EXSTYLE, style & ~flag) != 0;
	}

	static Widget fromHWND(HWND hwnd)
	{
		return cast(Widget)cast(void*)GetWindowLongA(hwnd, GWL_USERDATA);
	}

	static HINSTANCE getInstance() { return hInst; }

}

class Window : Widget
{
	static bool hasRegistered = false;
	static HBRUSH bgbrush;

	static void registerClass()
	{
		if(hasRegistered)
			return;
		hasRegistered = true;

		DWORD color = GetSysColor(COLOR_BTNFACE);
		bgbrush = CreateSolidBrush(color);

		WNDCLASSA wc;
		wc.lpszClassName = "VisualDWindow";
		wc.style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW;
		wc.lpfnWndProc = &WinWindowProc;
		wc.hInstance = hInst;
		wc.hIcon = null; //DefaultWindowIcon.peer;
		//wc.hIconSm = DefaultWindowSmallIcon.peer;
		wc.hCursor = LoadCursorW(cast(HINSTANCE) null, IDC_ARROW);
		wc.hbrBackground = bgbrush;
		wc.lpszMenuName = null;
		wc.cbClsExtra = 0;
		wc.cbWndExtra = 0;
		ATOM atom = RegisterClassA(&wc);
		assert(atom);
	}
	static void unregisterClass()
	{
		if(!hasRegistered)
			return;
		hasRegistered = false;

		UnregisterClassA("VisualDWindow", hInst);
		if(bgbrush)
			DeleteObject(bgbrush);
		bgbrush = null;
	}

	this(in HWND h)
	{
		hwnd = cast(HWND) h; // we need to remove "const" from "in"
		attached = true;
		createdWindows[this] = this; // prevent garbage collection
	}
	this(Widget parent, string title = "", int id = 0)
	{
		registerClass();
		uint style = WS_VISIBLE;
		if(parent)
			style |= WS_CHILD;
		createWidget(parent, "VisualDWindow", title, style, 0, id);
		createdWindows[this] = this; // prevent garbage collection
		super(parent);
	}
	this(Widget parent, uint style, string title = "", int id = 0)
	{
		registerClass();
		createWidget(parent, "VisualDWindow", title, style, 0, id);
		createdWindows[this] = this; // prevent garbage collection
		super(parent);
	}

	override void Dispose()
	{
		if(backgroundBrush)
			DeleteObject(backgroundBrush);
		super.Dispose();
		createdWindows.remove(this);
	}

	void setBackground(DWORD col)
	{
		//if(backgroundBrush)
		//	DeleteObject(backgroundBrush);
		//backgroundBrush = CreateSolidBrush(col);
	}

	extern(Windows) static int WinWindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		if (Window win = cast(Window) fromHWND(hWnd))
			return win.WindowProc(hWnd,uMsg,wParam,lParam);
		return DefWindowProcA(hWnd, uMsg, wParam, lParam);
	}

	int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		switch (uMsg) {
		case WM_COMMAND:
			Widget c = fromHWND(cast(HWND)lParam);
			doCommand(c, LOWORD(wParam));
			break;

		case WM_CTLCOLORBTN:
		case WM_CTLCOLORSTATIC:
			HDC dc = cast(HDC)wParam;
			//SetTextColor(dc, 0xFF0000);
			SetBkColor(dc, GetSysColor(COLOR_BTNFACE));
			return cast(int)bgbrush;

		case WM_CLOSE:
			// send close message to top level window
			// otherwise, only our embedded window is closed when pressing esc with the focus in the multi-line-edit
			if(HWND hnd = GetAncestor(hWnd, GA_ROOT))
				if(hnd != hwnd && hnd != hWnd)
					return SendMessageA(hnd, uMsg, wParam, lParam);
			break;

		case WM_DESTROY:
			if(destroyDelegate)
				destroyDelegate(this);
			break;

		case WM_NOTIFY:
			NMHDR* hdr = cast(NMHDR*) lParam;
			if(applyDelegate)
				if(hdr.code == PSN_APPLY)
					applyDelegate(this);

			switch(hdr.code)
			{
			case TCN_SELCHANGING:
				// Return FALSE to allow the selection to change.
				return FALSE;
			case TCN_SELCHANGE:
				if(auto tc = cast(TabControl) fromHWND(hdr.hwndFrom))
					tc.raiseWidget(tc.getCurSel());
				return FALSE;
			default:
				break;
			}
			break;

		default:
			break;
		}
		return DefWindowProcA(hWnd, uMsg, wParam, lParam);
	}

	void delegate(Widget w, int cmd) commandDelegate;
	void delegate(Widget w) destroyDelegate;
	void delegate(Widget w) applyDelegate;

	bool doCommand(Widget w, int cmd)
	{
		if(commandDelegate)
			commandDelegate(w, cmd);
		return true;
	}

	HANDLE backgroundBrush;
}

class Dialog : Widget
{
	static bool hasRegistered = false;
	static HBRUSH bgbrush;

	static void registerClass()
	{
		if(hasRegistered)
			return;
		hasRegistered = true;

		DWORD color = GetSysColor(COLOR_BTNFACE);
		bgbrush = CreateSolidBrush(color);

		WNDCLASSA wc;
		wc.lpszClassName = "VisualDDialog";
		wc.style = CS_DBLCLKS | CS_SAVEBITS;
		wc.lpfnWndProc = &DlgWindowProc;
		wc.hInstance = hInst;
		wc.hIcon = null; //DefaultWindowIcon.peer;
		//wc.hIconSm = DefaultWindowSmallIcon.peer;
		wc.hCursor = LoadCursorW(cast(HINSTANCE) null, IDC_ARROW);
		wc.hbrBackground = bgbrush;
		wc.lpszMenuName = null;
		wc.cbClsExtra = 0;
		wc.cbWndExtra = DLGWINDOWEXTRA;
		ATOM atom = RegisterClassA(&wc);
		assert(atom);
	}
	static void unregisterClass()
	{
		if(!hasRegistered)
			return;
		hasRegistered = false;

		UnregisterClassA("VisualDDialog", hInst);
		if(bgbrush)
			DeleteObject(bgbrush);
		bgbrush = null;
	}

	extern(Windows) static int DlgWindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		if (Dialog dlg = cast(Dialog) fromHWND(hWnd))
			return dlg.WindowProc(hWnd,uMsg,wParam,lParam);
		return DefDlgProcA(hWnd, uMsg, wParam, lParam);
	}

	this(Widget parent, string text = "", int id = 0)
	{
		registerClass();
		HWND parenthwnd = parent ? parent.hwnd : null; // VisualDDialog
		createWidget(parent, "#32770", text, WS_CHILD | WS_VISIBLE | DS_3DLOOK | DS_CONTROL, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		SetWindowLongA(hwnd, GWL_WNDPROC, cast(int)cast(void*)&DlgWindowProc);

		super(parent);
	}

	int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		return DefDlgProcA(hWnd, uMsg, wParam, lParam);
	}
}

class Label : Widget
{
	this(Widget parent, string text = "", int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "STATIC", text, SS_LEFTNOWORDWRAP | WS_CHILD | WS_VISIBLE, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)	getDialogFont(), 0);

		super(parent);
	}

	void setText(string str)
	{
		auto lines = std.string.splitLines(str);
		string newline = std.ascii.newline; // join no longer likes immutable seperator
		auto winstr = std.string.join(lines, newline);
		SendMessageW(hwnd, WM_SETTEXT, 0, cast(LPARAM)toUTF16z(winstr));
	}

	uint getTextWidth(string text)
	{
		HANDLE dc = GetDC(hwnd);
		if (!dc)
			return 0;
		scope(exit) ReleaseDC(hwnd, dc);

		auto prevfont = cast(HFONT) SelectObject(dc, getDialogFont());
		if (prevfont == null)
			return 0;
		scope(exit) SelectObject(dc, prevfont);

		wstring wtext = to!wstring(text);
		SIZE size;
		if (GetTextExtentPoint32W(dc, wtext.ptr, wtext.length, &size) == 0)
			return 0;

		return size.cx;
	}
}

class Text : Widget
{
	this(Widget parent, string text = "", int id = 0)
	{
		this(parent, text, id, ES_AUTOHSCROLL, WS_EX_STATICEDGE);
	}

	this(Widget parent, string text, int id, int style, int exstyle)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "EDIT", text, style | WS_CHILD | WS_VISIBLE | WS_TABSTOP, exstyle, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		super(parent);
	}

	void setText(string str)
	{
		auto lines = std.string.splitLines(str);
		string newline = std.ascii.newline; // join no longer likes immutable seperator
		auto winstr = std.string.join(lines, newline);
		SendMessageW(hwnd, WM_SETTEXT, 0, cast(LPARAM)toUTF16z(winstr));
	}

	void setText(wstring str)
	{
		auto lines = std.string.splitLines(str);
		static if(__traits(compiles, std.string.join(lines, "\r\n")))
			auto winstr = std.string.join(lines, "\r\n") ~ "\0";
		else
		{
			wstring winstr;
			if(lines.length > 0)
				winstr = lines[0];
			for(int i = 1; i < lines.length; i++)
				winstr ~= "\r\n" ~ lines[i];
			winstr ~= "\0";
		}
		SendMessageW(hwnd, WM_SETTEXT, 0, cast(LPARAM)winstr.ptr);
	}

	string getText()
	{
		int len = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
		scope buffer = new wchar[len+1];
		SendMessageW(hwnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
		string s = toUTF8(buffer[0..$-1]);
		s = replace(s, "\r", "");
		return s;
	}

	wstring getWText()
	{
		int len = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
		auto buffer = new wchar[len+1];
		SendMessageW(hwnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
		buffer = replace(buffer, "\r", "");
		return assumeUnique(buffer[0..$-1]);
	}
}

class MultiLineText : Text
{
	this(Widget parent, string text = "", int id = 0, bool readonly = false)
	{
		scope lines = std.string.splitLines(text);
		string newline = std.ascii.newline;
		scope winstr = std.string.join(lines, newline);
		uint exstyle = /*WS_HSCROLL |*/ WS_VSCROLL | ES_WANTRETURN | ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL;
		if(readonly)
			exstyle = (exstyle & ~(WS_HSCROLL | ES_AUTOHSCROLL)) | ES_READONLY;
		super(parent, winstr, id, exstyle, 0);

		defWndProc = cast(WNDPROC)cast(void*)GetWindowLongA(hwnd, GWL_WNDPROC);
		SetWindowLongA(hwnd, GWL_WNDPROC, cast(int)cast(void*)&MLTWindowProc);
	}

	extern(Windows) static int MLTWindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		if (MultiLineText mlt = cast(MultiLineText) fromHWND(hWnd))
			return mlt.WindowProc(hWnd,uMsg,wParam,lParam);
		return DefWindowProcA(hWnd, uMsg, wParam, lParam);
	}

	WNDPROC defWndProc;

	static HWND FindDialog(HWND hWnd)
	{
		while(hWnd && (GetWindowLongA(hWnd, GWL_STYLE) & (WS_POPUP | WS_SYSMENU)) == 0)
			hWnd = GetParent(hWnd);
		return hWnd;
	}

	int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
	{
		if(uMsg == WM_CHAR)
		{
			switch(wParam)
			{
				case VK_TAB:
					bool shift = (0x80 & GetKeyState(VK_SHIFT)) != 0;
					.SetFocus(GetNextDlgTabItem(FindDialog(hWnd), hWnd, shift));
					break;
				default:
					break;
			}
		}
		//return DefWindowProcA(hWnd, uMsg, wParam, lParam);
		return CallWindowProcA(cast(FARPROC) defWndProc, hWnd, uMsg, wParam, lParam);
	}
}

class ComboBox : Widget
{
	this(Widget parent, string[] texts, bool editable = true, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		DWORD style = editable ? CBS_DROPDOWN | CBS_AUTOHSCROLL : CBS_DROPDOWNLIST;
		createWidget(parent, "COMBOBOX", "", style | WS_VSCROLL | WS_HSCROLL | WS_CHILD | WS_VISIBLE | WS_TABSTOP, 0, id);

		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		foreach (s; texts)
			SendMessageW(hwnd, CB_ADDSTRING, 0, cast(LPARAM)toUTF16z(s));

		super(parent);
	}

	int findString(string s)
	{
		return SendMessageW(hwnd, CB_FINDSTRING, 0, cast(LPARAM)toUTF16z(s));
	}
	int getSelection()
	{
		return SendMessageA(hwnd, CB_GETCURSEL, 0, 0);
	}
	void setSelection(int n)
	{
		SendMessageA(hwnd, CB_SETCURSEL, n, 0);
	}
	void setSelection(string s)
	{
		SendMessageA(hwnd, CB_SELECTSTRING, 0, cast(LPARAM)toUTF16z(s));
	}
	string getText()
	{
		int len = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
		scope buffer = new wchar[len+1];
		SendMessageW(hwnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
		return toUTF8(buffer[0..$-1]);
	}
	wstring getWText()
	{
		int len = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
		scope buffer = new wchar[len+1];
		SendMessageW(hwnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
		return assumeUnique(buffer[0..$-1]);
	}
}

class ButtonBase : Widget
{
	this(Widget parent) { super(parent); }

	bool isChecked()
	{
		bool res = SendMessageA(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED;
		return res;
	}
	void setChecked(bool x)
	{
		SendMessageA(hwnd, BM_SETCHECK, x ? BST_CHECKED : BST_UNCHECKED, 0);
	}
}

class CheckBox : ButtonBase
{
	this(Widget parent, string intext, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "BUTTON", intext, BS_AUTOCHECKBOX | WS_CHILD | WS_VISIBLE | WS_TABSTOP, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		super(parent);
	}
}

class Button : ButtonBase
{
	this(Widget parent, string intext, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "BUTTON", intext, BS_PUSHBUTTON | WS_CHILD | WS_VISIBLE | WS_TABSTOP, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		super(parent);
	}
}

class Frame : ButtonBase
{
	this(Widget parent, string intext = "", int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "BUTTON", intext, BS_GROUPBOX | WS_CHILD | WS_VISIBLE, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		super(parent);
	}
}

class ToolBar : Widget
{
	this(Widget parent, uint style, uint exstyle, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, TOOLBARCLASSNAMEA, "", style | WS_CHILD | WS_VISIBLE, exstyle, id);
		super(parent);
	}

	bool EnableCheckButton(uint id, bool enable, bool check)
	{
		TBBUTTONINFO tbi;
		tbi.cbSize = TBBUTTONINFO.sizeof;
		tbi.dwMask = TBIF_STATE;
		tbi.fsState = (enable ? TBSTATE_ENABLED : 0)
		            | (check  ? TBSTATE_CHECKED : 0);

		return .SendMessage(hwnd, TB_SETBUTTONINFO, id, cast(LPARAM)&tbi) != 0;
	}
}

class ListView : Widget
{
	this(Widget parent, uint style, uint exstyle, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "SysListView32", "", style | WS_CHILD | WS_VISIBLE | WS_TABSTOP, exstyle, id);
		super(parent);
	}

	int SendItemMessage(uint msg, ref LVITEM lvi)
	{
		return .SendMessage(hwnd, msg, 0, cast(LPARAM)&lvi);
	}
}

class TabControl : Widget
{
	this(Widget parent, string[] tabs, uint style = 0, uint exstyle = 0, int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "SysTabControl32", "", style | WS_CHILD | WS_VISIBLE | WS_TABSTOP, exstyle, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)getDialogFont(), 0);
		super(parent);
		foreach(i, t; tabs)
		{
			TCITEM item;
			item.mask = TCIF_TEXT;
			item.iImage = -1;
			item.pszText = cast(wchar*)toUTF16z(t);
			SendMessageW(hwnd, TCM_INSERTITEMW, i, cast(LPARAM)&item);
			auto p = new Window(parent);
			pages ~= p;
		}
		raiseWidget(0);
	}

	override bool SetWindowPos(HWND hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags)
	{
		if(!super.SetWindowPos(hWndInsertAfter, X, Y, cx, cy, uFlags))
			return false;
		if(uFlags & SWP_NOSIZE)
			return false;
		setPageSize(X, Y, cx, cy);
		return true;
	}

	void setPageSize(int X, int Y, int cx, int cy)
	{
		RECT r;
		r.left = X;
		r.right = X + cx;
		r.top = Y;
		r.bottom = Y + cy;
		SendMessage(TCM_ADJUSTRECT, false, cast(LPARAM)&r);

		foreach(p; pages)
			p.SetWindowPos(null, &r, SWP_NOZORDER | SWP_NOACTIVATE);
	}

	void setHeaderSize(int X, int Y, int cx, int cy)
	{
		RECT r;
		r.left = X;
		r.right = X + cx;
		r.top = Y;
		r.bottom = Y + cy;
		SendMessage(TCM_ADJUSTRECT, false, cast(LPARAM)&r);

		super.setRect(X, Y, cx, r.top - Y);
	}

	override void setRect(int left, int top, int w, int h)
	{
		setHeaderSize(left, top, w, h);
		setPageSize(left, top, w, h);
	}

	override bool GetWindowRect(RECT* rect)
	{
		if(!super.GetWindowRect(rect))
			return false;
		if(!pages.empty)
		{
			RECT pr;
			if (!pages[0].GetWindowRect(&pr))
				return false;
			rect.bottom = pr.bottom;
		}
		return true;
	}

	// space for header and footer
	int getFrameHeight()
	{
		RECT r;
		r.left = 0;
		r.right = 100;
		r.top = 0;
		r.bottom = 100;
		SendMessage(TCM_ADJUSTRECT, false, cast(LPARAM)&r);
		return r.top + (100 - r.bottom);
	}

	int getCurSel()
	{
		return SendMessage(TCM_GETCURSEL, 0, 0);
	}

	void raiseWidget(size_t idx)
	{
		foreach(i, p; pages)
			p.setVisible(i == idx);
	}

	Widget[] pages;
}

int PopupContextMenu(HWND hwnd, POINT pt, wstring[] entries, int check = -1, int presel = -1)
{
	HMENU hmnu = CreatePopupMenu();
	if(!hmnu)
		return -1;
	scope(exit) DestroyMenu(hmnu);

	MENUITEMINFO mii;
	mii.cbSize = mii.sizeof;
	mii.fMask = MIIM_FTYPE | MIIM_ID | MIIM_STATE | MIIM_STRING;
	mii.fType = MFT_STRING;

	wchar*[] entriesz;
	for (int i = 0; i < entries.length; i++)
	{
		mii.fState = (i == check ? MFS_CHECKED : 0) | (i == presel ? MFS_DEFAULT : 0);

		wchar* pz = cast(wchar*) (entries[i] ~ '\0').ptr;
		entriesz ~= pz;
		mii.wID = i + 1;
		mii.dwTypeData = pz;
		if(!InsertMenuItem(hmnu, cast(UINT)i + 1, TRUE, &mii))
			return -1;
	}

	UINT uiCmd = TrackPopupMenuEx(hmnu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_HORIZONTAL | TPM_TOPALIGN | TPM_LEFTALIGN, pt.x, pt.y, hwnd, null);
	if (uiCmd)
		return uiCmd - 1;

	HRESULT hr = HResultFromLastError();
	return -1;
}

struct Attachment
{
	// specify the fraction that the control receives from a size change
	short hdiv;
	short left;  // left edge will receive left/hdiv of change
	short right;
	short vdiv;
	short top;
	short bottom;
}

enum kAttachNone      = Attachment(1, 0, 0, 1, 0, 0);
enum kAttachLeftRight = Attachment(1, 0, 1, 1, 0, 0);
enum kAttachRight     = Attachment(1, 1, 1, 1, 0, 0);
enum kAttachTopBottom = Attachment(1, 0, 0, 1, 0, 1);
enum kAttachBottom    = Attachment(1, 0, 0, 1, 1, 1);
enum kAttachAll       = Attachment(1, 0, 1, 1, 0, 1);

struct AttachData
{
	Attachment att;
	short initleft;   // initial rect of child window relative to parent
	short initright;
	short inittop;
	short initbottom;
	short initwidth;  // initial parent width
	short initheight; // initial parent height

	bool initFromWidget(Widget w)
	{
		RECT r, pr;
		if (!w.GetWindowRect(&r))
			return false;
		if (!w.parent || !w.parent.GetWindowRect(&pr))
			return false;

		initwidth  = cast(short) (pr.right - pr.left);
		initheight = cast(short) (pr.bottom - pr.top);
		initleft   = cast(short) (r.left - pr.left);
		initright  = cast(short) (r.right - pr.left);
		inittop    = cast(short) (r.top - pr.top);
		initbottom = cast(short) (r.bottom - pr.top);

		//logCall("initFromWidget(", w, ":", cast(void*)w, ") = w:", initwidth, " h:", initheight, " l:", initleft, " r:", initright, " t:", inittop, " b:", initbottom);
		return true;
	}

	bool resizeWidget(Widget w)
	{
		RECT pr;
		if (!w.parent || !w.parent.GetWindowRect(&pr))
			return false;

		int dx      = pr.right  - pr.left - initwidth;
		int dy      = pr.bottom - pr.top  - initheight;
		int hdiv    = max(1, att.hdiv);
		int vdiv    = max(1, att.vdiv);

		int nleft   = initleft   + dx * att.left   / hdiv;
		int nright  = initright  + dx * att.right  / hdiv;
		int ntop    = inittop    + dy * att.top    / vdiv;
		int nbottom = initbottom + dy * att.bottom / vdiv;

		//logCall("resizeWidget(", w, ":", cast(void*)w, ") to [l:", nleft, " t:", ntop, " w:", nright - nleft, " h:", nbottom - ntop, "]");

		w.setRect(nleft, ntop, nright - nleft, nbottom - ntop);
		return true;
	}
}

bool initWinControls(HINSTANCE inst)
{
	hInst = inst;
	Window.registerClass();
	Dialog.registerClass();
	return true;
}

bool exitWinControls(HINSTANCE inst)
{
	Window.unregisterClass();
	Dialog.unregisterClass();
	return true;
}
