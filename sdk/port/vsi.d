module sdk.port.vsi;

public import sdk.port.base;
public import sdk.win32.unknwn;

// VSI specifics
@property IUnknown DOCDATAEXISTING_UNKNOWN() 
{
	IUnknown unk;
	*cast(size_t*)&unk = -1;
	return unk;
}

//shared static this() { *cast(int*)&DOCDATAEXISTING_UNKNOWN = -1; }

const GUID GUID_COMPlusNativeEng = { 0x92EF0900, 0x2251, 0x11D2, [ 0xB7, 0x2E, 0x00, 0x00, 0xF8, 0x75, 0x72, 0xEF ] };
const GUID GUID_COMPlusOnlyEnd = uuid("{449EC4CC-30D2-4032-9256-EE18EB41B62B}");
const GUID GUID_NativeOnlyEng = uuid("{3B476D35-A401-11D2-AAD4-00C04F990171}");

interface IVsDebuggerDeployConnection  : IUnknown
{
	// only forward referenced in VS2015 SDK
};
