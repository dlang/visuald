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
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;
using System.Threading;
#endregion


namespace DParserCOMServer
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
	
	sealed internal class ExeCOMServer
    {
        #region Singleton Pattern

        private ExeCOMServer()
        {
        }

        private static ExeCOMServer _instance = new ExeCOMServer();
        public static ExeCOMServer Instance
        {
            get { return _instance; }
        }

        #endregion


        private object syncRoot = new Object(); // For thread-sync in lock
        private bool _bRunning = false; // Whether the server is running

        // The ID of the thread that runs the message loop
        private uint _nMainThreadID = 0;

        // The lock count (the number of active COM objects) in the server
        private int _nLockCnt = 0;
        
        // The timer to trigger GC every 5 seconds
        private Timer _gcTimer;

        private static uint _lastActivity;

        /// <summary>
        /// The method is call every 5 seconds to GC the managed heap after 
        /// the COM server is started.
        /// </summary>
        /// <param name="stateInfo"></param>
        private static void GarbageCollect(object stateInfo)
        {
            uint activity = VDServer.Activity;
            if (activity != _lastActivity)
            {
                _lastActivity = activity;
                GC.Collect();   // GC
            }
        }

        private uint _cookie;

        /// <summary>
        /// PreMessageLoop is responsible for registering the COM class 
        /// factories for the COM classes to be exposed from the server, and 
        /// initializing the key member variables of the COM server (e.g. 
        /// _nMainThreadID and _nLockCnt).
        /// </summary>
        private void PreMessageLoop()
        {
            //
            // Register the COM class factories.
            // 

            //Guid clsidSimpleObj = new Guid(SimpleObject.ClassId);
            Guid clsid = new Guid(IID.VDServer);

            // Register the SimpleObject class object
            int hResult = COMNative.CoRegisterClassObject(ref clsid, new VDServerClassFactory(),
                                                          CLSCTX.LOCAL_SERVER, REGCLS.MULTIPLEUSE | REGCLS.SUSPENDED,
                                                          out _cookie);
            if (hResult != 0)
            {
                throw new ApplicationException("CoRegisterClassObject failed w/err 0x" + hResult.ToString("X"));
            }

            // Inform the SCM about all the registered classes, and begins 
            // letting activation requests into the server process.
            hResult = COMNative.CoResumeClassObjects();
            if (hResult != 0)
            {
                // Revoke the registration of SimpleObject on failure
                if (_cookie != 0)
                {
                    COMNative.CoRevokeClassObject(_cookie);
                }

                // Revoke the registration of other classes
                // ...

                throw new ApplicationException("CoResumeClassObjects failed w/err 0x" + hResult.ToString("X"));
            }

            // Records the ID of the thread that runs the COM server so that 
            // the server knows where to post the WM_QUIT message to exit the 
            // message loop.
            _nMainThreadID = NativeMethod.GetCurrentThreadId();

            // Records the count of the active COM objects in the server. 
            // When _nLockCnt drops to zero, the server can be shut down.
            _nLockCnt = 0;

            // Start the GC timer to trigger GC every 5 seconds.
            _gcTimer = new Timer(new TimerCallback(GarbageCollect), null, 5000, 5000);
        }

        /// <summary>
        /// RunMessageLoop runs the standard message loop. The message loop 
        /// quits when it receives the WM_QUIT message.
        /// </summary>
        private void RunMessageLoop()
        {
            MSG msg;
            while (NativeMethod.GetMessage(out msg, IntPtr.Zero, 0, 0))
            {
                NativeMethod.TranslateMessage(ref msg);
                NativeMethod.DispatchMessage(ref msg);
            }
        }

        /// <summary>
        /// PostMessageLoop is called to revoke the registration of the COM 
        /// classes exposed from the server, and perform the cleanups.
        /// </summary>
        private void PostMessageLoop()
        {
			// Revoke the registration of  COM classes
            if (_cookie != 0)
            {
                COMNative.CoRevokeClassObject(_cookie);
            }

            // Dispose the GC timer.
            if (_gcTimer != null)
            {
                _gcTimer.Dispose();
            }

            // Wait for any threads to finish.
            Thread.Sleep(1000);
        }

        /// <summary>
        /// Run the COM server. If the server is running, the function 
        /// returns directly.
        /// </summary>
        /// <remarks>The method is thread-safe.</remarks>
        public void Run()
        {
            lock (syncRoot) // Ensure thread-safe
            {
                // If the server is running, return directly.
                if (_bRunning)
                    return;

                // Indicate that the server is running now.
                _bRunning = true;
            }

            try
            {
                // Call PreMessageLoop to initialize the member variables 
                // and register the class factories.
                PreMessageLoop();

                try
                {
                    // Run the message loop.
                    RunMessageLoop();
                }
                finally
                {
                    // Call PostMessageLoop to revoke the registration.
                    PostMessageLoop();
                }
            }
            finally
            {
                _bRunning = false;
            }
        }

        /// <summary>
        /// Increase the lock count
        /// </summary>
        /// <returns>The new lock count after the increment</returns>
        /// <remarks>The method is thread-safe.</remarks>
        public int Lock()
        {
            return Interlocked.Increment(ref _nLockCnt);
        }

        /// <summary>
        /// Decrease the lock count. When the lock count drops to zero, post 
        /// the WM_QUIT message to the message loop in the main thread to 
        /// shut down the COM server.
        /// </summary>
        /// <returns>The new lock count after the increment</returns>
        public int Unlock()
        {
            int nRet = Interlocked.Decrement(ref _nLockCnt);

            // If lock drops to zero, attempt to terminate the server.
            if (nRet == 0)
            {
                // Post the WM_QUIT message to the main thread
                NativeMethod.PostThreadMessage(_nMainThreadID, NativeMethod.WM_QUIT, UIntPtr.Zero, IntPtr.Zero); 
            }

            return nRet;
        }

        /// <summary>
        /// Get the current lock count.
        /// </summary>
        /// <returns></returns>
        public int GetLockCount()
        {
            return _nLockCnt;
        }
    }

	class Program
	{
		/// <summary>
		/// The main entry point for the application.
		/// </summary>
		static void Main(string[] args)
		{
			// Run the out-of-process COM server
			ExeCOMServer.Instance.Run();
		}
	}
}