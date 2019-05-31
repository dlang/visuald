//
// To be used by Visual D, set registry entry
// HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0D\ToolsOptionsPages\Projects\Visual D Settings\VDServerIID
// to "{002a2de9-8bb6-484d-AA05-7e4ad4084715}"

using System.Runtime.InteropServices;

namespace DParserCOMServer
{
	public static class IID
	{
		public const string IVDServer = "002a2de9-8bb6-484d-9901-7e4ad4084715";
		public const string VDServer = "002a2de9-8bb6-484d-AA05-7e4ad4084715";
		//public const string VDServer = "002a2de9-8bb6-484d-AB05-7e4ad4084715"; // debug
	}

	[ComVisible (true), Guid (IID.IVDServer)]
	[InterfaceType (ComInterfaceType.InterfaceIsIUnknown)]
	public interface IVDServer
	{
		void ConfigureSemanticProject (string filename, string imp, string stringImp, string versionids, string debugids, uint flags);
		void ClearSemanticProject ();
		void UpdateModule (string filename, string srcText, int flags);
		void GetTip (string filename, int startLine, int startIndex, int endLine, int endIndex, int flags);
		void GetTipResult (out int startLine, out int startIndex, out int endLine, out int endIndex, out string answer);
		void GetSemanticExpansions (string filename, string tok, uint line, uint idx, string expr);
		void GetSemanticExpansionsResult (out string stringList);
		void IsBinaryOperator (string filename, uint startLine, uint startIndex, uint endLine, uint endIndex, out bool pIsOp);
		void GetParseErrors (string filename, out string errors);
		void GetBinaryIsInLocations (string filename, out object locs); // array of pairs of DWORD
		void GetLastMessage (out string message);
		void GetIdentifierTypes(string filename, int startLine, int endLine, int flags);
		void GetIdentifierTypesResult(out string types);
		void GetDefinition (string filename, int startLine, int startIndex, int endLine, int endIndex);
		void GetDefinitionResult (out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename);
		void GetReferences (string filename, string tok, uint line, uint idx, string expr, bool moduleOnly);
		void GetReferencesResult (out string stringList);
		void ConfigureCommentTasks (string tasks);
		void GetCommentTasks (string filename, out string tasks);
	}
}


