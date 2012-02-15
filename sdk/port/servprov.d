module sdk.port.servprov;

import sdk.port.base;
import sdk.win32.unknwn;
//import std.c.windows.windows;
//import std.c.windows.com;

const GUID IID_IServiceProvider = IServiceProvider.iid;

interface IServiceProvider : IUnknown
{
	static const GUID iid = { 0x6d5140c1, 0x7436, 0x11ce, [ 0x80, 0x34, 0x00, 0xaa, 0x00, 0x60, 0x09, 0xfa ] };
public:
	/* [local] */ HRESULT QueryService( 
		/* [in] */ in GUID* guidService,
		/* [in] */ in IID* riid,
		/* [out] */ void **ppvObject);
}
