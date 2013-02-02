//
// To be used by Visual D, set registry entry
// HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0D\ToolsOptionsPages\Projects\Visual D Settings\VDServerIID
// to "{002a2de9-8bb6-484d-AA05-7e4ad4084715}"

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.IO;

using D_Parser.Parser;
using D_Parser.Misc;
using D_Parser.Dom;
using D_Parser.Completion;
using D_Parser.Resolver;

namespace ABothe
{
	[ComVisible(true), Guid("002a2de9-8bb6-484d-9901-7e4ad4084715")]
	[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	public interface IVDServer
	{
		void ConfigureSemanticProject(string filename, string imp, string stringImp, string versionids, string debugids, uint flags);
		void ClearSemanticProject();
		void UpdateModule(string filename, string srcText, bool verbose);
		void GetTip(string filename, int startLine, int startIndex, int endLine, int endIndex);
		void GetTipResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string answer);
		void GetSemanticExpansions(string filename, string tok, uint line, uint idx, string expr);
		void GetSemanticExpansionsResult(out string stringList);
		void IsBinaryOperator(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex, out bool pIsOp);
		void GetParseErrors(string filename, out string errors);
		void GetBinaryIsInLocations(string filename, out uint[] locs); // array of pairs of DWORD
		void GetLastMessage(out string message);
		void GetDefinition(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex);
		void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename);
	}

	class VDServerCompletionDataGenerator : ICompletionDataGenerator
	{
		public VDServerCompletionDataGenerator (string pre)
		{
			prefix = pre;
		}

		/// <summary>
		/// Adds a token entry
		/// </summary>
		public void Add(byte Token)
		{
			addExpansion(DTokens.Keywords[Token]);
		}

		/// <summary>
		/// Adds a property attribute
		/// </summary>
		public void AddPropertyAttribute(string AttributeText)
		{
			addExpansion(AttributeText);
		}

		public void AddTextItem(string Text, string Description)
		{
			addExpansion(Text);
		}

		/// <summary>
		/// Adds a node to the completion data
		/// </summary>
		/// <param name="Node"></param>
		public void Add(INode Node)
		{
			addExpansion(Node.Name);
		}

		/// <summary>
		/// Adds a module (name stub) to the completion data
		/// </summary>
		/// <param name="ModuleName"></param>
		/// <param name="AssocModule"></param>
		public void Add(string ModuleName, IAbstractSyntaxTree Module = null, string PathOverride = null)
		{
			addExpansion(ModuleName);
		}

		public void AddModule(IAbstractSyntaxTree module, string nameOverride = null)
		{
			if(string.IsNullOrEmpty(nameOverride))
				addExpansion(module.Name);
			else
				addExpansion(nameOverride);
		}

		public void AddPackage(string packageName)
		{
			addExpansion(packageName);
		}

		void addExpansion(string name)
		{
			if(!string.IsNullOrEmpty(name))
				if(name.StartsWith(prefix))
					expansions += name + "\n";
		}

		public string expansions;
		public string prefix;
	}

	[ComVisible(true), Guid("002a2de9-8bb6-484d-AA05-7e4ad4084715")]
	[ClassInterface(ClassInterfaceType.None)]
	public class VDServer : IVDServer
	{
		private ParseCacheList _parseCacheList;
		private ParseCache     _parseCache;
		private CodeLocation   _tipStart, _tipEnd;
		private string _tipText;
		private string _expansions;
		private string _imports;
		private string _stringImports;
		private string _versionIds;
		private string _debugIds;
		private uint   _flags;
		EditorData _editorData = new EditorData();

		public Dictionary<string, IAbstractSyntaxTree> _modules = new Dictionary<string, IAbstractSyntaxTree>();
		public Dictionary<string, string> _sources = new Dictionary<string, string>();

		public VDServer()
		{
			_parseCacheList = new ParseCacheList();
			_parseCache = new ParseCache();
			_parseCacheList.Add(_parseCache);

			// MessageBox.Show("VDServer()");
		}

		public void ConfigureSemanticProject(string filename, string imp, string stringImp, string versionids, string debugids, uint flags)
		{
			if (_imports != imp) 
			{
				var impDirs = imp.Split('\n');
				if(_parseCache.UpdateRequired(impDirs))
					_parseCache.BeginParse(impDirs, "");
			}
			_imports = imp;
			_stringImports = stringImp;
			_versionIds = versionids;
			_debugIds = debugids;
			_flags = flags;
			_setupEditorData();
			//MessageBox.Show("ConfigureSemanticProject()");
			//throw new NotImplementedException();
		}
		public void ClearSemanticProject()
		{
			MessageBox.Show("ClearSemanticProject()");
			//throw new NotImplementedException();
		}
		public void UpdateModule(string filename, string srcText, bool verbose)
		{
			IAbstractSyntaxTree ast;
			try
			{
				ast = DParser.ParseString(srcText, false);
			}
			catch(Exception ex)
			{
				ast = new DModule{ ParseErrors = new System.Collections.ObjectModel.ReadOnlyCollection<ParserError>(
						new List<ParserError>{
						new ParserError(false, ex.Message + "\n\n" + ex.StackTrace, DTokens.Invariant, CodeLocation.Empty)
					}) }; //WTF
			}
			if(string.IsNullOrEmpty(ast.ModuleName))
				ast.ModuleName = Path.GetFileNameWithoutExtension(filename);
			ast.FileName = filename;

			IAbstractSyntaxTree oldast = null;
			if (_modules.TryGetValue(filename, out oldast))
			{
				_parseCache.UfcsCache.RemoveModuleItems(oldast); 
				_parseCache.Remove(oldast);
			}
			_parseCache.AddOrUpdate(ast);
			ConditionalCompilationFlags cflags = new ConditionalCompilationFlags(_editorData);
			_parseCache.UfcsCache.CacheModuleMethods(ast, ResolutionContext.Create(_parseCacheList, cflags, null, null)); 

			_modules[filename] = ast;
			_sources[filename] = srcText;
			//MessageBox.Show("UpdateModule(" + filename + ")");
			//throw new NotImplementedException();
		}

		static int getCodeOffset(string s, CodeLocation loc)
		{
			// column/line 1-based
			int off = 0;
			for (int ln = 1; ln < loc.Line; ln++)
				off = s.IndexOf('\n', off) + 1;
			return off + loc.Column - 1;
		}
		static bool isIdentifierCharacter(Char ch)
		{
			return Char.IsLetterOrDigit(ch) || ch == '_';
		}

		public void GetTip(string filename, int startLine, int startIndex, int endLine, int endIndex)
		{
			IAbstractSyntaxTree ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(startIndex + 2, startLine);
			_tipText = "";

			_editorData.CaretLocation = _tipStart;
			_editorData.SyntaxTree = ast as DModule;
			_editorData.ModuleCode = _sources[filename];
			// codeOffset+1 because otherwise it does not work on the first character
			_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, _tipStart) + 1;
			AbstractTooltipContent[] content = AbstractTooltipProvider.BuildToolTip(_editorData);
			if(content == null || content.Length == 0)
				_tipText = "";
			else
				foreach (var c in content)
				   _tipText += c.Title + ":" + c.Description + "\n";

			//MessageBox.Show("GetTip()");
			//throw new NotImplementedException();
		}
		public void GetTipResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string answer)
		{
			startLine = _tipStart.Line;
			startIndex = _tipStart.Column - 1;
			endLine = _tipEnd.Line;
			endIndex = _tipEnd.Column - 1;
			answer = _tipText;
			//MessageBox.Show("GetTipResult()");
			//throw new NotImplementedException();
		}
		public void GetSemanticExpansions(string filename, string tok, uint line, uint idx, string expr)
		{
			IAbstractSyntaxTree ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			CodeLocation loc = new CodeLocation((int)idx + 1, (int) line);
			
			_editorData.CaretLocation = loc;
			_editorData.SyntaxTree = ast as DModule;
			_editorData.ModuleCode = _sources[filename];
			_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, loc);
			// step back to beginning of identifier
			while(_editorData.CaretOffset > 0 && isIdentifierCharacter(_editorData.ModuleCode[_editorData.CaretOffset-1]))
				  _editorData.CaretOffset--;

			VDServerCompletionDataGenerator cdgen = new VDServerCompletionDataGenerator(tok);
			AbstractCompletionProvider provider = AbstractCompletionProvider.BuildCompletionData(cdgen, _editorData, null); //tok

			_expansions = cdgen.expansions;
		}
		public void GetSemanticExpansionsResult(out string stringList)
		{
			stringList = _expansions;
			//MessageBox.Show("GetSemanticExpansionsResult()");
			//throw new NotImplementedException();
		}
		public void IsBinaryOperator(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex, out bool pIsOp)
		{
			IAbstractSyntaxTree ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			MessageBox.Show("IsBinaryOperator()");
			throw new NotImplementedException();
		}
		public void GetParseErrors(string filename, out string errors)
		{
			IAbstractSyntaxTree ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			var asterrors = ast.ParseErrors;
			
			string errs = "";
			int cnt = asterrors.Count();
			for (int i = 0; i < cnt; i++)
			{
				var err = asterrors[i];
				errs += String.Format("{0},{1},{2},{3}:{4}\n", err.Location.Line, err.Location.Column - 1, err.Location.Line, err.Location.Column, err.Message);
			}
			errors = errs;
			//MessageBox.Show("GetParseErrors()");
			//throw new COMException("No Message", 1);
		}
		public void GetBinaryIsInLocations(string filename, out uint[] locs) // array of pairs of DWORD
		{
			//MessageBox.Show("GetBinaryIsInLocations()");
			locs = null;
			//throw new COMException("No Message", 1);
		}
		public void GetLastMessage(out string message)
		{
			//MessageBox.Show("GetLastMessage()");
			message = "__no_message__"; // avoid throwing exception
			//throw new COMException("No Message", 1);
		}
		public void GetDefinition(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex)
		{
		}

		public void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename)
		{
			startLine = _tipStart.Line;
			startIndex = _tipStart.Column - 1;
			endLine = _tipEnd.Line;
			endIndex = _tipEnd.Column - 1;
			filename = "";
		}

		///////////////////////////////////
		void _setupEditorData()
		{
			string versions = _versionIds;
			versions += "Windows\n" + "LittleEndian\n";
			if ((_flags & 1) != 0)
				versions += "unittest\n";
			if ((_flags & 3) != 0)
				versions += "assert\n";
			if ((_flags & 4) != 0)
				versions += "Win64\n" + "X86_64\n" + "D_InlineAsm_X86_64\n" + "D_LP64\n";
			else
				versions += "Win32\n" + "X86\n" + "D_InlineAsm_X86\n";
			if ((_flags & 8) != 0)
				versions += "D_Coverage\n";
			if ((_flags & 16) != 0)
				versions += "D_Ddoc\n";
			if ((_flags & 32) != 0)
				versions += "D_NoBoundsChecks\n";
			if ((_flags & 64) != 0)
				versions += "GNU\n";
			else
				versions += "DigitalMars\n";
				
			_editorData.ParseCache = _parseCacheList;
			_editorData.IsDebug = (_flags & 2) != 0;
			_editorData.DebugLevel = (int)(_flags >> 16) & 0xff;
			_editorData.VersionNumber = (int)(_flags >> 8) & 0xff;
			_editorData.GlobalVersionIds = versions.Split('\n');
			_editorData.GlobalDebugIds = _debugIds.Split('\n');
			_editorData.Options = new CompletionOptions { ShowUFCSItems = true };
		}
	}
}
