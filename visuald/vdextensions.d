module visuald.vdextensions;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import sdk.vsi.textmgr;
import sdk.vsi.vsshell;

__gshared IVisualDHelper vdhelper;

interface IVisualDHelper : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9910-7e4ad4084715");

	int GetTextOptions(IVsTextView view, int* flags, int* tabsize, int* indentsize);
}

export extern(Windows) int RegisterHelper(IVisualDHelper helper)
{
	vdhelper = helper;
	return S_OK;
}

export extern(Windows) int UnregisterHelper(IVisualDHelper helper)
{
	if(vdhelper is helper)
		vdhelper = null;
	return S_OK;
}
