// compile with
// m:\s\d\rainers\windows\bin\dmd.exe -g testvd.d -I..\.. oleaut32.lib ole32.lib 

module testvd;

import std.stdio;
import std.conv;

import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.port.base;

import vdc.ivdserver;

static GUID IVDServer_iid = uuid("002a2de9-8bb6-484d-9901-7e4ad4084715");
static GUID VDServer_iid = uuid("002a2de9-8bb6-484d-AA05-7e4ad4084715");
static GUID IID_IUnknown = uuid("00000000-0000-0000-C000-000000000046");
static GUID IID_IClassFactory = { 0x00000001,0x0000,0x0000,[ 0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46 ] };

// issues:
// C# registration with REGASM only adds the class to the 64-bit registry, not wow6432node
int main()
{
	CoInitialize(null);

	IVDServer gVDServer;

	IUnknown pUnknown;
	HRESULT hr = CoGetClassObject(VDServer_iid, CLSCTX_INPROC_SERVER, null, IID_IUnknown, cast(void**)&pUnknown);
	if(FAILED(hr))
		return -1;
//	hr = OleRun(pUnknown);
//	if(FAILED(hr))
//		return -3;
	IClassFactory factory;
	hr = pUnknown.QueryInterface(&IID_IClassFactory, cast(void**)&factory);
	pUnknown.Release();
	if(FAILED(hr))
		return -5;

	hr = factory.CreateInstance(null, &IVDServer_iid, cast(void**)&gVDServer);
	if(FAILED(hr))
		return -5;

	BSTR fname = SysAllocString("filename");
	BSTR source = SysAllocString("void main() { int abc; }");
	hr = gVDServer.UpdateModule(fname, source, false);

	version(all)
	{{
		int iStartLine = 1;
		int iStartIndex = 6;
		int iEndLine = 1;
		int iEndIndex = 6;
		hr = gVDServer.GetTip(fname, iStartLine, iStartIndex, iEndLine, iEndIndex);

		BSTR btype;
		hr = gVDServer.GetTipResult(iStartLine, iStartIndex, iEndLine, iEndIndex, &btype);
		writeln("Tip: ", to!wstring(btype));
	}}

	version(all)
	{{
		int iStartLine = 1;
		int iStartIndex = 6;
		BSTR tok = SysAllocString("m");
		BSTR expr = SysAllocString("");
		hr = gVDServer.GetSemanticExpansions(fname, tok, iStartLine, iStartIndex, expr);

		BSTR expansions;
		hr = gVDServer.GetSemanticExpansionsResult(&expansions);
		writeln("Expansion: ", to!wstring(expansions));
	}}

	BSTR msg;
	hr = gVDServer.GetLastMessage(&msg);
	if(FAILED(hr))
		return -6;
	factory.Release();
	gVDServer.Release();
	return 0;
}
