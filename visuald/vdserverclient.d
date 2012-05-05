// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.vdserverclient;

import vdc.ivdserver;

import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import sdk.port.base;

import stdext.com;

version = VDServer;

static GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");

__gshared IClassFactory gVDClassFactory;
__gshared IVDServer gVDServer;

bool startVDServer()
{
	version(VDServer)
	{
		if(gVDServer)
			return false;

		GUID factory_iid = IID_IClassFactory;
		HRESULT hr = CoGetClassObject(VDServerClassFactory_iid, CLSCTX_LOCAL_SERVER, null, factory_iid, cast(void**)&gVDClassFactory);
		if(FAILED(hr))
			return false;

		hr = gVDClassFactory.CreateInstance(null, &IVDServer.iid, cast(void**)&gVDServer);
		if (FAILED(hr))
		{
			gVDClassFactory = release(gVDClassFactory);
			return false;
		}
	}
	return true;
}

bool stopVDServer()
{
	version(VDServer)
	{
		if(!gVDServer)
			return false;

		gVDServer = release(gVDServer);
		gVDClassFactory = release(gVDClassFactory);
	}
	return true;
}

