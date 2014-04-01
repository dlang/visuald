﻿﻿//
// To be used by Visual D, set registry entry
// HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0D\ToolsOptionsPages\Projects\Visual D Settings\VDServerIID
// to "{002a2de9-8bb6-484d-AA05-7e4ad4084715}"

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.IO;
using Microsoft.Win32;
using System.Reflection;

using D_Parser.Parser;
using D_Parser.Misc;
using D_Parser.Dom;
using D_Parser.Completion;
using D_Parser.Resolver;
using D_Parser.Resolver.TypeResolution;
using D_Parser.Completion.ToolTips;

namespace DParserCOMServer
{
	class IID
	{
		public const string IVDServer = "002a2de9-8bb6-484d-9901-7e4ad4084715";
		public const string VDServer = "002a2de9-8bb6-484d-AA05-7e4ad4084715";
	}

	[ComVisible(true), Guid(IID.IVDServer)]
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
		void GetDefinition(string filename, int startLine, int startIndex, int endLine, int endIndex);
		void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename);
	}

	class VDServerCompletionDataGenerator : ICompletionDataGenerator
	{
		public VDServerCompletionDataGenerator (string pre)
		{
			prefix = pre;
		}

		public void NotifyTimeout()
		{

		}

		/// <summary>
		/// Adds a token entry
		/// </summary>
		public void Add(byte Token)
		{
			addExpansion(DTokens.Keywords[Token], "KW", "");
		}

		/// <summary>
		/// Adds a property attribute
		/// </summary>
		public void AddPropertyAttribute(string AttributeText)
		{
			addExpansion(AttributeText, "PROP", "");
		}

		public void AddTextItem(string Text, string Description)
		{
			addExpansion(Text, "TEXT", Description);
		}

		class NodeTypeNameVisitor : NodeVisitor<string>
		{
			const string InvalidType = "I";
			const string TemplateType = "TMPL";

			public static readonly NodeTypeNameVisitor Instance = new NodeTypeNameVisitor();

			public string Visit(DEnumValue dEnumValue)
			{
				return "EVAL";
			}

			public string Visit(DVariable dVariable)
			{
				return "VAR";
			}

			public string Visit(DMethod n)
			{
				if (n.ContainsPropertyAttribute(BuiltInAtAttribute.BuiltInAttributes.Property))
					return "PROP";
				return "MTHD";
			}

			public string Visit(DClassLike dClassLike)
			{
				switch (dClassLike.ClassType)
				{
					case DTokens.Struct:
						return "STRU";
					default:
						return "CLSS";
					case DTokens.Interface:
						return "IFAC";
					case DTokens.Template:
						return TemplateType;
					case DTokens.Union:
						return "UNIO";
				}
			}

			public string Visit(DEnum dEnum)
			{
				return "ENUM";
			}

			public string Visit(DModule dModule)
			{
				return "MOD";
			}

			public string Visit(DBlockNode dBlockNode)
			{
				return InvalidType;
			}

			public string Visit(TemplateParameter.Node templateParameterNode)
			{
				return TemplateType; // ? or a more special type ?
			}

			public string Visit(NamedTemplateMixinNode n)
			{
				return "NMIX";
			}

			public string Visit(EponymousTemplate ep)
			{
				return TemplateType;
			}

			public string Visit(ModuleAliasNode moduleAliasNode)
			{
				return "VAR";
			}

			public string Visit(ImportSymbolNode importSymbolNode)
			{
				return "VAR";
			}

			public string Visit(ImportSymbolAlias importSymbolAlias)
			{
				return "VAR";
			}

			#region Not needed
			public string VisitAttribute(Modifier attr)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(DeprecatedAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(PragmaAttribute attr)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(BuiltInAtAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(UserDeclarationAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(VersionCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(DebugCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(StaticIfCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(NegatedDeclarationCondition a)
			{
				throw new NotImplementedException();
			}
			#endregion
		}

		class NodeToolTipContentGen : NodeTooltipRepresentationGen
		{

		}

		readonly static NodeToolTipContentGen tooltipContentGen = new NodeToolTipContentGen();

		/// <summary>
		/// Adds a node to the completion data
		/// </summary>
		/// <param name="Node"></param>
		public void Add(INode Node)
		{
			if (Node.NameHash == 0)
				return;
			var name = Node.Name;
			if(!name.StartsWith(prefix))
				return;

			var sb = new StringBuilder(tooltipContentGen.GenTooltipSignature(Node as DNode));
			
			Dictionary<string,string> cats;
			string summary;
			tooltipContentGen.GenToolTipBody(Node as DNode, out summary, out cats);

			if(!string.IsNullOrEmpty(summary) || (cats != null && cats.Count > 0))
				sb.Append("\n\n");

			if (!string.IsNullOrEmpty(summary))
				sb.Append(summary);

			if (cats != null)
			{
				foreach (var kv in cats)
				{
					sb.Append("\n<b>").Append(kv.Key).Append("</b>\n");
					sb.Append(kv.Value);
				}
			}

			addExpansion(name, Node.Accept(NodeTypeNameVisitor.Instance), sb.ToString());
		}

		/// <summary>
		/// Adds a module (name stub) to the completion data
		/// </summary>
		/// <param name="ModuleName"></param>
		/// <param name="AssocModule"></param>
		public void AddModule(DModule module,string nameOverride)
		{
			if(string.IsNullOrEmpty(nameOverride))
				addExpansion(module.Name, "MOD", "");
			else
				addExpansion(nameOverride, "MOD", "");
		}

		public void AddPackage(string packageName)
		{
			addExpansion(packageName, "PKG", "");
		}

		public void AddCodeGeneratingNodeItem(INode node, string codeToGenerate)
		{
			addExpansion(node.Name + "|" + codeToGenerate, "OVR", codeToGenerate);
		}

		public void AddIconItem(string iconName, string text, string description)
		{
			addExpansion(iconName + "|" + text, "ICN", description);
		}

		void addExpansion(string name, string type, string desc)
		{
			if(!string.IsNullOrEmpty(name))
				if(name.StartsWith(prefix))
					expansions += name.Replace("\r\n", "\a").Replace('\n', '\a') + ":" + type + ":" + desc.Replace("\r\n", "\a").Replace('\n', '\a') + "\n";
		}

		public string expansions;
		public string prefix;
	}

	[ComVisible(true), Guid(IID.VDServer)]
	[ClassInterface(ClassInterfaceType.None)]
	public class VDServer : IVDServer
	{
		private CodeLocation   _tipStart, _tipEnd;
		private string _tipText;
		private string _expansions;
		private string _imports;
		private string _stringImports;
		private string _versionIds;
		private string _debugIds;
		private uint   _flags;
		EditorData _editorData = new EditorData();

		public Dictionary<string, DModule> _modules = new Dictionary<string, DModule>();
		public Dictionary<string, string> _sources = new Dictionary<string, string>();

		public VDServer()
		{
			// MessageBox.Show("VDServer()");
		}

		public void ConfigureSemanticProject(string filename, string imp, string stringImp, string versionids, string debugids, uint flags)
		{
			if (_imports != imp) 
			{
				var impDirs = imp.Split('\n');
				GlobalParseCache.BeginAddOrUpdatePaths(impDirs);
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
			//MessageBox.Show("ClearSemanticProject()");
			//throw new NotImplementedException();
		}
		public void UpdateModule(string filename, string srcText, bool verbose)
		{
			DModule ast;
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

			//GlobalParseCache.RemoveModule(filename);
			GlobalParseCache.AddOrUpdateModule(ast);
			ConditionalCompilationFlags cflags = new ConditionalCompilationFlags(_editorData);
			//GlobalParseCache.UfcsCache.CacheModuleMethods(ast, ResolutionContext.Create(_parseCacheList, cflags, null, null)); 

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
			DModule ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(startIndex + 2, startLine);
			_tipText = "";

			_setupEditorData();
			_editorData.CaretLocation = _tipStart;
			_editorData.SyntaxTree = ast as DModule;
			_editorData.ModuleCode = _sources[filename];
			// codeOffset+1 because otherwise it does not work on the first character
			_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, _tipStart) + 1;
			List<AbstractTooltipContent> content = AbstractTooltipProvider.BuildToolTip(_editorData);
			if (content == null || content.Count == 0)
				_tipText = "";
			else
				foreach (var c in content) 
				{
					if (!string.IsNullOrEmpty (_tipText))
						_tipText += "\a";
					if (string.IsNullOrWhiteSpace (c.Description))
						_tipText += c.Title;
					else
						_tipText += c.Title + ":\n" + c.Description;
				}

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
			DModule ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			_setupEditorData();
			CodeLocation loc = new CodeLocation((int)idx + 1, (int) line);
			_editorData.SyntaxTree = ast as DModule;
			_editorData.ModuleCode = _sources[filename];
			_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, loc);
			// step back to beginning of identifier
			while(_editorData.CaretOffset > 0 && isIdentifierCharacter(_editorData.ModuleCode[_editorData.CaretOffset-1]))
			{
				_editorData.CaretOffset--;
				if(idx > 0)
					idx--;
			}
			_editorData.CaretLocation = new CodeLocation((int)idx + 1, (int) line);

			char triggerChar = string.IsNullOrEmpty(tok) ?  '\0' : tok[0];
			VDServerCompletionDataGenerator cdgen = new VDServerCompletionDataGenerator(tok);
			CodeCompletion.GenerateCompletionData(_editorData, cdgen, triggerChar);

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
			DModule ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);

			//MessageBox.Show("IsBinaryOperator()");
			throw new NotImplementedException();
		}
		public void GetParseErrors(string filename, out string errors)
		{
			DModule ast = null;
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
		public void GetDefinition(string filename, int startLine, int startIndex, int endLine, int endIndex)
		{
			DModule ast = null;
			if (!_modules.TryGetValue(filename, out ast))
				throw new COMException("module not found", 1);
			
			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(endIndex + 1, endLine);
			_tipText = "";
			
			_setupEditorData();
			_editorData.CaretLocation = _tipEnd;
			_editorData.SyntaxTree = ast as DModule;
			_editorData.ModuleCode = _sources[filename];
			// codeOffset+1 because otherwise it does not work on the first character
			_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, _tipStart) + 2;

			DResolver.NodeResolutionAttempt attempt;
			var rr = DResolver.ResolveTypeLoosely(_editorData, out attempt);

			_tipText = "";
			if (rr != null)
			{
				var n = DResolver.GetResultMember(rr, true);

				if (n == null)
					return;

				_tipStart = n.Location;
				_tipEnd = n.EndLocation;
				INode node = n.NodeRoot;
				if(node is DModule)
					_tipText = (node as DModule).FileName;
			}
		}

		public void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename)
		{
			startLine = _tipStart.Line;
			startIndex = _tipStart.Column - 1;
			endLine = _tipEnd.Line;
			endIndex = _tipEnd.Column - 1;
			filename = _tipText;
		}

		///////////////////////////////////
		void _setupEditorData()
		{
			string versions = _versionIds;
			versions += "Windows\n" + "LittleEndian\n" + "D_HardFloat\n" + "all\n" + "D_Version2\n";
			if ((_flags & 1) != 0)
				versions += "unittest\n";
			if ((_flags & 2) != 0)
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
				
			_editorData.ParseCache = new ParseCacheView(_imports.Split('\n'));
			_editorData.IsDebug = (_flags & 2) != 0;
			_editorData.DebugLevel = (int)(_flags >> 16) & 0xff;
			_editorData.VersionNumber = (int)(_flags >> 8) & 0xff;
			_editorData.GlobalVersionIds = versions.Split('\n');
			_editorData.GlobalDebugIds = _debugIds.Split('\n');
            CompletionOptions.Instance.ShowUFCSItems = (_flags & 0x2000000) != 0;
            CompletionOptions.Instance.DisableMixinAnalysis = (_flags & 0x1000000) == 0;
			CompletionOptions.Instance.HideDeprecatedNodes = (_flags & 128) != 0;
            CompletionOptions.Instance.CompletionTimeout = 500;
		}

#if false
		[EditorBrowsable(EditorBrowsableState.Never)]
		[ComRegisterFunction()]
		public static void Register(Type t)
		{
			try
			{
				RegasmRegisterLocalServer(t);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
				throw ex; // Re-throw the exception
			}
		}
		
		[EditorBrowsable(EditorBrowsableState.Never)]
		[ComUnregisterFunction()]
		public static void Unregister(Type t)
		{
			try
			{
				RegasmUnregisterLocalServer(t);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
				throw ex; // Re-throw the exception
			}
		}

		/// <summary>
		/// Register the component as a local server.
		/// </summary>
		/// <param name="t"></param>
		public static void RegasmRegisterLocalServer(Type t)
		{
			GuardNullType(t, "t");  // Check the argument
			
			// Open the CLSID key of the component.
			using (RegistryKey keyCLSID = Registry.ClassesRoot.OpenSubKey(
				@"CLSID\" + t.GUID.ToString("B"), /*writable*/true))
			{
				// Remove the auto-generated InprocServer32 key after registration
				// (REGASM puts it there but we are going out-of-proc).
				keyCLSID.DeleteSubKeyTree("InprocServer32");
				
				// Create "LocalServer32" under the CLSID key
				using (RegistryKey subkey = keyCLSID.CreateSubKey("LocalServer32"))
				{
					subkey.SetValue("", Assembly.GetExecutingAssembly().Location,
					                RegistryValueKind.String);
				}
			}
		}
		
		/// <summary>
		/// Unregister the component.
		/// </summary>
		/// <param name="t"></param>
		public static void RegasmUnregisterLocalServer(Type t)
		{
			GuardNullType(t, "t");  // Check the argument
			
			// Delete the CLSID key of the component
			Registry.ClassesRoot.DeleteSubKeyTree(@"CLSID\" + t.GUID.ToString("B"));
		}
		
		private static void GuardNullType(Type t, String param)
		{
			if (t == null)
			{
				throw new ArgumentException("The CLR type must be specified.", param);
			}
		}
#endif
	}
}


