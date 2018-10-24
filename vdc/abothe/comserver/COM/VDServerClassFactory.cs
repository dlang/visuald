/****************************** Module Header ******************************\
Module Name:  ExeCOMServer.cs
Project:      CSExeCOMServer
Copyright (c) Microsoft Corporation.

ExeCOMServer encapsulates the skeleton of an out-of-process COM server in  
C#. The class implements the singleton design pattern and it's thread-safe. 
To start the server, call CSExeCOMServer.Instance.Run(). If the server is 
running, the function returns directly. Inside the Run method, it registers 
the class factories for the COM classes to be exposed from the COM server, 
and starts the message loop to wait for the drop of lock count to zero. 
When lock count equals zero, it revokes the registrations and quits the 
server.

The lock count of the server is incremented when a COM object is created, 
and it's decremented when the object is released (GC-ed). In order that the 
COM objects can be GC-ed in time, ExeCOMServer triggers GC every 5 seconds 
by running a Timer after the server is started.

This source is subject to the Microsoft Public License.
See http://www.microsoft.com/en-us/openness/licenses.aspx#MPL.
All other rights reserved.

THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
\***************************************************************************/

#region Using directives

using System;
using System.Runtime.InteropServices;

#endregion


namespace DParserCOMServer.COM
{
	[Guid("002a2de9-8bb6-484d-aa02-7e4ad4084715"), ComVisible(true)]
	public class VDServerClassFactory : IClassFactory
	{
		public int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject)
		{
			ppvObject = IntPtr.Zero;
			
			if (pUnkOuter != IntPtr.Zero)
			{
				// The pUnkOuter parameter was non-NULL and the object does 
				// not support aggregation.
				Marshal.ThrowExceptionForHR(COMNative.CLASS_E_NOAGGREGATION);
			}
			
			if (riid == new Guid(IID.IVDServer) ||
			    riid == new Guid(COMNative.IID_IDispatch) ||
			    riid == new Guid(COMNative.IID_IUnknown))
			{
				// Create the instance of the .NET object
				ppvObject = Marshal.GetComInterfaceForObject(new VDServer(), typeof(IVDServer));
			}
			else
			{
				// The object that ppvObject points to does not support the 
				// interface identified by riid.
				Marshal.ThrowExceptionForHR(COMNative.E_NOINTERFACE);
			}
			return 0;   // S_OK
		}
		
		public int LockServer(bool fLock)
		{
			if(fLock)
				ExeCOMServer.Instance.Lock();
			else
				ExeCOMServer.Instance.Unlock();
			return 0;   // S_OK
		}
	}
}