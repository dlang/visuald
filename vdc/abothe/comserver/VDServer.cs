﻿//
// To be used by Visual D, set registry entry
// HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0D\ToolsOptionsPages\Projects\Visual D Settings\VDServerIID
// to "{002a2de9-8bb6-484d-AA05-7e4ad4084715}"

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Runtime.InteropServices;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using DParserCOMServer.CodeSemantics;
using D_Parser.Parser;
using D_Parser.Misc;
using D_Parser.Dom;
using D_Parser.Refactoring;
using D_Parser.Dom.Expressions;

namespace DParserCOMServer
{
	[ComVisible(true), Guid(IID.VDServer)]
	[ClassInterface(ClassInterfaceType.None)]
	public class VDServer : IVDServer
	{
		private readonly EditorDataProvider _editorDataProvider = new EditorDataProvider();
		private readonly TooltipGenerator _tipGenerationTask;
		private readonly SemanticExpansionsGenerator _semanticExpansionsTask;
		private readonly SymbolDefinitionGenerator _symbolDefinitionTask;
		private readonly ReferencesListGenerator _referencesTask;
		private CodeLocation   _tipStart, _tipEnd;

		private string _imports;

		private string[] _taskTokens;

		private static uint _activityCounter;

		public static uint Activity { get { return _activityCounter; } }

		// remember modules, the global cache might not yet be ready or might have forgotten a module
		readonly Dictionary<string, DModule> _modules = new Dictionary<string, DModule>();
		readonly Dictionary<string, string> _identiferTypes = new Dictionary<string, string>();

		public DModule GetModule(string fileName)
		{
			if (!_sources.ContainsKey(fileName))
				return null;
			DModule mod = GlobalParseCache.GetModule(fileName);
			if (mod == null)
				_modules.TryGetValue(fileName, out mod);
			return mod;
		}
		public Dictionary<string, string> _sources = new Dictionary<string, string>();

		public VDServer()
		{
			_tipGenerationTask = new TooltipGenerator(this, _editorDataProvider);
			_semanticExpansionsTask = new SemanticExpansionsGenerator(this, _editorDataProvider);
			_symbolDefinitionTask = new SymbolDefinitionGenerator(this, _editorDataProvider);
			_referencesTask = new ReferencesListGenerator(this, _editorDataProvider);
		}

		private static string normalizePath(string path)
		{
			path = Path.GetFullPath(path);
			return path.ToLower();
		}

		private static string normalizeDir(string dir)
		{
			dir = normalizePath(dir);
			if (dir.Length != 0 && dir[dir.Length - 1] == Path.DirectorySeparatorChar)
				dir += Path.DirectorySeparatorChar;
			return dir;
		}

		readonly char[] nlSeparator = { '\n' };

		private string[] uniqueDirectories(string imp)
		{
			var impDirs = imp.Split(nlSeparator, StringSplitOptions.RemoveEmptyEntries);
			string[] normDirs = new string[impDirs.Length];
			for (int i = 0; i < impDirs.Length; i++)
				normDirs[i] = normalizeDir(impDirs[i]);

			string[] uniqueDirs = new string[impDirs.Length];
			int unique = 0;
			for (int i = 0; i < normDirs.Length; i++)
			{
				int j;
				for (j = 0; j < normDirs.Length; j++)
					if (i != j && normDirs[i].StartsWith(normDirs[j]))
						if (normDirs[i] != normDirs[j] || j < i)
							break;
				if (j >= normDirs.Length)
					uniqueDirs[unique++] = normDirs[i];
			}

			Array.Resize(ref uniqueDirs, unique);
			return uniqueDirs;
		}

		public void ConfigureSemanticProject(string filename, string imp, string stringImp, string versionids, string debugids, uint flags)
		{
			_editorDataProvider.ConfigureEnvironment(imp, versionids, debugids, flags);

			if (_imports != imp) 
			{
				string[] uniqueDirs = uniqueDirectories(imp);
				GlobalParseCache.BeginAddOrUpdatePaths(uniqueDirs, taskTokens:_taskTokens);
				_activityCounter++;
			}
			_imports = imp;
		}
		public void ClearSemanticProject()
		{
			//MessageBox.Show("ClearSemanticProject()");
			//throw new NotImplementedException();
		}
		public void UpdateModule(string filename, string srcText, int flags)
		{
			filename = normalizePath(filename);
			DModule ast;
			try
			{
				ast = DParser.ParseString(srcText, false, true, _taskTokens);
			}
			catch (Exception ex)
			{
				ast = new DModule{ ParseErrors = new System.Collections.ObjectModel.ReadOnlyCollection<ParserError>(
						new List<ParserError>{
						new ParserError(false, ex.Message + "\n\n" + ex.StackTrace, DTokens.Invariant, CodeLocation.Empty)
					}) }; //WTF
			}
			if (string.IsNullOrEmpty(ast.ModuleName))
				ast.ModuleName = Path.GetFileNameWithoutExtension(filename);
			ast.FileName = filename;

			_modules [filename] = ast;
			_sources[filename] = srcText;
			GlobalParseCache.AddOrUpdateModule(ast);

			if ((flags & 2) != 0)
				UpdateIdentifierTypes(filename, ast);

			//MessageBox.Show("UpdateModule(" + filename + ")");
			//throw new NotImplementedException();
			_activityCounter++;
		}

		private void UpdateIdentifierTypes(string filename, DModule ast)
		{
			try
			{
				var editorData = _editorDataProvider.MakeEditorData();
				var cancelTokenSource = new CancellationTokenSource();
				cancelTokenSource.CancelAfter(300);
				editorData.CancelToken = cancelTokenSource.Token;
				editorData.SyntaxTree = ast;

				var invalidCodeRegions = new List<ISyntaxRegion>();
				var textLocationsToHighlight =
					TypeReferenceFinder.Scan(editorData, cancelTokenSource.Token, invalidCodeRegions);
				_identiferTypes[filename] = TextLocationsToIdentifierSpans(textLocationsToHighlight);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
			}
		}

		static string GetIdentifier(ISyntaxRegion sr)
		{
			switch (sr)
			{
				case INode n:
					return n.Name;
				case TemplateInstanceExpression templateInstanceExpression:
					return templateInstanceExpression.TemplateId; // Identifier.ToString(false);
				case NewExpression newExpression:
					return newExpression.Type.ToString(false);
				case TemplateParameter templateParameter:
					return templateParameter.Name;
				case IdentifierDeclaration identifierDeclaration:
					return identifierDeclaration.Id;
				default:
					return "";
			}
		}

		struct TextSpan
		{
			public CodeLocation start;
			public byte kind;
		};

		static string TextLocationsToIdentifierSpans(Dictionary<int, Dictionary<ISyntaxRegion, byte>> textLocations)
		{
			if (textLocations == null)
				return null;

			var identifierSpans = new Dictionary<string, List<TextSpan>>();
			foreach (var kv in textLocations)
			{
				var line = kv.Key;
				foreach (var kvv in kv.Value)
				{
					var sr = kvv.Key;
					var ident = GetIdentifier(sr);
					if (string.IsNullOrEmpty(ident))
						continue;

	                if (!identifierSpans.TryGetValue(ident, out var spans))
						spans = identifierSpans[ident] = new List<TextSpan>();

					else if (spans.Last().kind == kvv.Value)
						continue;

					var span = new TextSpan {start = sr.Location, kind = kvv.Value};
					spans.Add(span);
				}
			}
			var s = new StringBuilder();
			foreach (var idv in identifierSpans)
			{
				s.Append(idv.Key).Append(':').Append(idv.Value.First().kind.ToString());
				foreach (var span in idv.Value.GetRange(1, idv.Value.Count - 1))
				{
					s.Append($";{span.kind},{span.start.Line},{span.start.Column - 1}");
				}
				s.Append('\n');
			}
			return s.ToString();
		}

		public void GetTip(string filename, int startLine, int startIndex, int endLine, int endIndex, int flags)
		{
			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(startIndex + 2, startLine);

			_tipGenerationTask.Run(filename, _tipStart, (flags & 1) != 0);
		}

		public void GetTipResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string answer)
		{
			switch (_tipGenerationTask.TaskStatus)
			{
				case TaskStatus.RanToCompletion:
					var result = _tipGenerationTask.Result;
					startLine = Math.Max(0, result.Item1.Line);
					startIndex = Math.Max(0, result.Item1.Column - 1);
					endLine = Math.Max(0, result.Item2.Line);
					endIndex = Math.Max(0, result.Item2.Column - 1);
					answer = result.Item3;
					break;
				case TaskStatus.Faulted:
				case TaskStatus.Canceled:
					startLine = 0;
					startIndex = 0;
					endLine = 0;
					endIndex = 0;
					answer = "__cancelled__";
					break;
				default:
					startLine = _tipStart.Line;
					startIndex = _tipStart.Column - 1;
					endLine = _tipEnd.Line;
					endIndex = _tipEnd.Column - 1;
					answer = "__pending__";
					break;
			}
		}
		
		public void GetSemanticExpansions(string filename, string tok, uint line, uint idx, string expr)
		{
			_semanticExpansionsTask.Run(filename, new CodeLocation((int)idx + 1, (int)line), tok);
		}

		public void GetSemanticExpansionsResult(out string stringList)
		{
			switch (_semanticExpansionsTask.TaskStatus)
			{
				case TaskStatus.RanToCompletion:
					stringList = _semanticExpansionsTask.Result;
					break;
				case TaskStatus.Faulted:
				case TaskStatus.Canceled:
					stringList = "__cancelled__";
					break;
				default:
					stringList = "__pending__";
					break;
			}
		}

		public void GetParseErrors(string filename, out string errors)
		{
			filename = normalizePath(filename);
			var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			var asterrors = ast.ParseErrors;
			
			var errs = new StringBuilder();
			foreach (var err in asterrors)
				errs.Append($"{err.Location.Line},{err.Location.Column - 1},{err.Location.Line},{err.Location.Column}:{err.Message}\n");
			errors = errs.ToString();
			//MessageBox.Show("GetParseErrors()");
			//throw new COMException("No Message", 1);
		}

		public void GetIdentifierTypes(string filename, out string types)
		{
			filename = normalizePath(filename);
			if (!_identiferTypes.TryGetValue(filename, out types))
				throw new COMException("module not found", 1);
		}

		public void ConfigureCommentTasks(string tasks)
		{
			_taskTokens = tasks.Split(nlSeparator, StringSplitOptions.RemoveEmptyEntries);
		}

		public void GetCommentTasks(string filename, out string tasks)
		{
			filename = normalizePath(filename);
			var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			var tsks = new StringBuilder();
			if (ast.Tasks != null)
			foreach (var task in ast.Tasks)
				tsks.Append($"{task.Location.Line},{task.Location.Column - 1}:{task.Message}\n");

			tasks = tsks.ToString();
			//MessageBox.Show("GetCommentTasks()");
			//throw new COMException("No Message", 1);
		}

		public void IsBinaryOperator(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex, out bool pIsOp)
		{
			filename = normalizePath(filename);
			var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			//MessageBox.Show("IsBinaryOperator()");
			throw new NotImplementedException();
		}

		class BinaryIsInVisitor : DefaultDepthFirstVisitor
		{
			public List<int> locs = new List<int>();

			public override void Visit(IdentityExpression x)
			{
				locs.Add(x.opLine);
				locs.Add(x.opColumn - 1);
				base.Visit(x);
			}
			public override void Visit(InExpression x)
			{
				locs.Add(x.opLine);
				locs.Add(x.opColumn - 1);
				base.Visit(x);
			}
		}

		public void GetBinaryIsInLocations(string filename, out object locs) // array of pairs of DWORD
		{
			filename = normalizePath(filename);
			var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			var visitor = new BinaryIsInVisitor();
			ast.Accept(visitor);

			locs = visitor.locs.ToArray();
		}

		public void GetLastMessage(out string message)
		{
			//MessageBox.Show("GetLastMessage()");
			message = "__no_message__"; // avoid throwing exception
			//throw new COMException("No Message", 1);
		}

		public void GetDefinition(string filename, int startLine, int startIndex, int endLine, int endIndex)
		{
			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(endIndex + 1, endLine);
			_symbolDefinitionTask.Run(filename, _tipStart, _tipEnd);
		}
		public void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename)
		{
			switch (_symbolDefinitionTask.TaskStatus)
			{
				case TaskStatus.RanToCompletion:
					var result = _symbolDefinitionTask.Result;
					startLine = Math.Max(0, result.Item1.Line);
					startIndex = Math.Max(0, result.Item1.Column - 1);
					endLine = Math.Max(0, result.Item2.Line);
					endIndex = Math.Max(0, result.Item2.Column - 1);
					filename = result.Item3;
					break;
				case TaskStatus.Faulted:
				case TaskStatus.Canceled:
					startLine = 0;
					startIndex = 0;
					endLine = 0;
					endIndex = 0;
					filename = "__cancelled__";
					break;
				default:
					startLine = _tipStart.Line;
					startIndex = _tipStart.Column - 1;
					endLine = _tipEnd.Line;
					endIndex = _tipEnd.Column - 1;
					filename = "__pending__";
					break;
			}
		}

		public void GetReferences(string filename, string tok, uint line, uint idx, string expr)
		{
			_referencesTask.Run(filename, new CodeLocation((int)idx + 1, (int)line), null);
		}

		public void GetReferencesResult(out string stringList)
		{
			switch (_referencesTask.TaskStatus)
			{
				case TaskStatus.RanToCompletion:
					stringList = _referencesTask.Result;
					break;
				case TaskStatus.Faulted:
				case TaskStatus.Canceled:
					stringList = "__cancelled__";
					break;
				default:
					stringList = "__pending__";
					break;
			}
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


