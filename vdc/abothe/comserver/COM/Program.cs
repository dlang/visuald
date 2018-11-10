namespace DParserCOMServer.COM
{
	static class Program
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