namespace DParserCOMServer.COM
{
	static class Program
	{
		/// <summary>
		/// The main entry point for the application.
		/// </summary>
		static void Main(string[] args)
		{
			SetErrorMode(3); //don't show JitDebugger on crash
			
			// Run the out-of-process COM server
			ExeCOMServer.Instance.Run();
		}

		[DllImport("Kernel32.dll")]
		public static extern uint SetErrorMode(uint mode);
	}
}