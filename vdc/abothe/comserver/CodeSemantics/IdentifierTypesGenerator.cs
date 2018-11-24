using System;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Dom.Expressions;
using D_Parser.Refactoring;

namespace DParserCOMServer.CodeSemantics
{
	public class IdentifierTypesGenerator
		: AbstractVDServerTask<string, Tuple<int, bool>>
	{
		public IdentifierTypesGenerator(VDServer vdServer, EditorDataProvider editorDataProvider)
			: base(vdServer, editorDataProvider) { }

		protected override string Process(
			EditorData editorData, Tuple<int, bool> args)
		{
			int endLine = args.Item1;
			bool resolveTypes = args.Item2;

			try
			{
				var invalidCodeRegions = new List<ISyntaxRegion>();
				var textLocationsToHighlight =
					TypeReferenceFinder.Scan(editorData, editorData.CancelToken, resolveTypes, invalidCodeRegions);
				return TextLocationsToIdentifierSpans(textLocationsToHighlight);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message); // Log the error
				return null;
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
				case IdentifierExpression identifierExp:
					return identifierExp.StringValue;
				default:
					return "";
			}
		}

		struct TextSpan
		{
			public CodeLocation start;
			public TypeReferenceKind kind;
		};

		class TypeReferenceLocationComparer : Comparer<KeyValuePair<ISyntaxRegion, TypeReferenceKind>>
		{
			public override int Compare(KeyValuePair<ISyntaxRegion, TypeReferenceKind> x,
										KeyValuePair<ISyntaxRegion, TypeReferenceKind> y)
			{
				if (x.Key.Location == y.Key.Location)
					return 0;
				return x.Key.Location < y.Key.Location ? -1 : 1;
			}
		}
		private static TypeReferenceLocationComparer locComparer = new TypeReferenceLocationComparer();

		class TypeReferenceLineComparer : Comparer<KeyValuePair<int, Dictionary<ISyntaxRegion, TypeReferenceKind>>>
		{
			public override int Compare(KeyValuePair<int, Dictionary<ISyntaxRegion, TypeReferenceKind>> x,
										KeyValuePair<int, Dictionary<ISyntaxRegion, TypeReferenceKind>> y)
			{
				if (x.Key == y.Key)
					return 0;
				return x.Key < y.Key ? -1 : 1;
			}
		}
		private static TypeReferenceLineComparer lineComparer = new TypeReferenceLineComparer();


		static string TextLocationsToIdentifierSpans(Dictionary<int, Dictionary<ISyntaxRegion, TypeReferenceKind>> textLocations)
		{
			if (textLocations == null)
				return null;

			var textLocArray = textLocations.ToArray();
			Array.Sort(textLocArray, lineComparer);
			var identifierSpans = new Dictionary<string, List<TextSpan>>();
			KeyValuePair<ISyntaxRegion, TypeReferenceKind>[] smallArray = new KeyValuePair<ISyntaxRegion, TypeReferenceKind>[1];

			foreach (var kv in textLocArray)
			{
				var line = kv.Key;
				KeyValuePair<ISyntaxRegion, TypeReferenceKind>[] columns;
				if (kv.Value.Count() == 1)
				{
					smallArray[0] = kv.Value.First();
					columns = smallArray;
				}
				else
				{
					columns = kv.Value.ToArray();
					Array.Sort(columns, locComparer);
				}
				foreach (var kvv in columns)
				{
					var sr = kvv.Key;
					var ident = GetIdentifier(sr);
					if (string.IsNullOrEmpty(ident))
						continue;

					if (!identifierSpans.TryGetValue(ident, out var spans))
						spans = identifierSpans[ident] = new List<TextSpan>();

					else if (spans.Last().kind == kvv.Value)
						continue;

					var span = new TextSpan { start = sr.Location, kind = kvv.Value };
					spans.Add(span);
				}
			}
			var s = new StringBuilder();
			foreach (var idv in identifierSpans)
			{
				s.Append(idv.Key).Append(':').Append(((byte)idv.Value.First().kind).ToString());
				foreach (var span in idv.Value.GetRange(1, idv.Value.Count - 1))
				{
					s.Append($";{(byte)span.kind},{span.start.Line},{span.start.Column - 1}");
				}
				s.Append('\n');
			}
			return s.ToString();
		}
	}
}