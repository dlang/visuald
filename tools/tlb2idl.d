module tlbidl;

import core.sys.windows.windows;
import std.c.windows.com; // deprecated, but kept to still build with 2.066
import core.stdc.string;
import std.stdio;
import std.file;
import std.path;

import std.utf;

interface ITypeLib : IUnknown
{
}

static IID IID_IInterfaceViewer =
{
	0xfc37e5ba,
	0x4a8e,
	0x11ce,
	[ 0x87, 0x0b, 0x08, 0x00, 0x36, 0x8d, 0x23, 0x02 ]
};

interface IInterfaceViewer : IUnknown
{
	HRESULT View (HWND hwndParent, const ref IID riid, IUnknown punk);
}

// CLSIDs of viewers implemented in IVIEWER.DLL
//
static CLSID CLSID_ITypeLibViewer = { 0x57efbf49, 0x4a8b, 0x11ce, [ 0x87, 0xb,  0x8,  0x0,  0x36, 0x8d, 0x23, 0x2 ] };
//DEFINE_GUID(CLSID_IDataObjectViewer, 0x28d8aba0, 0x4b78, 0x11ce, 0xb2, 0x7d, 0x0,  0xaa, 0x0,  0x1f, 0x73, 0xc1);
//DEFINE_GUID(CLSID_IDispatchViewer,   0xd2af7a60, 0x4c42, 0x11ce, 0xb2, 0x7d, 0x00, 0xaa, 0x00, 0x1f, 0x73, 0xc1) ;

nothrow {
extern(Windows)
HRESULT LoadTypeLib(wchar* path, ITypeLib *pLib);

extern(Windows)
HANDLE LoadLibraryW(wchar* path);

extern(Windows)
export BOOL SendMessageW(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

extern(Windows)
HWND FindWindowExA(HWND hwndParent, HWND hwndChildAfter, LPCSTR lpszClass, LPCSTR lpszWindow);

alias
extern(Windows)
HRESULT fnDllGetClassObject(const CLSID* rclsid, const IID* riid, LPVOID* ppv);

string idltext;

extern(Windows)
HWND GetParent(HWND hWnd);

alias
extern(Windows)
BOOL fnEnumWindows(HWND hwnd, LPARAM lParam);

extern(Windows)
BOOL EnumWindows(fnEnumWindows* lpEnumFunc, LPARAM lParam) nothrow;

extern(Windows)
alias BOOL function(HWND, LPARAM) nothrow WNDENUMPROC;

extern(Windows)
BOOL EnumChildWindows(HWND hWndParent, WNDENUMPROC lpEnumFunc, LPARAM lParam) nothrow;

const GA_ROOTOWNER = 3;

extern(Windows)
HWND GetAncestor(HWND hwnd, UINT gaFlags);

extern(Windows)
HWND GetWindow(HWND hWnd, UINT uCmd) nothrow;

const GW_OWNER = 4;

extern(Windows)
int GetClassNameA(HWND hWnd, LPSTR lpClassName, int nMaxCount) nothrow;

extern(Windows)
BOOL CloseWindow(HWND hWnd);

extern(Windows)
BOOL PostMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
} // nothrow

HWND myWindow;
HWND foundWindow;

extern(Windows)
BOOL EnumWindowsProcIdl(HWND hwnd, LPARAM lParam) nothrow
{
	if(GetWindow(hwnd, GW_OWNER) == myWindow)
	{
		char[100] cname;
		GetClassNameA(hwnd, cname.ptr, 100);
		if(cname[0..3] != "IME")
			foundWindow = hwnd;
	}
	return TRUE;
}

extern(Windows)
BOOL EnumChild(HWND hwnd, LPARAM lParam) nothrow
{
	char[100] cname;
	GetClassNameA(hwnd, cname.ptr, 100);
	if(strcmp(cname.ptr, "RICHEDIT".ptr) == 0)
	{
		*cast(HWND*) lParam = hwnd;
		return FALSE;
	}

	EnumChildWindows(hwnd, &EnumChild, lParam);
	return TRUE;
}

HWND FindRichEdit(HWND root) nothrow
{
	HWND found;
	EnumChildWindows(root, &EnumChild, cast(LPARAM) &found);
	return found;
}

extern(Windows)
int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam) nothrow
{
	if(myWindow)
		EnumWindows(&EnumWindowsProcIdl, 0);
	if(foundWindow)
	{
		HWND hnd = FindRichEdit(foundWindow);
		if(hnd)
		{
			int len = SendMessageW(hnd, WM_GETTEXTLENGTH, 0, 0);
			scope buffer = new wchar[len+1];
			SendMessageW(hnd, WM_GETTEXT, cast(WPARAM)(len+1), cast(LPARAM)buffer.ptr);
			try
			{
				idltext = toUTF8(buffer[0..$-1]);
			}
			catch
			{
			}
			if(idltext.length > 0)
			{
				PostMessageA(foundWindow, WM_CLOSE, 0, 0);
//				CloseWindow(foundWindow);
			}
		}
	}
	return DefWindowProcA(hWnd, uMsg, wParam, lParam);
}

void main(string[] argv)
{
	string ivdll = r"c:\Programme\Microsoft SDKs\Windows\v6.0A\bin\IViewers.Dll";
	if(argv.length > 3)
		ivdll = argv[3];
	string outidl = "out.idl";
	if(argv.length > 2)
		outidl = argv[2];
	string olb = r"c:\Programme\Gemeinsame Dateien\Microsoft Shared\MSEnv\dte80a.olb";
	if(argv.length > 1)
		olb = argv[1];

	wchar* path = cast(wchar*)toUTF16z(olb);
	ITypeLib lib;
	HRESULT rc = LoadTypeLib(path, &lib);
	if(FAILED(rc))
		throw new Exception("LoadTypeLib failed on " ~ olb);

	debug writefln("lib = %s", cast(void*)lib);

	wchar* ivdllpath = cast(wchar*)toUTF16z(ivdll);
	HANDLE m = LoadLibraryW(ivdllpath);
	if(!m)
	{
		// try subfolder x86 for Windows SDK 8.0
		string ivdll2 = dirName(ivdll) ~ "\\x86\\" ~ baseName(ivdll);
		ivdllpath = cast(wchar*)toUTF16z(ivdll2);
		m = LoadLibraryW(ivdllpath);
		if(m)
			ivdll = ivdll2;
	}
	if(!m)
		throw new Exception("LoadLibrary failed on " ~ ivdll);

	debug writefln("m = %s", cast(void*)m);
	fnDllGetClassObject* fn = cast(fnDllGetClassObject*) GetProcAddress(m, "DllGetClassObject".ptr);
	if(!fn)
		throw new Exception("GetProcAddress(\"DllGetClassObject\") fails on " ~ ivdll);

	debug writefln("fn = %s", cast(void*)fn);
	IInterfaceViewer viewer;
	IClassFactory factory;
	IID iid_IClassFactory = IID_IClassFactory; // must make a copy because "IID_IClassFactory is not an lvalue"!?
	rc = (*fn)(&CLSID_ITypeLibViewer, &iid_IClassFactory, cast(void**)&factory);
	if(FAILED(rc) || !factory)
		throw new Exception("failed to create class factory");

	debug writefln("factory = %s", cast(void*)factory);
	rc = factory.CreateInstance(null, &IID_IInterfaceViewer, cast(void**)&viewer);
	if(FAILED(rc) || !viewer)
		throw new Exception("failed to create interface viewer");

	debug writefln("viewer = %s", cast(void*)viewer);

	HINSTANCE hInst = GetModuleHandleA(null);
	WNDCLASSA wc;
	wc.lpszClassName = "DummyWindow";
	wc.style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc = &WindowProc;
	wc.hInstance = hInst;
	wc.hIcon = null; //DefaultWindowIcon.peer;
	//wc.hIconSm = DefaultWindowSmallIcon.peer;
	static if(is(typeof(IDC_ARROW) : const(wchar)*))
		wc.hCursor = LoadCursorW(cast(HINSTANCE) null, IDC_ARROW);
	else
		wc.hCursor = LoadCursorA(cast(HINSTANCE) null, IDC_ARROW);

	wc.hbrBackground = null;
	wc.lpszMenuName = null;
	wc.cbClsExtra = 0;
	wc.cbWndExtra = 0;
	ATOM atom = RegisterClassA(&wc);
	assert(atom);

	HWND hwnd = CreateWindowExA(0, "DummyWindow".ptr, "".ptr, WS_OVERLAPPED,
				CW_USEDEFAULT, CW_USEDEFAULT, 10, 10,
				null, null, hInst, null);

	//writefln("hwnd = %s", cast(void*)hwnd);
	myWindow = hwnd;
	IID iid_ITypeLib = IID_ITypeLib; // must make a copy because IID_ITypeLib is not an lvalue!?
	viewer.View(hwnd, iid_ITypeLib, lib);

	std.file.write(outidl, idltext);
}
