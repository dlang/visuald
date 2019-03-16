// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.vdextensions;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.win32.wtypes;

import sdk.vsi.textmgr;
import sdk.vsi.vsshell;

import stdext.com;

import visuald.hierutil;
import visuald.dpackage;
import visuald.config;

__gshared IVisualDHelper vdhelper;
__gshared IVisualCHelper vchelper;

interface IVisualDHelper : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9910-7e4ad4084715");

	int GetTextOptions(IVsTextView view, int* flags, int* tabsize, int* indentsize);
}

IVisualDHelper createDHelper()
{
	if (!vdhelper)
		vdhelper = VsLocalCreateInstance!IVisualDHelper (&g_VisualDHelperCLSID, CLSCTX_INPROC_SERVER);
	return vdhelper;
}

interface IVisualCHelper : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9911-7e4ad4084715");

	int GetDCompileOptions(IVsHierarchy proj, VSITEMID itemid, BSTR* impPath, BSTR* stringImpPath,
	                       BSTR* versionids, BSTR* debugids, ref uint flags);
	int GetDCommandLine(IVsHierarchy proj, uint itemid, BSTR* cmdline);
}

IVisualCHelper createCHelper()
{
	if (!vchelper)
		vchelper = VsLocalCreateInstance!IVisualCHelper (&g_VisualCHelperCLSID, CLSCTX_INPROC_SERVER);
	return vchelper;
}

int vdhelper_GetTextOptions(IVsTextView view, int* flags, int* tabsize, int* indentsize)
{
	try
	{
		if (!createDHelper())
			return S_FALSE;
		return vdhelper.GetTextOptions(view, flags, tabsize, indentsize);
	}
	catch(Throwable)
	{
		return E_FAIL;
	}
}

int vdhelper_GetDCompileOptions(IVsHierarchy proj, VSITEMID itemid, ProjectOptions opt)
{
	try
	{
		if (!createCHelper())
			return S_FALSE;

		BSTR versionids;
		BSTR debugids;
		BSTR impPath;
		BSTR stringImpPath;
		uint flags; // see ConfigureFlags!()

		int rc = vchelper.GetDCompileOptions(proj, itemid, &impPath, &stringImpPath, &versionids, &debugids, flags);
		if (rc != S_OK)
			return rc;

		opt.versionids = detachBSTR(versionids);
		opt.debugids = detachBSTR(debugids);
		opt.imppath = detachBSTR(impPath);
		opt.fileImppath = detachBSTR(stringImpPath);

		opt.useUnitTests   = (flags & 1) != 0;
		opt.release        = (flags & 2) == 0;
		opt.isX86_64       = (flags & 4) != 0;
		opt.cov            = (flags & 8) != 0;
		opt.doDocComments  = (flags & 16) != 0;
		opt.boundscheck    = (flags & 32) != 0 ? 3 : 0;
		opt.errDeprecated  = (flags & 128) != 0;
		opt.compiler       = (flags & 0x4_00_00_00) != 0 ? Compiler.LDC : (flags & 64) != 0 ? Compiler.GDC : Compiler.DMD;
		opt.versionlevel   = (flags >> 8)  & 0xff;
		opt.debuglevel     = (flags >> 16) & 0xff;
		opt.mscoff         = true;

		return S_OK;
	}
	catch(Throwable)
	{
		return E_FAIL;
	}
}

int vdhelper_GetDCommandLine(IVsHierarchy proj, VSITEMID itemid, out string cmd)
{
	try
	{
		if (!createCHelper())
			return S_FALSE;

		BSTR cmdline;
		int rc = vchelper.GetDCommandLine(proj, itemid, &cmdline);
		if (rc != S_OK)
			return rc;

		cmd = detachBSTR(cmdline);
		return S_OK;
	}
	catch(Throwable)
	{
		return E_FAIL;
	}
}
