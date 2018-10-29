using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Dom.Expressions;
using D_Parser.Resolver;
using D_Parser.Resolver.ExpressionSemantics;
using D_Parser.Resolver.TypeResolution;

namespace DParserCOMServer.CodeSemantics
{
	public static class TooltipGenerator
	{
		public static Task<Tuple<CodeLocation, CodeLocation, string>> Generate(
			IEditorData editorData, bool evaluateUnderneathExpression, CancellationToken cancellationToken)
		{
			return Task.Run(() => GenerateSync(editorData, evaluateUnderneathExpression), cancellationToken);
		}

		private static Tuple<CodeLocation, CodeLocation, string> GenerateSync(
			IEditorData editorData, bool evaluateUnderneathExpression)
		{
			var sr = DResolver.GetScopedCodeObject(editorData);
			var types = LooseResolution.ResolveTypeLoosely(editorData, sr, out _, true);

			if (editorData.CancelToken.IsCancellationRequested)
				return Tuple.Create(CodeLocation.Empty, CodeLocation.Empty, String.Empty);
			if (types == null)
				return Tuple.Create(sr.Location, sr.EndLocation, String.Empty);

			var tipText = new StringBuilder();
			DNode dn = null;

			foreach (var t in AmbiguousType.TryDissolve(types))
			{
				tipText.Append(NodeToolTipContentGen.Instance.GenTooltipSignature(t));
				if (t is DSymbol symbol)
					dn = symbol.Definition;

				tipText.Append("\a");
			}

			while (tipText.Length > 0 && tipText[tipText.Length - 1] == '\a')
				tipText.Length--;

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
						var valueStr = " = " + v.ToString();
						if (tipText.Length > valueStr.Length &&
						    tipText.ToString(tipText.Length - valueStr.Length, valueStr.Length) != valueStr)
							tipText.Append(valueStr);
					}
				}
				catch (Exception e)
				{
					tipText.Append("\aException during evaluation = ").Append(e.Message);
				}

				ctxt.Pop();
			}

			if (dn != null)
				VDServerCompletionDataGenerator.GenerateNodeTooltipBody(dn, tipText);

			while (tipText.Length > 0 && tipText[tipText.Length - 1] == '\a')
				tipText.Length--;

			return Tuple.Create(sr.Location, sr.EndLocation, tipText.ToString());
		}
	}
}