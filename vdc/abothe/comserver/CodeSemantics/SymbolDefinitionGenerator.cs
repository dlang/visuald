using System;
using System.Text;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Parser;
using D_Parser.Resolver;
using D_Parser.Resolver.ExpressionSemantics;
using D_Parser.Resolver.TypeResolution;

namespace DParserCOMServer.CodeSemantics
{
	public class SymbolDefinitionGenerator
		: AbstractVDServerTask<Tuple<CodeLocation, CodeLocation, string>, CodeLocation>
	{
		public SymbolDefinitionGenerator(VDServer vdServer, EditorDataProvider editorDataProvider)
			: base(vdServer, editorDataProvider) { }

		protected override Tuple<CodeLocation, CodeLocation, string> Process(EditorData editorData, CodeLocation tipEnd)
		{
			var tipStart = editorData.CaretLocation;
			editorData.CaretOffset += 2;
			editorData.CaretLocation = tipEnd;

			var sr = DResolver.GetScopedCodeObject(editorData);
			var rr = sr != null ? LooseResolution.ResolveTypeLoosely(editorData, sr, out _, true) : null;

			var definitionSourceFilename = new StringBuilder();
			if (rr != null)
			{
				if (rr is AliasedType at)
				{
					// jump to original definition if it is not renamed or the caret is on the import
					var isRenamed = (at.Definition as ImportSymbolAlias)?.ImportBinding?.Alias != null;
					if (!isRenamed || at.Definition.Location == sr.Location)
						rr = at.Base;
				}
				DNode n = null;
				foreach (var t in AmbiguousType.TryDissolve(rr))
				{
					n = ExpressionTypeEvaluation.GetResultMember(t);
					if (n != null)
						break;
				}

				if (n != null)
				{
					if (definitionSourceFilename.Length > 0)
						definitionSourceFilename.Append("\n");
					bool decl = false;
					if (n is DMethod method)
						decl = method.Body == null;
					else if (n.ContainsAnyAttribute(DTokens.Extern))
						decl = true;
					if (decl)
						definitionSourceFilename.Append("EXTERN:");

					tipStart = n.Location;
					tipEnd = n.EndLocation;
					if (n.NodeRoot is DModule module)
						definitionSourceFilename.Append(module.FileName);
				}
			}

			return Tuple.Create(tipStart, tipEnd, definitionSourceFilename.ToString());
		}
	}
}
