// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.wmmsg;

import visuald.windows;
import visuald.logutil;

string msg_toString(uint msg)
{
	if(msg == WM_NULL) return "WM_NULL";
	if(msg == WM_CREATE) return "WM_CREATE";
	if(msg == WM_DESTROY) return "WM_DESTROY";
	if(msg == WM_MOVE) return "WM_MOVE";
	if(msg == WM_SIZE) return "WM_SIZE";
	if(msg == WM_ACTIVATE) return "WM_ACTIVATE";
	if(msg == WM_SETFOCUS) return "WM_SETFOCUS";
	if(msg == WM_KILLFOCUS) return "WM_KILLFOCUS";
	if(msg == WM_ENABLE) return "WM_ENABLE";
	if(msg == WM_SETREDRAW) return "WM_SETREDRAW";
	if(msg == WM_SETTEXT) return "WM_SETTEXT";
	if(msg == WM_GETTEXT) return "WM_GETTEXT";
	if(msg == WM_GETTEXTLENGTH) return "WM_GETTEXTLENGTH";
	if(msg == WM_PAINT) return "WM_PAINT";
	if(msg == WM_CLOSE) return "WM_CLOSE";
	if(msg == WM_QUERYENDSESSION) return "WM_QUERYENDSESSION";
	if(msg == WM_QUERYOPEN) return "WM_QUERYOPEN";
	if(msg == WM_ENDSESSION) return "WM_ENDSESSION";
	if(msg == WM_QUIT) return "WM_QUIT";
	if(msg == WM_ERASEBKGND) return "WM_ERASEBKGND";
	if(msg == WM_SYSCOLORCHANGE) return "WM_SYSCOLORCHANGE";
	if(msg == WM_SHOWWINDOW) return "WM_SHOWWINDOW";
	if(msg == WM_WININICHANGE) return "WM_WININICHANGE";
	if(msg == WM_WININICHANGE               ) return "WM_WININICHANGE               ";
	if(msg == WM_DEVMODECHANGE) return "WM_DEVMODECHANGE";
	if(msg == WM_ACTIVATEAPP) return "WM_ACTIVATEAPP";
	if(msg == WM_FONTCHANGE) return "WM_FONTCHANGE";
	if(msg == WM_TIMECHANGE) return "WM_TIMECHANGE";
	if(msg == WM_CANCELMODE) return "WM_CANCELMODE";
	if(msg == WM_SETCURSOR) return "WM_SETCURSOR";
	if(msg == WM_MOUSEACTIVATE) return "WM_MOUSEACTIVATE";
	if(msg == WM_CHILDACTIVATE) return "WM_CHILDACTIVATE";
	if(msg == WM_QUEUESYNC) return "WM_QUEUESYNC";
	if(msg == WM_GETMINMAXINFO) return "WM_GETMINMAXINFO";
	if(msg == WM_PAINTICON) return "WM_PAINTICON";
	if(msg == WM_ICONERASEBKGND) return "WM_ICONERASEBKGND";
	if(msg == WM_NEXTDLGCTL) return "WM_NEXTDLGCTL";
	if(msg == WM_SPOOLERSTATUS) return "WM_SPOOLERSTATUS";
	if(msg == WM_DRAWITEM) return "WM_DRAWITEM";
	if(msg == WM_MEASUREITEM) return "WM_MEASUREITEM";
	if(msg == WM_DELETEITEM) return "WM_DELETEITEM";
	if(msg == WM_VKEYTOITEM) return "WM_VKEYTOITEM";
	if(msg == WM_CHARTOITEM) return "WM_CHARTOITEM";
	if(msg == WM_SETFONT) return "WM_SETFONT";
	if(msg == WM_GETFONT) return "WM_GETFONT";
	if(msg == WM_SETHOTKEY) return "WM_SETHOTKEY";
	if(msg == WM_GETHOTKEY) return "WM_GETHOTKEY";
	if(msg == WM_QUERYDRAGICON) return "WM_QUERYDRAGICON";
	if(msg == WM_COMPAREITEM) return "WM_COMPAREITEM";
	if(msg == WM_GETOBJECT) return "WM_GETOBJECT";
	if(msg == WM_COMPACTING) return "WM_COMPACTING";
	if(msg == WM_COMMNOTIFY) return "WM_COMMNOTIFY";
	if(msg == WM_WINDOWPOSCHANGING) return "WM_WINDOWPOSCHANGING";
	if(msg == WM_WINDOWPOSCHANGED) return "WM_WINDOWPOSCHANGED";
	if(msg == WM_POWER) return "WM_POWER";

	if(msg == WM_NOTIFY) return "WM_NOTIFY";
	if(msg == WM_INPUTLANGCHANGEREQUEST) return "WM_INPUTLANGCHANGEREQUEST";
	if(msg == WM_INPUTLANGCHANGE) return "WM_INPUTLANGCHANGE";
	if(msg == WM_TCARD) return "WM_TCARD";
	if(msg == WM_HELP) return "WM_HELP";
	if(msg == WM_USERCHANGED) return "WM_USERCHANGED";
	if(msg == WM_NOTIFYFORMAT) return "WM_NOTIFYFORMAT";
	if(msg == WM_CONTEXTMENU) return "WM_CONTEXTMENU";
	if(msg == WM_STYLECHANGING) return "WM_STYLECHANGING";
	if(msg == WM_STYLECHANGED) return "WM_STYLECHANGED";
	if(msg == WM_DISPLAYCHANGE) return "WM_DISPLAYCHANGE";
	if(msg == WM_GETICON) return "WM_GETICON";
	if(msg == WM_SETICON) return "WM_SETICON";

	if(msg == WM_NCCREATE) return "WM_NCCREATE";
	if(msg == WM_NCDESTROY) return "WM_NCDESTROY";
	if(msg == WM_NCCALCSIZE) return "WM_NCCALCSIZE";
	if(msg == WM_NCHITTEST) return "WM_NCHITTEST";
	if(msg == WM_NCPAINT) return "WM_NCPAINT";
	if(msg == WM_NCACTIVATE) return "WM_NCACTIVATE";
	if(msg == WM_GETDLGCODE) return "WM_GETDLGCODE";
	if(msg == WM_SYNCPAINT) return "WM_SYNCPAINT";

	if(msg == WM_NCMOUSEMOVE) return "WM_NCMOUSEMOVE";
	if(msg == WM_NCLBUTTONDOWN) return "WM_NCLBUTTONDOWN";
	if(msg == WM_NCLBUTTONUP) return "WM_NCLBUTTONUP";
	if(msg == WM_NCLBUTTONDBLCLK) return "WM_NCLBUTTONDBLCLK";
	if(msg == WM_NCRBUTTONDOWN) return "WM_NCRBUTTONDOWN";
	if(msg == WM_NCRBUTTONUP) return "WM_NCRBUTTONUP";
	if(msg == WM_NCRBUTTONDBLCLK) return "WM_NCRBUTTONDBLCLK";
	if(msg == WM_NCMBUTTONDOWN) return "WM_NCMBUTTONDOWN";
	if(msg == WM_NCMBUTTONUP) return "WM_NCMBUTTONUP";
	if(msg == WM_NCMBUTTONDBLCLK) return "WM_NCMBUTTONDBLCLK";
	if(msg == WM_NCXBUTTONDOWN) return "WM_NCXBUTTONDOWN";
	if(msg == WM_NCXBUTTONUP) return "WM_NCXBUTTONUP";
	if(msg == WM_NCXBUTTONDBLCLK) return "WM_NCXBUTTONDBLCLK";
	if(msg == WM_INPUT_DEVICE_CHANGE) return "WM_INPUT_DEVICE_CHANGE";
	if(msg == WM_INPUT) return "WM_INPUT";

	if(msg == WM_KEYFIRST) return "WM_KEYFIRST";
	if(msg == WM_KEYDOWN) return "WM_KEYDOWN";
	if(msg == WM_KEYUP) return "WM_KEYUP";
	if(msg == WM_CHAR) return "WM_CHAR";
	if(msg == WM_DEADCHAR) return "WM_DEADCHAR";
	if(msg == WM_SYSKEYDOWN) return "WM_SYSKEYDOWN";
	if(msg == WM_SYSKEYUP) return "WM_SYSKEYUP";
	if(msg == WM_SYSCHAR) return "WM_SYSCHAR";
	if(msg == WM_SYSDEADCHAR) return "WM_SYSDEADCHAR";
	if(msg == WM_UNICHAR) return "WM_UNICHAR";
	if(msg == WM_KEYLAST) return "WM_KEYLAST";
	if(msg == UNICODE_NOCHAR) return "UNICODE_NOCHAR";
	if(msg == WM_IME_STARTCOMPOSITION) return "WM_IME_STARTCOMPOSITION";
	if(msg == WM_IME_ENDCOMPOSITION) return "WM_IME_ENDCOMPOSITION";
	if(msg == WM_IME_COMPOSITION) return "WM_IME_COMPOSITION";
	if(msg == WM_IME_KEYLAST) return "WM_IME_KEYLAST";

	if(msg == WM_INITDIALOG) return "WM_INITDIALOG";
	if(msg == WM_COMMAND) return "WM_COMMAND";
	if(msg == WM_SYSCOMMAND) return "WM_SYSCOMMAND";
	if(msg == WM_TIMER) return "WM_TIMER";
	if(msg == WM_HSCROLL) return "WM_HSCROLL";
	if(msg == WM_VSCROLL) return "WM_VSCROLL";
	if(msg == WM_INITMENU) return "WM_INITMENU";
	if(msg == WM_INITMENUPOPUP) return "WM_INITMENUPOPUP";
	if(msg == WM_MENUSELECT) return "WM_MENUSELECT";
	if(msg == WM_MENUCHAR) return "WM_MENUCHAR";
	if(msg == WM_ENTERIDLE) return "WM_ENTERIDLE";
	if(msg == WM_MENURBUTTONUP) return "WM_MENURBUTTONUP";
	if(msg == WM_MENUDRAG) return "WM_MENUDRAG";
	if(msg == WM_MENUGETOBJECT) return "WM_MENUGETOBJECT";
	if(msg == WM_UNINITMENUPOPUP) return "WM_UNINITMENUPOPUP";
	if(msg == WM_MENUCOMMAND) return "WM_MENUCOMMAND";
	if(msg == WM_CHANGEUISTATE) return "WM_CHANGEUISTATE";
	if(msg == WM_UPDATEUISTATE) return "WM_UPDATEUISTATE";
	if(msg == WM_QUERYUISTATE) return "WM_QUERYUISTATE";

	if(msg == WM_CTLCOLORMSGBOX) return "WM_CTLCOLORMSGBOX";
	if(msg == WM_CTLCOLOREDIT) return "WM_CTLCOLOREDIT";
	if(msg == WM_CTLCOLORLISTBOX) return "WM_CTLCOLORLISTBOX";
	if(msg == WM_CTLCOLORBTN) return "WM_CTLCOLORBTN";
	if(msg == WM_CTLCOLORDLG) return "WM_CTLCOLORDLG";
	if(msg == WM_CTLCOLORSCROLLBAR) return "WM_CTLCOLORSCROLLBAR";
	if(msg == WM_CTLCOLORSTATIC) return "WM_CTLCOLORSTATIC";
	if(msg == MN_GETHMENU) return "MN_GETHMENU";

	if(msg == WM_MOUSEMOVE) return "WM_MOUSEMOVE";
	if(msg == WM_LBUTTONDOWN) return "WM_LBUTTONDOWN";
	if(msg == WM_LBUTTONUP) return "WM_LBUTTONUP";
	if(msg == WM_LBUTTONDBLCLK) return "WM_LBUTTONDBLCLK";
	if(msg == WM_RBUTTONDOWN) return "WM_RBUTTONDOWN";
	if(msg == WM_RBUTTONUP) return "WM_RBUTTONUP";
	if(msg == WM_RBUTTONDBLCLK) return "WM_RBUTTONDBLCLK";
	if(msg == WM_MBUTTONDOWN) return "WM_MBUTTONDOWN";
	if(msg == WM_MBUTTONUP) return "WM_MBUTTONUP";
	if(msg == WM_MBUTTONDBLCLK) return "WM_MBUTTONDBLCLK";
	if(msg == WM_MOUSEWHEEL) return "WM_MOUSEWHEEL";
	if(msg == WM_XBUTTONDOWN) return "WM_XBUTTONDOWN";
	if(msg == WM_XBUTTONUP) return "WM_XBUTTONUP";
	if(msg == WM_XBUTTONDBLCLK) return "WM_XBUTTONDBLCLK";
	if(msg == WM_MOUSEHWHEEL) return "WM_MOUSEHWHEEL";

	if(msg == WM_PARENTNOTIFY) return "WM_PARENTNOTIFY";
	if(msg == WM_ENTERMENULOOP) return "WM_ENTERMENULOOP";
	if(msg == WM_EXITMENULOOP) return "WM_EXITMENULOOP";
	if(msg == WM_NEXTMENU) return "WM_NEXTMENU";
	if(msg == WM_SIZING) return "WM_SIZING";
	if(msg == WM_CAPTURECHANGED) return "WM_CAPTURECHANGED";
	if(msg == WM_MOVING) return "WM_MOVING";

	if(msg == WM_POWERBROADCAST) return "WM_POWERBROADCAST";

	if(msg == WM_DEVICECHANGE) return "WM_DEVICECHANGE";
	if(msg == WM_MDICREATE) return "WM_MDICREATE";
	if(msg == WM_MDIDESTROY) return "WM_MDIDESTROY";
	if(msg == WM_MDIACTIVATE) return "WM_MDIACTIVATE";
	if(msg == WM_MDIRESTORE) return "WM_MDIRESTORE";
	if(msg == WM_MDINEXT) return "WM_MDINEXT";
	if(msg == WM_MDIMAXIMIZE) return "WM_MDIMAXIMIZE";
	if(msg == WM_MDITILE) return "WM_MDITILE";
	if(msg == WM_MDICASCADE) return "WM_MDICASCADE";
	if(msg == WM_MDIICONARRANGE) return "WM_MDIICONARRANGE";
	if(msg == WM_MDIGETACTIVE) return "WM_MDIGETACTIVE";

	if(msg == WM_MDISETMENU) return "WM_MDISETMENU";
	if(msg == WM_ENTERSIZEMOVE) return "WM_ENTERSIZEMOVE";
	if(msg == WM_EXITSIZEMOVE) return "WM_EXITSIZEMOVE";
	if(msg == WM_DROPFILES) return "WM_DROPFILES";
	if(msg == WM_MDIREFRESHMENU) return "WM_MDIREFRESHMENU";
	if(msg == WM_IME_SETCONTEXT) return "WM_IME_SETCONTEXT";
	if(msg == WM_IME_NOTIFY) return "WM_IME_NOTIFY";
	if(msg == WM_IME_CONTROL) return "WM_IME_CONTROL";
	if(msg == WM_IME_COMPOSITIONFULL) return "WM_IME_COMPOSITIONFULL";
	if(msg == WM_IME_SELECT) return "WM_IME_SELECT";
	if(msg == WM_IME_CHAR) return "WM_IME_CHAR";
	if(msg == WM_IME_REQUEST) return "WM_IME_REQUEST";
	if(msg == WM_IME_KEYDOWN) return "WM_IME_KEYDOWN";
	if(msg == WM_IME_KEYUP) return "WM_IME_KEYUP";
	if(msg == WM_MOUSEHOVER) return "WM_MOUSEHOVER";
	if(msg == WM_MOUSELEAVE) return "WM_MOUSELEAVE";
	if(msg == WM_NCMOUSEHOVER) return "WM_NCMOUSEHOVER";
	if(msg == WM_NCMOUSELEAVE) return "WM_NCMOUSELEAVE";
	if(msg == WM_WTSSESSION_CHANGE) return "WM_WTSSESSION_CHANGE";

	if(msg >= WM_TABLET_FIRST && msg <= WM_TABLET_LAST) return "WM_TABLET_nnn";

	if(msg == WM_CUT) return "WM_CUT";
	if(msg == WM_COPY) return "WM_COPY";
	if(msg == WM_PASTE) return "WM_PASTE";
	if(msg == WM_CLEAR) return "WM_CLEAR";
	if(msg == WM_UNDO) return "WM_UNDO";
	if(msg == WM_RENDERFORMAT) return "WM_RENDERFORMAT";
	if(msg == WM_RENDERALLFORMATS) return "WM_RENDERALLFORMATS";
	if(msg == WM_DESTROYCLIPBOARD) return "WM_DESTROYCLIPBOARD";
	if(msg == WM_DRAWCLIPBOARD) return "WM_DRAWCLIPBOARD";
	if(msg == WM_PAINTCLIPBOARD) return "WM_PAINTCLIPBOARD";
	if(msg == WM_VSCROLLCLIPBOARD) return "WM_VSCROLLCLIPBOARD";
	if(msg == WM_SIZECLIPBOARD) return "WM_SIZECLIPBOARD";
	if(msg == WM_ASKCBFORMATNAME) return "WM_ASKCBFORMATNAME";
	if(msg == WM_CHANGECBCHAIN) return "WM_CHANGECBCHAIN";
	if(msg == WM_HSCROLLCLIPBOARD) return "WM_HSCROLLCLIPBOARD";
	if(msg == WM_QUERYNEWPALETTE) return "WM_QUERYNEWPALETTE";
	if(msg == WM_PALETTEISCHANGING) return "WM_PALETTEISCHANGING";
	if(msg == WM_PALETTECHANGED) return "WM_PALETTECHANGED";
	if(msg == WM_HOTKEY) return "WM_HOTKEY";
	if(msg == WM_PRINT) return "WM_PRINT";
	if(msg == WM_PRINTCLIENT) return "WM_PRINTCLIENT";
	if(msg == WM_APPCOMMAND) return "WM_APPCOMMAND";
	if(msg == WM_THEMECHANGED) return "WM_THEMECHANGED";
	if(msg == WM_CLIPBOARDUPDATE) return "WM_CLIPBOARDUPDATE";
	if(msg == WM_DWMCOMPOSITIONCHANGED) return "WM_DWMCOMPOSITIONCHANGED";
	if(msg == WM_DWMNCRENDERINGCHANGED) return "WM_DWMNCRENDERINGCHANGED";
	if(msg == WM_DWMCOLORIZATIONCOLORCHANGED) return "WM_DWMCOLORIZATIONCOLORCHANGED";
	if(msg == WM_DWMWINDOWMAXIMIZEDCHANGE) return "WM_DWMWINDOWMAXIMIZEDCHANGE";
	if(msg == WM_GETTITLEBARINFOEX) return "WM_GETTITLEBARINFOEX";

	return "";
}

void logMessage(string prefix, HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam)
{
	debug
	{
		string msg = msg_toString(uMsg);
		if(msg.length == 0)
			msg = tryformat("%x", uMsg);

		logCall("%s(hwnd=%x, msg=%s, wp=%x, lp=%x)", prefix, hWnd, msg, wParam, lParam);
	}
}
