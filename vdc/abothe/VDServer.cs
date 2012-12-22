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

using D_Parser.Parser;
using D_Parser.Misc;
using D_Parser.Dom;
using D_Parser.Completion;

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
			if(DTokens.Keywords[Token].StartsWith(prefix))
            	expansions += DTokens.Keywords[Token] + "\n";
        }

        /// <summary>
        /// Adds a property attribute
        /// </summary>
        public void AddPropertyAttribute(string AttributeText)
        {
			if(AttributeText.StartsWith(prefix))
				expansions += AttributeText + "\n";
        }

        public void AddTextItem(string Text, string Description)
        {
			if(Text.StartsWith(prefix))
				expansions += Text + "\n";
        }

        /// <summary>
        /// Adds a node to the completion data
        /// </summary>
        /// <param name="Node"></param>
        public void Add(INode Node)
        {
			if(Node.Name.StartsWith(prefix))
				expansions += Node.Name + "\n";
        }

        /// <summary>
        /// Adds a module (name stub) to the completion data
        /// </summary>
        /// <param name="ModuleName"></param>
        /// <param name="AssocModule"></param>
        public void Add(string ModuleName, IAbstractSyntaxTree Module = null, string PathOverride = null)
        {
            expansions += ModuleName + "\n";
        }

        public string expansions;
        public string prefix;
    }

    [ComVisible(true), Guid("002a2de9-8bb6-484d-AA05-7e4ad4084715")]
    [ClassInterface(ClassInterfaceType.None)]
    public class VDServer : IVDServer
    {
        private ParseCacheList _parseCacheList;
        private ParseCache _parseCache;
        private CodeLocation _tipStart, _tipEnd;
        private string _tipText;
        private string _expansions;

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
            try
            {
                IAbstractSyntaxTree ast = DParser.ParseString(srcText, false);
                //_parseCache.AddOrUpdate(ast);
                _modules[filename] = ast;
                _sources[filename] = srcText;
            }
            catch(Exception)
            {
            }
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

        public void GetTip(string filename, int startLine, int startIndex, int endLine, int endIndex)
        {
            IAbstractSyntaxTree ast = null;
            if (!_modules.TryGetValue(filename, out ast))
                throw new COMException("module not found", 1);

            _tipStart = new CodeLocation(startIndex + 1, startLine);
            _tipEnd = new CodeLocation(startIndex + 2, startLine);
            _tipText = "";

            EditorData editorData = new EditorData();
            editorData.CaretLocation = _tipStart;
            editorData.SyntaxTree = ast as DModule;
            editorData.ModuleCode = _sources[filename];
			editorData.ParseCache = _parseCacheList;
            editorData.CaretOffset = getCodeOffset(editorData.ModuleCode, _tipStart);
            AbstractTooltipContent[] content = AbstractTooltipProvider.BuildToolTip(editorData);
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
            EditorData editorData = new EditorData();
            editorData.CaretLocation = loc;
            editorData.SyntaxTree = ast as DModule;
            editorData.ModuleCode = _sources[filename];
            editorData.CaretOffset = getCodeOffset(editorData.ModuleCode, loc);
			editorData.ParseCache = _parseCacheList;
            VDServerCompletionDataGenerator cdgen = new VDServerCompletionDataGenerator(tok);
            AbstractCompletionProvider provider = AbstractCompletionProvider.BuildCompletionData(cdgen, editorData, tok);
            _expansions = cdgen.expansions;
            //MessageBox.Show("GetSemanticExpansions()");
            //throw new NotImplementedException();
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
            message = "";
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
	}
}
