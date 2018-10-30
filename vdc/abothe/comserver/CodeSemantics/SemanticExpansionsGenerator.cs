using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Parser;

namespace DParserCOMServer.CodeSemantics
{
	public class SemanticExpansionsGenerator : AbstractVDServerTask<string, string>
	{
		public SemanticExpansionsGenerator(VDServer vdServer, EditorDataProvider editorDataProvider)
			: base(vdServer, editorDataProvider) { }

		protected override string Process(EditorData editorData, string tok)
		{
			var originalCaretLocation = editorData.CaretLocation;
			var idx = originalCaretLocation.Column - 1;
			// step	back to	beginning of identifier
			while (editorData.CaretOffset > 0 && Lexer.IsIdentifierPart(editorData.ModuleCode[editorData.CaretOffset - 1]))
			{
				editorData.CaretOffset--;
				if (idx > 0) idx--;
			}
			editorData.CaretLocation = new CodeLocation(idx + 1, originalCaretLocation.Line);

			char triggerChar = string.IsNullOrEmpty(tok) ? '\0' : tok[0];

			var cdgen = new VDServerCompletionDataGenerator(tok);
			CodeCompletion.GenerateCompletionData(editorData, cdgen, triggerChar);
			return cdgen.expansions.ToString();
		}
	}
}
