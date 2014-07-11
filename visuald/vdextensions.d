module visuald.vdextensions;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import sdk.vsi.textmgr;
import sdk.vsi.vsshell;

import visuald.hierutil;
import visuald.dpackage;

__gshared IVisualDHelper vdhelper;

interface IVisualDHelper : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9910-7e4ad4084715");

	int GetTextOptions(IVsTextView view, int* flags, int* tabsize, int* indentsize);
}

IVisualDHelper createHelper()
{
	if (!vdhelper)
		vdhelper = VsLocalCreateInstance!IVisualDHelper (&g_VisualDHelperCLSID, sdk.win32.wtypes.CLSCTX_INPROC_SERVER);
	return vdhelper;
}

int vdhelper_GetTextOptions(IVsTextView view, int* flags, int* tabsize, int* indentsize)
{
	if (!createHelper())
		return S_FALSE;
	return vdhelper.GetTextOptions(view, flags, tabsize, indentsize);
}
