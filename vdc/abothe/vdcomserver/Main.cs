
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;

using DParserCOMServer;

namespace vdcomserver
{
	/// 
	/// P/Invoke calls
	/// 
	internal class COM
	{
		[DllImport ("ole32.dll")]
		public static extern UInt32 CoRegisterClassObject (
			ref Guid rclsid, 
			[MarshalAs (UnmanagedType.Interface)]IClassFactory pUnkn, 
			int dwClsContext, 
			int flags, 
			out int lpdwRegister);
		[DllImport ("ole32.dll")]
		public static extern UInt32 CoRevokeClassObject (int dwRegister);
		[DllImport("ole32.dll")]
		public static extern UInt32 CoResumeClassObjects();

		public const int RPC_C_AUTHN_LEVEL_PKT_PRIVACY = 6; // Encrypted DCOM communication
		public const int RPC_C_IMP_LEVEL_IDENTIFY = 2;  // No impersonation really required
		public const int CLSCTX_LOCAL_SERVER = 4; 
		public const int REGCLS_MULTIPLEUSE = 1;
		public const int REGCLS_SUSPENDED = 4;
		public const int EOAC_DISABLE_AAA = 0x1000;  // Disable Activate-as-activator
		public const int EOAC_NO_CUSTOM_MARSHAL = 0x2000; // Disable custom marshalling
		public const int EOAC_SECURE_REFS = 0x2;   // Enable secure DCOM references
		public const int CLASS_E_NOAGGREGATION = unchecked((int)0x80040110);
		public const int S_OK = unchecked((int)0x0);
		public const int E_NOINTERFACE = unchecked((int)0x80004002);
		public const string guidIClassFactory = "00000001-0000-0000-C000-000000000046";
		public const string guidIUnknown = "00000000-0000-0000-C000-000000000046";
	}
		
	/// 
	/// IClassFactory declaration
	/// 
	[ComImport(), ComVisible(false), InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid(COM.guidIClassFactory)]
	internal interface IClassFactory
	{
		[PreserveSig]
		int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject);
		[PreserveSig]
		int LockServer(bool fLock);
	}

	[StructLayout(LayoutKind.Sequential)]
	internal struct POINT
	{
		public int X;
		public int Y;
	}
	[StructLayout(LayoutKind.Sequential)]
	internal struct MSG
	{
		public IntPtr hwnd;
		public UInt32 message;
		public IntPtr wParam;
		public IntPtr lParam;
		public UInt32 time;
		public POINT pt;
	}
	internal class User32
	{
		[DllImport("user32.dll")]
		public static extern sbyte GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin,
		                                      uint wMsgFilterMax);
		[DllImport("user32.dll")]
		public static extern void PostQuitMessage(int nExitCode);
		[DllImport("user32.dll")]
		public static extern bool TranslateMessage([In] ref MSG lpMsg);
		[DllImport("user32.dll")]
		public static extern IntPtr DispatchMessage([In] ref MSG lpmsg);
	}

	internal class IID
	{
		public const string VDServerClassFactory = "002a2de9-8bb6-484d-aa02-7e4ad4084715"; // debug: 9a02, release: 9902
	}

	[ComVisible(true), Guid(IID.VDServerClassFactory)]
	//[ClassInterface(ClassInterfaceType.None)]
	public class VDServerClassFactory : IClassFactory
	{
		static readonly Guid VDServerGUID = new Guid (DParserCOMServer.IID.IVDServer);
		static readonly Guid IUnknownGUID = new Guid(COM.guidIUnknown);

		public int CreateInstance(IntPtr UnkOuter, ref Guid riid, out IntPtr pvObject)
		{
			pvObject = IntPtr.Zero;
			//MessageBox.Show("CreateInstance", "[LOCAL] message");
			if(riid.Equals(VDServerGUID) || riid.Equals(IUnknownGUID))
			{
				//MessageBox.Show("CreateInstance IVDServer", "[LOCAL] message");
				VDServer srv = new VDServer();
				pvObject = Marshal.GetComInterfaceForObject(srv, typeof(IVDServer));
				return COM.S_OK;
			}
			return COM.E_NOINTERFACE;
		}

		public int LockServer(bool fLock)
		{
			if(fLock)
			{
				//MessageBox.Show("LockServer", "[LOCAL] message");
				lockCount++;
			}
			else
			{
				//MessageBox.Show("UnlockServer", "[LOCAL] message");
				lockCount--;
			}
			if(lockCount == 0)
				User32.PostQuitMessage(0);
			return COM.S_OK;
		}

		[EditorBrowsable(EditorBrowsableState.Never)]
		[ComRegisterFunction()]
		public static void Register(Type t)
		{/*
			try
			{
				VDServer.RegasmRegisterLocalServer(t);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
				throw ex; // Re-throw the exception
			}*/
		}
		[EditorBrowsable(EditorBrowsableState.Never)]
		[ComUnregisterFunction()]
		public static void Unregister(Type t)
		{/*
			try
			{
				VDServer.RegasmUnregisterLocalServer(t);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
				throw ex; // Re-throw the exception
			}*/
		}

		int lockCount;
	}

	class MainClass
	{
		public static void Main (string[] args)
		{
			// Create the MyCar class object.
			VDServerClassFactory cf = new VDServerClassFactory();

			int regID;
			Guid CLSID_MyObject = new Guid(DParserCOMServer.IID.VDServer);
			UInt32 hResult = COM.CoRegisterClassObject(ref CLSID_MyObject, cf, COM.CLSCTX_LOCAL_SERVER, 
			                                           COM.REGCLS_MULTIPLEUSE | COM.REGCLS_SUSPENDED, out regID);
			if (hResult != 0)
				throw new ApplicationException("CoRegisterClassObject failed" + hResult.ToString("X"));  

            hResult = COM.CoResumeClassObjects();
			if (hResult != 0)
				throw new ApplicationException("CoResumeClassObjects failed" + hResult.ToString("X"));  

			//MessageBox.Show("vdcomserver registered", "[LOCAL] message");
			
			// Now just run until a quit message is sent,
			// in responce to the final release.
			//Application.Run();

			MSG msg = new MSG();
			while(User32.GetMessage(out msg, IntPtr.Zero, 0, 0) != 0)
			{
				User32.TranslateMessage(ref msg);
				User32.DispatchMessage(ref msg);
			}

			// All done, so remove class object.
			COM.CoRevokeClassObject(regID);	
		}
	}
}

/*
using System;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.ServiceProcess;
using System.Threading;
using System.Runtime.InteropServices;

namespace Test
{
	// 
	// .NET class, interface exposed through DCOM
	//
	
	// exposed COM interface
	[GuidAttribute(MyService.guidIMyInterface), ComVisible(true)]
	public interface IMyInterface
	{
		string GetDateTime(string prefix); 
	}
	
	// exposed COM class
	[GuidAttribute(MyService.guidMyClass), ComVisible(true)]
	public class CMyClass: IMyInterface
	{
		// Print date & time and the current EXE name
		public string GetDateTime(string prefix) 
		{ 
			Process currentProcess = Process.GetCurrentProcess();
			return string.Format("{0}: {1} [server-side COM call executed on {2}]", 
			                     prefix, DateTime.Now, currentProcess.MainModule.ModuleName);
		} 
	}
	
	//
	// My hosting Windows service
	//
	internal class MyService : 
		ServiceBase
	{
		public MyService()
		{
			// Initialize COM security
			Thread.CurrentThread.ApartmentState = ApartmentState.STA;
			UInt32 hResult = ComAPI.CoInitializeSecurity(
				IntPtr.Zero, // Add here your Security descriptor
				-1,
				IntPtr.Zero,
				IntPtr.Zero,
				ComAPI.RPC_C_AUTHN_LEVEL_PKT_PRIVACY,
				ComAPI.RPC_C_IMP_LEVEL_IDENTIFY,
				IntPtr.Zero,
				ComAPI.EOAC_DISABLE_AAA 
				| ComAPI.EOAC_SECURE_REFS 
				| ComAPI.EOAC_NO_CUSTOM_MARSHAL,
				IntPtr.Zero);
			if (hResult != 0)
				throw new ApplicationException(
					"CoIntializeSecurity failed" + hResult.ToString("X"));
		}
		
		// The main entry point for the process
		static void Main()
		{
			ServiceBase.Run(new ServiceBase[] { new MyService() });
		}
		/// 
		/// On start, register the COM class factory
		/// 
		protected override void OnStart(string[] args)
		{
			Guid CLSID_MyObject = new Guid(MyService.guidMyClass);
			UInt32 hResult = ComAPI.CoRegisterClassObject(
				ref CLSID_MyObject, 
				new MyClassFactory(), 
				ComAPI.CLSCTX_LOCAL_SERVER, 
				ComAPI.REGCLS_MULTIPLEUSE, 
				out _cookie);
			if (hResult != 0)
				throw new ApplicationException(
					"CoRegisterClassObject failed" + hResult.ToString("X"));  
		}
		/// 
		/// On stop, remove the COM class factory registration
		/// 
		protected override void OnStop()
		{
			if (_cookie != 0)
				ComAPI.CoRevokeClassObject(_cookie);
		}
		private int _cookie = 0;
		
		//
		// Public constants
		//
		public const string serviceName = "MyService";
		public const string guidIMyInterface = "e88d15a5-0510-4115-9aee-a8421c96decb";
		public const string guidMyClass = "f681abd0-41de-46c8-9ed3-d0f4eba19891";
	}
	
	//
	// Standard installer 
	//
	[RunInstaller(true)]
	public class MyServiceInstaller : 
		System.Configuration.Install.Installer
	{
		public MyServiceInstaller()
		{
			processInstaller = new ServiceProcessInstaller();
			serviceInstaller = new ServiceInstaller();
			// Add a new service running under Local SYSTEM
			processInstaller.Account = ServiceAccount.LocalSystem;
			serviceInstaller.StartType = ServiceStartMode.Manual;
			serviceInstaller.ServiceName = MyService.serviceName;
			Installers.Add(serviceInstaller);
			Installers.Add(processInstaller);
		}
		private ServiceInstaller serviceInstaller;
		private ServiceProcessInstaller processInstaller;
	}
	
	//
	// Internal COM Stuff
	//
	
	/// 
	/// P/Invoke calls
	/// 
	internal class ComAPI
	{
		[DllImport("OLE32.DLL")]
		public static extern UInt32 CoInitializeSecurity(
			IntPtr securityDescriptor, 
			Int32 cAuth,
			IntPtr asAuthSvc,
			IntPtr reserved,
			UInt32 AuthLevel,
			UInt32 ImpLevel,
			IntPtr pAuthList,
			UInt32 Capabilities,
			IntPtr reserved3
			);
		[DllImport ("ole32.dll")]
		public static extern UInt32 CoRegisterClassObject (
			ref Guid rclsid, 
			[MarshalAs (UnmanagedType.Interface)]IClassFactory pUnkn, 
			int dwClsContext, 
			int flags, 
			out int lpdwRegister);
		[DllImport ("ole32.dll")]
		public static extern UInt32 CoRevokeClassObject (int dwRegister);
		public const int RPC_C_AUTHN_LEVEL_PKT_PRIVACY = 6; // Encrypted DCOM communication
		public const int RPC_C_IMP_LEVEL_IDENTIFY = 2;  // No impersonation really required
		public const int CLSCTX_LOCAL_SERVER = 4; 
		public const int REGCLS_MULTIPLEUSE = 1;
		public const int EOAC_DISABLE_AAA = 0x1000;  // Disable Activate-as-activator
		public const int EOAC_NO_CUSTOM_MARSHAL = 0x2000; // Disable custom marshalling
		public const int EOAC_SECURE_REFS = 0x2;   // Enable secure DCOM references
		public const int CLASS_E_NOAGGREGATION = unchecked((int)0x80040110);
		public const int E_NOINTERFACE = unchecked((int)0x80004002);
		public const string guidIClassFactory = "00000001-0000-0000-C000-000000000046";
		public const string guidIUnknown = "00000000-0000-0000-C000-000000000046";
	}
	
	/// 
	/// IClassFactory declaration
	/// 
	[ComImport (), InterfaceType (ComInterfaceType.InterfaceIsIUnknown), 
	 Guid (ComAPI.guidIClassFactory)]
	internal interface IClassFactory
	{
		[PreserveSig]
		int CreateInstance (IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject);
		[PreserveSig]
		int LockServer (bool fLock);
	}
	
	/// 
	/// My Class factory implementation
	/// 
	internal class MyClassFactory : IClassFactory
	{
		public int CreateInstance (IntPtr pUnkOuter, 
		                           ref Guid riid, 
		                           out IntPtr ppvObject)
		{
			ppvObject = IntPtr.Zero;
			if (pUnkOuter != IntPtr.Zero)
				Marshal.ThrowExceptionForHR (ComAPI.CLASS_E_NOAGGREGATION);
			if (riid == new Guid(MyService.guidIMyInterface) 
			    || riid == new Guid(ComAPI.guidIUnknown))
			{
				//
				// Create the instance of my .NET object
				//
				ppvObject = Marshal.GetComInterfaceForObject(
					new CMyClass(), typeof(IMyInterface));
			}
			else
				Marshal.ThrowExceptionForHR (ComAPI.E_NOINTERFACE);
			return 0;
		}
		public int LockServer (bool lockIt)
		{
			return 0;
		} 
	}
}
*/