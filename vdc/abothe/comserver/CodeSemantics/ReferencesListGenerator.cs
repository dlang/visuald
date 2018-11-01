using System;
using System.Text;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Parser;
using D_Parser.Refactoring;
using D_Parser.Resolver;
using D_Parser.Resolver.ExpressionSemantics;
using D_Parser.Resolver.TypeResolution;
using System.IO;

namespace DParserCOMServer.CodeSemantics
{
	public class ReferencesListGenerator : AbstractVDServerTask<string, object>
	{
		private readonly VDServer _vdServer;
		public ReferencesListGenerator(VDServer vdServer, EditorDataProvider editorDataProvider)
			: base(vdServer, editorDataProvider)
		{
			_vdServer = vdServer;
		}

		protected override string Process(EditorData editorData, object parameter)
		{
			var sr = DResolver.GetScopedCodeObject(editorData);
			var rr = sr != null ? LooseResolution.ResolveTypeLoosely(editorData, sr, out _, true) : null;

			var refs = new StringBuilder();
			if (rr != null)
			{
				var n = ExpressionTypeEvaluation.GetResultMember(rr);

				if (n != null)
				{
					var ctxt = ResolutionContext.Create(editorData, true);
					if (n.ContainsAnyAttribute(DTokens.Private) || (n is DVariable variable && variable.IsLocal))
					{
						GetReferencesInModule(editorData.SyntaxTree, refs, n, ctxt);
					}
					else
					{
						foreach (var rootPackage in editorData.ParseCache.EnumRootPackagesSurroundingModule(editorData.SyntaxTree))
							foreach (var module in rootPackage)
								GetReferencesInModule(module, refs, n, ctxt);
					}
				}

				//var res = TypeReferenceFinder.Scan(_editorData, System.Threading.CancellationToken.None, null);
			}

			return refs.ToString();
		}

		private void GetReferencesInModule(DModule ast, StringBuilder refs, DNode n, ResolutionContext ctxt)
		{
			var res = ReferencesFinder.SearchModuleForASTNodeReferences(ast, n, ctxt);

			foreach (var r in res)
			{
				var rfilename = ast.FileName;
				var rloc = r.Location;
				var len = r.ToString().Length;
				var src = GetSource(rfilename);
				var linetxt = GetSourceLine(src, rloc.Line);
				var ln = $"{rloc.Line},{rloc.Column - 1},{rloc.Line},{rloc.Column + len - 1}:{rfilename}|{linetxt}\n";

				refs.Append(ln);
			}
		}

		private string GetSource(string fileName)
		{
			var sources = _vdServer._sources;
			if (!sources.ContainsKey(fileName))
			{
				try
				{
					sources[fileName] = File.ReadAllText(fileName);
				}
				catch (Exception)
				{
					return "";
				}
			}
			return sources[fileName];
		}

		private static string GetSourceLine(string s, int line)
		{
			int off = 0;
			for (int ln = 1; ln < line; ln++)
				off = s.IndexOf('\n', off) + 1;
			int end = s.IndexOf('\n', off);
			return s.Substring(off, end - off);
		}
	}
}
