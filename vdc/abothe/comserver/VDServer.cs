﻿//
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
using System.Threading;
using Microsoft.Win32;
using System.Reflection;

using D_Parser.Parser;
using D_Parser.Misc;
using D_Parser.Dom;
using D_Parser.Completion;
using D_Parser.Resolver;
using D_Parser.Resolver.TypeResolution;
using D_Parser.Completion.ToolTips;
using D_Parser.Refactoring;

namespace DParserCOMServer
{
	public class IID
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
		void GetReferences(string filename, string tok, uint line, uint idx, string expr);
        void GetReferencesResult(out string stringList);
	}

	class NodeToolTipContentGen : NodeTooltipRepresentationGen
	{
		public static readonly NodeToolTipContentGen Instance = new NodeToolTipContentGen();

		private NodeToolTipContentGen() {
			SignatureFlags = TooltipSignatureFlags.NoEnsquaredDefaultParams | TooltipSignatureFlags.NoLineBreakedMethodParameters;
		}

		protected override void AppendFormat (string content, StringBuilder sb, FormatFlags flags, double r = 0, double g = 0, double b = 0)
		{
			sb.Append (content);
			//base.AppendFormat (content, sb, flags, r, g, b);
		}
	}

    public class VDserverParseCacheView : ParseCacheView
    {
        #region Properties
        readonly List<RootPackage> packs;
        #endregion

        #region Constructors
        public VDserverParseCacheView(IEnumerable<string> packageRoots)
        {
            this.packs = new List<RootPackage>();
            Add(packageRoots);
        }

        public VDserverParseCacheView(IEnumerable<RootPackage> packages)
        {
            this.packs = new List<RootPackage>(packages);
        }
        #endregion

        public override IEnumerable<RootPackage> EnumRootPackagesSurroundingModule(DModule module)
        {
            return packs;
        }

        public void Add(RootPackage pack)
        {
            if (pack != null && !packs.Contains(pack))
                packs.Add(pack);
        }

        public void Add(IEnumerable<string> roots)
        {
            RootPackage rp;
            foreach (var r in roots)
                if ((rp = GlobalParseCache.GetRootPackage(r)) != null && !packs.Contains(rp))
                    packs.Add(rp);
        }
    }

    public class Request
    {
        public const byte None = 0;
        public const byte Tip = 1;
        public const byte Expansions = 2;
        public const byte Definition = 3;
        public const byte References = 4;
    }

	[ComVisible(true), Guid(IID.VDServer)]
	[ClassInterface(ClassInterfaceType.None)]
	public class VDServer : IVDServer
	{
		private CodeLocation   _tipStart, _tipEnd;
        
        private string _result;
        private byte _request = Request.None;

		private string _imports;
		private string _stringImports;
		private string _versionIds;
		private string _debugIds;
		private uint   _flags;

        EditorData _editorData = new EditorData();

        // remember modules, the global cache might not yet be ready or might have forgotten a module
		public Dictionary<string, DModule> _modules = new Dictionary<string, DModule>();

		public DModule GetModule(string fileName)
		{
			DModule mod;
			mod = GlobalParseCache.GetModule (fileName);
            if (mod == null)
                _modules.TryGetValue(fileName, out mod);
            return mod;
		}
		public Dictionary<string, string> _sources = new Dictionary<string, string>();

		public VDServer()
		{
			// MessageBox.Show("VDServer()");
		}

        ~VDServer()
        {
            StopCompletionThread();
        }

        private static string normalizePath(string path)
        {
            path = Path.GetFullPath(path);
            return path.ToLower();
        }

        private static string normalizeDir(string dir)
        {
            dir = normalizePath(dir);
            if (!dir.EndsWith("\\"))
                dir += '\\';
            return dir;
        }

        private string[] uniqueDirectories(string imp)
        {
            var impDirs = imp.Split('\n');
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
			if (_imports != imp) 
			{
                string[] uniqueDirs = uniqueDirectories(imp);
				GlobalParseCache.BeginAddOrUpdatePaths(uniqueDirs);
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
            filename = normalizePath(filename);
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

			_modules [filename] = ast;
			GlobalParseCache.AddOrUpdateModule(ast);

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

		Thread completionThread;
        AutoResetEvent completionEvent = new AutoResetEvent(true);
        Mutex completionMutex = new Mutex();
        Action runningAction;
        Action nextAction;
        CancellationTokenSource cancelTokenSource = new CancellationTokenSource();

        void LaunchCompletionThread()
        {
            if (completionMutex.WaitOne(0))
            {
                if (completionThread == null || !completionThread.IsAlive)
                {
                    completionThread = new Thread(runAsyncCompletionLoop)
                    {
                        IsBackground = true,
                        Name = "completion thread",
                        Priority = ThreadPriority.BelowNormal
                    };
                    completionThread.Start();
                }
                completionMutex.ReleaseMutex();
            }
        }
        void StopCompletionThread()
        {
            if (completionMutex.WaitOne(0))
            {
                if (completionThread != null && completionThread.IsAlive)
                    completionEvent.Set();
                completionThread = null;
                completionMutex.ReleaseMutex();
            }
        }

        void runAsyncCompletionLoop()
        {
            while (completionThread != null)
            {
                if (nextAction == null)
                {
                    completionEvent.WaitOne(100);
                    continue;
                }
                if (completionMutex.WaitOne(100))
                {
                    runningAction = nextAction;
                    nextAction = null;
                    completionMutex.ReleaseMutex();
                }
                if (runningAction != null)
                {
                    cancelTokenSource = new CancellationTokenSource();
#if NET40
#else
                    if (CompletionOptions.Instance.CompletionTimeout > 0)
                        cancelTokenSource.CancelAfter(CompletionOptions.Instance.CompletionTimeout);
#endif
                    _editorData.CancelToken = cancelTokenSource.Token;
                    runningAction();
                }
            }
        }

        void runAsync(Action a)
        {
            LaunchCompletionThread();
            if (completionMutex.WaitOne(0))
            {
                cancelTokenSource.Cancel();
                nextAction = a;
                completionMutex.ReleaseMutex();
            }
        }

        public void GetTip(string filename, int startLine, int startIndex, int endLine, int endIndex)
		{
            filename = normalizePath(filename);
            var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(startIndex + 2, startLine);

            _request = Request.Tip;
            _result = "__pending__";

            Action dg = () =>
            {
                _setupEditorData();
                _editorData.CaretLocation = _tipStart;
                _editorData.SyntaxTree = ast as DModule;
                _editorData.ModuleCode = _sources[filename];
                // codeOffset+1 because otherwise it does not work on the first character
                _editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, _tipStart) + 1;

                ISyntaxRegion sr = DResolver.GetScopedCodeObject(_editorData);
                LooseResolution.NodeResolutionAttempt attempt;
                AbstractType types = sr != null ? LooseResolution.ResolveTypeLoosely(_editorData, sr, out attempt, true) : null;

                if (_editorData.CancelToken.IsCancellationRequested)
                    return;

                StringBuilder tipText = new StringBuilder();
                if (types != null)
                {
                    if (sr != null)
                    {
                        _tipStart = sr.Location;
                        _tipEnd = sr.EndLocation;
                    }

                    DNode dn = null;

                    foreach (var t in AmbiguousType.TryDissolve(types))
                    {
                        tipText.Append(NodeToolTipContentGen.Instance.GenTooltipSignature(t)).Append("\a");
                        if (t is DSymbol)
                            dn = (t as DSymbol).Definition;
                    }

                    while (tipText.Length > 0 && tipText[tipText.Length - 1] == '\a')
                        tipText.Length--;

                    if (dn != null)
                        VDServerCompletionDataGenerator.GenerateNodeTooltipBody(dn, tipText);

                    while (tipText.Length > 0 && tipText[tipText.Length - 1] == '\a')
                        tipText.Length--;
                }
                if (_request == Request.Tip)
                    _result = tipText.ToString();
            };
            runAsync (dg);

        }
        public void GetTipResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string answer)
		{
			startLine = _tipStart.Line;
			startIndex = _tipStart.Column - 1;
			endLine = _tipEnd.Line;
			endIndex = _tipEnd.Column - 1;
			answer = _request == Request.Tip ? _result : "__cancelled__";
			//MessageBox.Show("GetTipResult()");
			//throw new NotImplementedException();
		}
		
        public void GetSemanticExpansions(string filename, string tok, uint line, uint idx, string expr)
		{
            filename = normalizePath(filename);
            var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);

			_request = Request.Expansions;
			_result = "__pending__";

			Action dg = () =>
			{
				_setupEditorData();
				CodeLocation loc = new CodeLocation((int)idx + 1, (int)	line);
				_editorData.SyntaxTree = ast as DModule;
				_editorData.ModuleCode = _sources[filename];
				_editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode,	loc);
				// step	back to	beginning of identifier
				while(_editorData.CaretOffset > 0 && Lexer.IsIdentifierPart(_editorData.ModuleCode[_editorData.CaretOffset-1]))
				{
					_editorData.CaretOffset--;
					if(idx > 0)
						idx--;
				}
				_editorData.CaretLocation = new CodeLocation((int)idx + 1, (int) line);

				char triggerChar = string.IsNullOrEmpty(tok) ? '\0' : tok[0];

				VDServerCompletionDataGenerator	cdgen = new VDServerCompletionDataGenerator(tok);
				CodeCompletion.GenerateCompletionData(_editorData, cdgen, triggerChar);
                if (!_editorData.CancelToken.IsCancellationRequested && _request == Request.Expansions)
				{
					_result = cdgen.expansions.ToString();
				}
			};
			runAsync (dg);
		}
		public void GetSemanticExpansionsResult(out string stringList)
		{
			stringList = _request == Request.Expansions ? _result : "__cancelled__";
			//MessageBox.Show("GetSemanticExpansionsResult()");
			//throw new NotImplementedException();
		}

        public void GetParseErrors(string filename, out string errors)
		{
            filename = normalizePath(filename);
            var ast = GetModule(filename);

			if (ast == null)
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

        public void IsBinaryOperator(string filename, uint startLine, uint startIndex, uint endLine, uint endIndex, out bool pIsOp)
        {
            filename = normalizePath(filename);
            var ast = GetModule(filename);

            if (ast == null)
                throw new COMException("module not found", 1);

            //MessageBox.Show("IsBinaryOperator()");
            throw new NotImplementedException();
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
			filename = normalizePath(filename);
			var ast = GetModule(filename);

			if (ast == null)
				throw new COMException("module not found", 1);
			
			_tipStart = new CodeLocation(startIndex + 1, startLine);
			_tipEnd = new CodeLocation(endIndex + 1, endLine);

			_request = Request.Definition;
			_result = "__pending__";

			Action dg = () =>
			{
                _setupEditorData();
                _editorData.CaretLocation = _tipEnd;
                _editorData.SyntaxTree = ast as DModule;
                _editorData.ModuleCode = _sources[filename];
                // codeOffset+1 because otherwise it does not work on the first character
                _editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, _tipStart) + 2;

                ISyntaxRegion sr = DResolver.GetScopedCodeObject(_editorData);
				LooseResolution.NodeResolutionAttempt attempt;
				var	rr = sr	!= null	? LooseResolution.ResolveTypeLoosely(_editorData, sr, out attempt, true) : null;

				StringBuilder tipText = new StringBuilder();
				if (rr != null)
				{
					DNode n = null;
					foreach (var t in AmbiguousType.TryDissolve(rr))
					{
						n =	DResolver.GetResultMember(t, true);
						if (n != null)
							break;
					}

					if (n != null)
					{
						if (tipText.Length > 0)
							tipText.Append("\n");
						bool decl = false;
						var mthd = n as DMethod;
						if (mthd != null)
							decl = mthd.Body ==	null;
						else if (n.ContainsAttribute(DTokens.Extern))
							decl = true;
						if (decl)
							tipText.Append("EXTERN:");

						_tipStart = n.Location;
						_tipEnd = n.EndLocation;
						INode node = n.NodeRoot;
						if (node is DModule)
							tipText.Append((node as DModule).FileName);
					}
				}
				if (!_editorData.CancelToken.IsCancellationRequested && _request == Request.Definition)
					_result = tipText.ToString();
			};
			runAsync (dg);
		}
		public void GetDefinitionResult(out int startLine, out int startIndex, out int endLine, out int endIndex, out string filename)
		{
			startLine = _tipStart.Line;
			startIndex = _tipStart.Column - 1;
			endLine = _tipEnd.Line;
			endIndex = _tipEnd.Column - 1;
            filename = _request == Request.Definition ? _result : "__cancelled__";
		}

        public void GetReferences(string filename, string tok, uint line, uint idx, string expr)
        {
            filename = normalizePath(filename);
            var ast = GetModule(filename);

            if (ast == null)
                throw new COMException("module not found", 1);

            _request = Request.References;
            _result = "__pending__";

            Action dg = () =>
            {
                _setupEditorData();
                CodeLocation loc = new CodeLocation((int)idx + 1, (int)line);
                _editorData.CaretLocation = loc;
                _editorData.SyntaxTree = ast as DModule;
                _editorData.ModuleCode = _sources[filename];
                _editorData.CaretOffset = getCodeOffset(_editorData.ModuleCode, loc);

                ISyntaxRegion sr = DResolver.GetScopedCodeObject(_editorData);
                LooseResolution.NodeResolutionAttempt attempt;
                var rr = sr != null ? LooseResolution.ResolveTypeLoosely(_editorData, sr, out attempt, true) : null;

                StringBuilder refs = new StringBuilder();
                if (rr != null)
                {
                    var n = DResolver.GetResultMember(rr, true);

                    if (n != null)
                    {
                        var ctxt = ResolutionContext.Create(_editorData, true);
                        if (n.ContainsAttribute(DTokens.Private) || ((n is DVariable) && (n as DVariable).IsLocal))
                        {
                            GetReferencesInModule(ast, refs, n, ctxt);
                        }
                        else
                        {
                            foreach (var basePath in _imports.Split('\n'))
                                foreach (var mod in GlobalParseCache.EnumModulesRecursively(basePath))
                                    GetReferencesInModule(mod, refs, n, ctxt);
                        }
                    }
                    //var res = TypeReferenceFinder.Scan(_editorData, System.Threading.CancellationToken.None, null);
                }
                if (!_editorData.CancelToken.IsCancellationRequested && _request == Request.References)
                    _result = refs.ToString();
            };
        }

        private static void GetReferencesInModule(DModule ast, StringBuilder refs, DNode n, ResolutionContext ctxt)
        {
            var res = ReferencesFinder.SearchModuleForASTNodeReferences(ast, n, ctxt);

            int cnt = res.Count();
            foreach (var r in res)
            {
                var rfilename = ast.FileName;
                var rloc = r.Location;
                var ln = String.Format("{0},{1},{2},{3}:{4}\n", rloc.Line, rloc.Column - 1, rloc.Line, rloc.Column, rfilename);
                refs.Append(ln);
            }
        }
        public void GetReferencesResult(out string stringList)
        {
            stringList = _request == Request.Definition ? _result : "__cancelled__";
            //MessageBox.Show("GetSemanticExpansionsResult()");
            //throw new NotImplementedException();
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
            else if ((_flags & 0x4000000) != 0)
                versions += "LDC\n";
            else
                versions += "DigitalMars\n";
            if ((_flags & 0x8000000) != 0)
                versions += "CRuntime_Microsoft\n";
            else if ((_flags & 0x4000040) != 0) // GNU or LDC
                versions += "CRuntime_MinGW\n";
            else
                versions += "CRuntime_DigitalMars\n";

            string[] uniqueDirs = uniqueDirectories(_imports);
            _editorData.ParseCache = new VDserverParseCacheView(uniqueDirs);
			_editorData.IsDebug = (_flags & 2) != 0;
			_editorData.DebugLevel = (_flags >> 16) & 0xff;
			_editorData.VersionNumber = (_flags >> 8) & 0xff;
			_editorData.GlobalVersionIds = versions.Split('\n');
			_editorData.GlobalDebugIds = _debugIds.Split('\n');
            CompletionOptions.Instance.ShowUFCSItems = (_flags & 0x2000000) != 0;
            CompletionOptions.Instance.DisableMixinAnalysis = (_flags & 0x1000000) == 0;
			CompletionOptions.Instance.HideDeprecatedNodes = (_flags & 128) != 0;
            CompletionOptions.Instance.CompletionTimeout = -1; // 2000;
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


