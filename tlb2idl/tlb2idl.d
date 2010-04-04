module tlbodl;

import std.c.windows.windows;
import std.c.windows.com;
import std.c.string;
import std.stdio;
import std.file;

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
	HRESULT View (HWND hwndParent, ref IID riid, IUnknown punk);
}

// CLSIDs of viewers implemented in IVIEWER.DLL
//
static CLSID CLSID_ITypeLibViewer = { 0x57efbf49, 0x4a8b, 0x11ce, [ 0x87, 0xb,  0x8,  0x0,  0x36, 0x8d, 0x23, 0x2 ] };
//DEFINE_GUID(CLSID_IDataObjectViewer, 0x28d8aba0, 0x4b78, 0x11ce, 0xb2, 0x7d, 0x0,  0xaa, 0x0,  0x1f, 0x73, 0xc1);
//DEFINE_GUID(CLSID_IDispatchViewer,   0xd2af7a60, 0x4c42, 0x11ce, 0xb2, 0x7d, 0x00, 0xaa, 0x00, 0x1f, 0x73, 0xc1) ;

extern(Windows)
HRESULT LoadTypeLib(wchar* path, ITypeLib *pLib);

extern(Windows)
export BOOL SendMessageW(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

extern(Windows)
HWND FindWindowExA(HWND hwndParent, HWND hwndChildAfter, LPCSTR lpszClass, LPCSTR lpszWindow);

typedef
extern(Windows)
HRESULT fnDllGetClassObject(CLSID* rclsid, IID* riid, LPVOID* ppv);

string idltext;

extern(Windows)
HWND GetParent(HWND hWnd);

alias
extern(Windows)
BOOL fnEnumWindows(HWND hwnd, LPARAM lParam);

extern(Windows)
BOOL EnumWindows(fnEnumWindows* lpEnumFunc, LPARAM lParam);

extern(Windows)
BOOL EnumChildWindows(HWND hWndParent, WNDENUMPROC lpEnumFunc, LPARAM lParam);

const GA_ROOTOWNER = 3;

extern(Windows)
HWND GetAncestor(HWND hwnd, UINT gaFlags);

extern(Windows)
HWND GetWindow(HWND hWnd, UINT uCmd);

const GW_OWNER = 4;

extern(Windows)
int GetClassNameA(HWND hWnd, LPTSTR lpClassName, int nMaxCount);

extern(Windows)
BOOL CloseWindow(HWND hWnd);

extern(Windows)
BOOL PostMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);

HWND myWindow;
HWND foundWindow;

extern(Windows)
BOOL EnumWindowsProcIdl(HWND hwnd, LPARAM lParam)
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
BOOL EnumChild(HWND hwnd, LPARAM lParam)
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

HWND FindRichEdit(HWND root)
{
	HWND found;
	EnumChildWindows(root, &EnumChild, cast(LPARAM) &found);
	return found;
}

extern(Windows)
int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam) 
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
			idltext = toUTF8(buffer[0..$-1]);
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
	debug writefln("lib = %s", cast(void*)lib);
	
	HANDLE m = LoadLibraryA(ivdll.ptr);

	if(m)
	{
		debug writefln("m = %s", cast(void*)m);
		fnDllGetClassObject* fn = cast(fnDllGetClassObject*) 
			GetProcAddress(m, "DllGetClassObject".ptr);
		if(fn)
		{
			debug writefln("fn = %s", cast(void*)fn);
			IInterfaceViewer viewer;
			IClassFactory factory;
			rc = (*fn)(&CLSID_ITypeLibViewer, &IID_IClassFactory, cast(void**)&factory);
			debug writefln("factory = %s", cast(void*)factory);
			if(factory)
			{
				rc = factory.CreateInstance(null, &IID_IInterfaceViewer, cast(void**)&viewer);
				debug writefln("viewer = %s", cast(void*)viewer);

				HINSTANCE hInst = GetModuleHandleA(null);
				WNDCLASSA wc;
				wc.lpszClassName = "DummyWindow";
				wc.style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW;
				wc.lpfnWndProc = &WindowProc;
				wc.hInstance = hInst;
				wc.hIcon = null; //DefaultWindowIcon.peer;
				//wc.hIconSm = DefaultWindowSmallIcon.peer;
				wc.hCursor = LoadCursorA(cast(HINSTANCE) null, IDC_ARROW);
				wc.hbrBackground = null;
				wc.lpszMenuName = null;
				wc.cbClsExtra = 0;
				wc.cbWndExtra = 0;
				ATOM atom = RegisterClassA(&wc);
				assert(atom);

				HWND hwnd = CreateWindowA("DummyWindow".ptr, "".ptr, WS_OVERLAPPED,
							CW_USEDEFAULT, CW_USEDEFAULT, 10, 10,
							null, null, hInst, null);
						writefln("hwnd = %s", cast(void*)hwnd);

				myWindow = hwnd;
						viewer.View(hwnd, IID_ITypeLib, lib);

				std.file.write(outidl, idltext);
			}
		}
		
	}
	
}
