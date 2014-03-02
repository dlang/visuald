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

		/// <summary>
		/// Adds a node to the completion data
		/// </summary>
		/// <param name="Node"></param>
		public void Add(INode Node)
		{
			string name = Node.Name;
			if(string.IsNullOrEmpty(name) || !name.StartsWith(prefix))
				return;

			string type = "I"; // Node.GetType().ToString()
			if (Node is DMethod)
				type = "MTHD";
			else if (Node is DClassLike)
			{
				var ctype = (Node as DClassLike).ClassType;
				if (ctype == DTokens.Struct)
					type = "STRU";
				else if (ctype == DTokens.Class)
					type = "CLSS";
				else if (ctype == DTokens.Interface)
					type = "IFAC";
				else if (ctype == DTokens.Template)
					type = "TMPL";
				else if (ctype == DTokens.Union)
					type = "UNIO";
			}
			else if (Node is DEnum)
				type = "ENUM";
			else if (Node is DEnumValue)
				type = "EVAL";
			else if (Node is NamedTemplateMixinNode)
				type = "NMIX";
			else if (Node is DVariable)
				type = "VAR";
			else if (Node is DModule)
				type = "MOD";

			string desc = Node.Description;
            if(!string.IsNullOrEmpty(desc))
                desc = desc.Trim();

			string proto = VDServerCompletionDataGenerator.GeneratePrototype(Node);
			if (!string.IsNullOrEmpty(proto) && !string.IsNullOrEmpty(desc))
				proto = proto + "\n\n";
			desc = proto + desc;
			addExpansion(name, type, desc);
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

		// generate prototype
		public static string GeneratePrototype(INode node, int currentParameter = -1, bool isInTemplateArgInsight = false)
		{
			if(node is DMethod)
				return VDServerCompletionDataGenerator.GeneratePrototype(node as DMethod, isInTemplateArgInsight, currentParameter);
			if(node is DVariable)
				return VDServerCompletionDataGenerator.GeneratePrototype(node as DVariable);
			if(node is DelegateType)
				return VDServerCompletionDataGenerator.GeneratePrototype(node as DelegateType, currentParameter);
			if(node is DelegateDeclaration)
				return VDServerCompletionDataGenerator.GeneratePrototype(node as DelegateDeclaration, currentParameter);
			if(node is AbstractType)
				return VDServerCompletionDataGenerator.GeneratePrototype(node as AbstractType, currentParameter, isInTemplateArgInsight);
			return null;
		}

		public static string GeneratePrototype(AbstractType t, int currentParameter = -1, bool isInTemplateArgInsight = false)
		{
			var ms = t as MemberSymbol;
			if (ms != null)
			{
				if (ms.Definition is DVariable)
				{
					var bt = DResolver.StripAliasSymbol(ms.Base);
					if (bt is DelegateType)
						return VDServerCompletionDataGenerator.GeneratePrototype(bt as DelegateType, currentParameter);
				}
				else if (ms.Definition is DMethod)
					return VDServerCompletionDataGenerator.GeneratePrototype(ms.Definition as DMethod, isInTemplateArgInsight, currentParameter);
			}
			else if (t is TemplateIntermediateType)
				return VDServerCompletionDataGenerator.GeneratePrototype(t as TemplateIntermediateType, currentParameter);

			return null;
		}

		public static string GeneratePrototype(DelegateType dt, int currentParam = -1)
		{
			var dd = dt.TypeDeclarationOf as DelegateDeclaration;
			if (dd != null)
				return VDServerCompletionDataGenerator.GeneratePrototype(dd, currentParam);

			return null;
		}

		public static string GeneratePrototype(DelegateDeclaration dd, int currentParam = -1)
		{
			var sb = new StringBuilder("Delegate: ");

			if (dd.ReturnType != null)
				sb.Append(dd.ReturnType.ToString(true)).Append(' ');

			if (dd.IsFunction)
				sb.Append("function");
			else
				sb.Append("delegate");

			sb.Append('(');
			if (dd.Parameters != null && dd.Parameters.Count != 0)
			{
				for (int i = 0; i < dd.Parameters.Count; i++)
				{
					var p = dd.Parameters[i] as DNode;
					if (i == currentParam)
					{
						sb.Append(p.ToString(false)).Append(',');
					}
					else
						sb.Append(p.ToString(false)).Append(',');
				}

				sb.Remove(sb.Length - 1, 1);
			}
			sb.Append(')');

			return sb.ToString();
		}

		public static string GeneratePrototype(DVariable dv)
		{
			var sb = new StringBuilder("Variable in ");
			sb.Append(AbstractNode.GetNodePath (dv, false));
			sb.Append(": ");

			sb.Append(dv.ToString (false));
			return sb.ToString();
		}

		public static string GeneratePrototype(DMethod dm, bool isTemplateParamInsight=false, int currentParam=-1)
		{
			var sb = new StringBuilder("");

			string name;
			switch (dm.SpecialType)
			{
			case DMethod.MethodType.Constructor:
				sb.Append("Constructor");
				name = dm.Parent.Name;
				break;
			case DMethod.MethodType.Destructor:
				sb.Append("Destructor");
				name = dm.Parent.Name;
				break;
			case DMethod.MethodType.Allocator:
				sb.Append("Allocator");
				name = dm.Parent.Name;
				break;
			default:
				sb.Append("Method");
				name = dm.Name;
				break;
			}
			sb.Append(" in ");
			sb.Append(AbstractNode.GetNodePath (dm, false));
			sb.Append(": ");

			if (dm.Attributes != null && dm.Attributes.Count > 0)
				sb.Append(dm.AttributeString + ' ');

			if (dm.Type != null)
			{
				sb.Append(dm.Type.ToString(true));
				sb.Append(" ");
			}
			else if (dm.Attributes != null && dm.Attributes.Count != 0)
			{
				foreach (var attr in dm.Attributes)
				{
					var m = attr as Modifier;
					if (m != null && DTokens.IsStorageClass(m.Token))
					{
						sb.Append(DTokens.GetTokenString(m.Token));
						sb.Append(" ");
						break;
					}
				}
			}

			sb.Append(name);

			// Template parameters
			if (dm.TemplateParameters != null && dm.TemplateParameters.Length > 0)
			{
				sb.Append("(");

				for (int i = 0; i < dm.TemplateParameters.Length; i++)
				{
					var p = dm.TemplateParameters[i];
					if (isTemplateParamInsight && i == currentParam)
					{
						sb.Append(p.ToString());
					}
					else
						sb.Append(p.ToString());

					if (i < dm.TemplateParameters.Length - 1)
						sb.Append(",");
				}

				sb.Append(")");
			}

			// Parameters
			sb.Append("(");

			for (int i = 0; i < dm.Parameters.Count; i++)
			{
				var p = dm.Parameters[i] as DNode;
				if (!isTemplateParamInsight && i == currentParam)
				{
					sb.Append(p.ToString(true, false));
				}
				else
					sb.Append(p.ToString(true, false));

				if (i < dm.Parameters.Count - 1)
					sb.Append(",");
			}

			sb.Append(")");
			return sb.ToString();
		}

		public static string GeneratePrototype(TemplateIntermediateType tit, int currentParam = -1)
		{
			var sb = new StringBuilder("");

			if (tit is ClassType)
				sb.Append("Class");
			else if (tit is InterfaceType)
				sb.Append("Interface");
			else if (tit is TemplateType)
				sb.Append("Template");
			else if (tit is StructType)
				sb.Append("Struct");
			else if (tit is UnionType)
				sb.Append("Union");

			var dc = tit.Definition;
			sb.Append(" in ");
			sb.Append(AbstractNode.GetNodePath (dc, false));
			sb.Append(": ").Append(tit.Name);
			if (dc.TemplateParameters != null && dc.TemplateParameters.Length != 0)
			{
				sb.Append('(');
				for (int i = 0; i < dc.TemplateParameters.Length; i++)
				{
					sb.Append(dc.TemplateParameters[i].ToString());
					sb.Append(',');
				}
				sb.Remove(sb.Length - 1, 1).Append(')');
			}

			return sb.ToString ();
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
						_tipText += "\n\n";
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

			var ctxt=ResolutionContext.Create(_editorData);
			var rr = DResolver.ResolveType(_editorData, ctxt);

			_tipText = "";
			if (rr != null && rr.Length > 0)
			{
				var res = rr[rr.Length - 1];				
				var n = DResolver.GetResultMember(res);
				
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


