module winctrl;

import std.c.windows.windows;
import std.utf;
import sdk.port.base;

enum
{
    CBS_SIMPLE            =0x0001L,
    CBS_DROPDOWN          =0x0002L,
    CBS_DROPDOWNLIST      =0x0003L,
    CBS_OWNERDRAWFIXED    =0x0010L,
    CBS_OWNERDRAWVARIABLE =0x0020L,
    CBS_AUTOHSCROLL       =0x0040L,
    CBS_OEMCONVERT        =0x0080L,
    CBS_SORT              =0x0100L,
    CBS_HASSTRINGS        =0x0200L,
    CBS_NOINTEGRALHEIGHT  =0x0400L,
    CBS_DISABLENOSCROLL   =0x0800L,
    CBS_UPPERCASE           =0x2000L,
    CBS_LOWERCASE           =0x4000L,
}

const CB_ADDSTRING = 0x0143;
const CB_FINDSTRING = 0x014C;
const CB_SELECTSTRING = 0x014D;
const CB_SETCURSEL = 0x014E;
const CB_GETCURSEL = 0x0147;

const GWL_USERDATA = -21;
const WS_EX_STATICEDGE = 0x00020000;
const WM_SETFONT = 0x0030;
const TRANSPARENT = 1;

const PSN_APPLY = -202;
const GA_ROOT = 2;

extern(Windows)
{
export BOOL UnregisterClassA(LPCSTR lpClassName, HINSTANCE hInstance);
export LONG GetWindowLongA(HWND hWnd,int nIndex);
export int SetWindowLongA(HWND hWnd, int nIndex, int dwNewLong);
export DWORD GetSysColor(int);
export BOOL DestroyWindow(HWND hWnd);
export HBRUSH CreateSolidBrush(COLORREF c);
export BOOL MoveWindow(HWND hWnd, int x, int y, int w, int h, byte bRepaint);
export BOOL EnableWindow (HWND hWnd, BOOL enable);
export HWND CreateWindowExW(DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName, DWORD dwStyle,
    int X, int Y, int nWidth, int nHeight, HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam);
export BOOL SendMessageW(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);
HWND GetAncestor(HWND hwnd, UINT gaFlags);

struct NMHDR
{
	HWND      hwndFrom;
	UINT_PTR  idFrom;
	UINT      code;         // NM_ code
}
}

private Widget[Widget] createdWindows; // collection of all windows with HWND to avoid garbage collection
private HINSTANCE hInst;

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
	
	static Widget fromHWND(HWND hwnd) 
	{
		return cast(Widget)cast(void*)GetWindowLongA(hwnd, GWL_USERDATA);
	}
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
		wc.hCursor = LoadCursorA(cast(HINSTANCE) null, IDC_ARROW);
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

	this(HWND h)
	{
		hwnd = h;
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

	void Dispose()
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

class Label : Widget
{
	this(Widget parent, string text = "", int id = 0)
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "STATIC", text, SS_LEFTNOWORDWRAP | WS_CHILD | WS_VISIBLE, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)GetStockObject(DEFAULT_GUI_FONT), 0);

		super(parent);
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
		createWidget(parent, "EDIT", text, style | WS_CHILD | WS_VISIBLE, exstyle, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)GetStockObject(DEFAULT_GUI_FONT), 0);
		super(parent);
	}

	void setText(string str) {
		auto lines = std.string.splitlines(str);
		auto winstr = std.string.join(lines, std.string.newline);
		SendMessageW(hwnd, WM_SETTEXT, 0, cast(LPARAM)toUTF16z(winstr));
	}

        string getText() 
	{
		int len = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
                scope buffer = new wchar[len+1];
                SendMessageW(hwnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
                return toUTF8(buffer[0..$-1]);
	}

}

class MultiLineText : Text
{
	this(Widget parent, string text = "", int id = 0, bool readonly = false)
	{
		scope lines = std.string.splitlines(text);
		scope winstr = std.string.join(lines, std.string.newline);
		uint exstyle = WS_HSCROLL | WS_VSCROLL | ES_WANTRETURN | ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL;
		if(readonly)
			exstyle = (exstyle & ~(WS_HSCROLL | ES_AUTOHSCROLL)) | ES_READONLY;
		super(parent, winstr, id, exstyle, 0);
	}
}

class ComboBox : Widget
{
        this(Widget parent, string[] texts, bool editable = true, int id = 0) 
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		DWORD style = editable ? CBS_DROPDOWN | CBS_AUTOHSCROLL : CBS_DROPDOWNLIST;
		createWidget(parent, "COMBOBOX", "", style | WS_VSCROLL | WS_HSCROLL | WS_CHILD | WS_VISIBLE, 0, id);
            
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)GetStockObject(DEFAULT_GUI_FONT), 0);
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
}

class CheckBox : Widget
{
	this(Widget parent, string intext, int id = 0) 
	{
		HWND parenthwnd = parent ? parent.hwnd : null;
		createWidget(parent, "BUTTON", intext, BS_AUTOCHECKBOX | WS_CHILD | WS_VISIBLE, 0, id);
		SendMessageA(hwnd, WM_SETFONT, cast(WPARAM)GetStockObject(DEFAULT_GUI_FONT), 0);
		super(parent);
	}

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

bool initWinControls(HINSTANCE inst)
{
	hInst = inst;
	Window.registerClass();
	return true;
}

bool exitWinControls(HINSTANCE inst)
{
	Window.unregisterClass();
	return true;
}
