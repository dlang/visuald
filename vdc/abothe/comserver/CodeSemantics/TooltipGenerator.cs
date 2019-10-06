using System;
using System.Collections.Generic;
using System.Text;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Dom.Expressions;
using D_Parser.Resolver;
using D_Parser.Resolver.ExpressionSemantics;
using D_Parser.Resolver.TypeResolution;

namespace DParserCOMServer.CodeSemantics
{
	public class TooltipGenerator
		: AbstractVDServerTask<Tuple<CodeLocation, CodeLocation, string>, int>
	{
		public TooltipGenerator(VDServer vdServer, EditorDataProvider editorDataProvider)
			: base(vdServer, editorDataProvider) { }

		protected override Tuple<CodeLocation, CodeLocation, string> Process(EditorData editorData, int flags)
		{
			bool evaluateUnderneathExpression = (flags & 1) != 0;
			bool quoteCode = (flags & 2) != 0;
			bool overloads = (flags & 4) != 0;

			// codeOffset+1 because otherwise it does not work on the first character
			// editorData.CaretOffset++;

			var sr = DResolver.GetScopedCodeObject(editorData);
			if (sr == null)
				return Tuple.Create(CodeLocation.Empty, CodeLocation.Empty, String.Empty);

			ArgumentsResolutionResult res = null;
			if (overloads)
			{
				res = ParameterInsightResolution.ResolveArgumentContext(editorData);
			}
			else
			{
				var types = LooseResolution.ResolveTypeLoosely(editorData, sr, out _, true);
				if (types != null)
				{
					res = new ArgumentsResolutionResult();
					res.ResolvedTypesOrMethods = new AbstractType[1] { types };
				}
			}

			if (editorData.CancelToken.IsCancellationRequested)
				return Tuple.Create(CodeLocation.Empty, CodeLocation.Empty, String.Empty);
			if (res == null || res.ResolvedTypesOrMethods == null)
				return Tuple.Create(sr.Location, sr.EndLocation, String.Empty);

			DNode dn = null;
			var tips = new List<Tuple<string, string>>();
			foreach (var types in res.ResolvedTypesOrMethods)
			{
				foreach (var t in AmbiguousType.TryDissolve(types))
				{
					var tipText = new StringBuilder();
					var dt = t;
					if (dt is AliasedType at)
					{
						// jump to original definition if it is not renamed or the caret is on the import
						var isRenamed = (at.Definition as ImportSymbolAlias)?.ImportBinding?.Alias != null;
						if (!isRenamed || at.Definition.Location == sr.Location)
							dt = at.Base;
					}
					tipText.Append(NodeToolTipContentGen.Instance.GenTooltipSignature(dt, false, -1, quoteCode));
					if (dt is DSymbol symbol)
						dn = symbol.Definition;

					if (evaluateUnderneathExpression)
					{
						var ctxt = editorData.GetLooseResolutionContext(LooseResolution.NodeResolutionAttempt.Normal);
						ctxt.Push(editorData);
						try
						{
							ISymbolValue v = null;
							if (dn is DVariable var && var.Initializer != null && var.IsConst)
								v = Evaluation.EvaluateValue(var.Initializer, ctxt);
							if (v == null && sr is IExpression expression)
								v = Evaluation.EvaluateValue(expression, ctxt);
							if (v != null && !(v is ErrorValue))
							{
								var valueStr = " = " + v;
								if (tipText.Length > valueStr.Length &&
									tipText.ToString(tipText.Length - valueStr.Length, valueStr.Length) != valueStr)
									tipText.Append(valueStr);
							}
						}
						catch (Exception e)
						{
							tipText.Append(" (Exception during evaluation: ").Append(e.Message).Append(")");
						}

						ctxt.Pop();
					}
					var docText = new StringBuilder();
					if (dn != null)
						VDServerCompletionDataGenerator.GenerateNodeTooltipBody(dn, docText);

					tips.Add(Tuple.Create(tipText.ToString(), docText.ToString()));
				}
			}
			var text = new StringBuilder();
			string prevDoc = "";
			bool first = true;
			foreach (var tip in tips)
			{
				// do not emit the same doc twice
				if (overloads || (tip.Item2 != "ditto" && tip.Item2 != prevDoc))
				{
					if (!string.IsNullOrEmpty(prevDoc))
						text.Append("\n").Append(prevDoc);
				}
				if (!first)
					text.Append("\a");
				first = false;
				text.Append(tip.Item1);
				if (tip.Item2 != "ditto")
					prevDoc = tip.Item2;
			}
			if (!string.IsNullOrEmpty(prevDoc))
				text.Append("\n").Append(prevDoc);

			return Tuple.Create(sr.Location, sr.EndLocation, text.ToString());
		}
	}
}