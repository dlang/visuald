using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Parser;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace DParserCOMServer
{
	class VDServerCompletionDataGenerator : ICompletionDataGenerator
	{
		public VDServerCompletionDataGenerator(string pre)
		{
			if (pre.EndsWith("*"))
			{
				prefix = pre.Substring(0, pre.Length - 1);
				exact = false;
			}
			else 
			{
				prefix = pre;
				exact = true;
			}
		}

		public void NotifyTimeout()
		{

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

		class NodeTypeNameVisitor : NodeVisitor<string>
		{
			const string InvalidType = "I";
			const string TemplateType = "TMPL";

			public static readonly NodeTypeNameVisitor Instance = new NodeTypeNameVisitor();

			public string Visit(DEnumValue dEnumValue)
			{
				return "EVAL";
			}

			public string Visit(DVariable dVariable)
			{
                if (dVariable.IsAlias)
                    return "ALIA";
                if (dVariable.IsStaticProperty)
                    return "SPRP";
				return "VAR";
			}

			public string Visit(DMethod n)
			{
				if (n.ContainsPropertyAttribute(BuiltInAtAttribute.BuiltInAttributes.Property))
					return "PROP";
				if (n.Parent is DClassLike)
					return "MTHD";
				else
					return "FUNC";
			}

			public string Visit(DClassLike dClassLike)
			{
				switch (dClassLike.ClassType)
				{
					case DTokens.Struct:
						return "STRU";
					default:
						return "CLSS";
					case DTokens.Interface:
						return "IFAC";
					case DTokens.Template:
						return TemplateType;
					case DTokens.Union:
						return "UNIO";
				}
			}

			public string Visit(DEnum dEnum)
			{
				return "ENUM";
			}

			public string Visit(DModule dModule)
			{
				return "MOD";
			}

			public string Visit(DBlockNode dBlockNode)
			{
				return InvalidType;
			}

			public string Visit(TemplateParameter.Node templateParameterNode)
			{
				return TemplateType; // ? or a more special type ?
			}

			public string Visit(NamedTemplateMixinNode n)
			{
				return "NMIX";
			}

			public string Visit(EponymousTemplate ep)
			{
				return TemplateType;
			}

			public string Visit(ModuleAliasNode moduleAliasNode)
			{
				return "MOD";
			}

			public string Visit(ImportSymbolNode importSymbolNode)
			{
				return "VAR";
			}

			public string Visit(ImportSymbolAlias importSymbolAlias)
			{
                return "ALIA";
			}

			#region Not needed
			public string VisitAttribute(Modifier attr)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(DeprecatedAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(PragmaAttribute attr)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(BuiltInAtAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(UserDeclarationAttribute a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(VersionCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(DebugCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(StaticIfCondition a)
			{
				throw new NotImplementedException();
			}

			public string VisitAttribute(NegatedDeclarationCondition a)
			{
				throw new NotImplementedException();
			}
			#endregion
		}

		public void SetSuggestedItem(string item) { }

		/// <summary>
		/// Adds a node to the completion data
		/// </summary>
		/// <param name="Node"></param>
		public void Add(INode Node)
		{
			if (Node.NameHash == 0)
				return;
			var name = Node.Name;
            if (!nameMatches(name))
				return;

			var sb = new StringBuilder(NodeToolTipContentGen.Instance.GenTooltipSignature(Node as DNode));

			GenerateNodeTooltipBody(Node as DNode, sb);

			addExpansion(name, Node.Accept(NodeTypeNameVisitor.Instance), sb.ToString());
		}

		public static void GenerateNodeTooltipBody(DNode Node, StringBuilder sb)
		{
			Dictionary<string, string> cats;
			string summary;
			NodeToolTipContentGen.Instance.GenToolTipBody(Node, out summary, out cats);

			if (!string.IsNullOrEmpty(summary) || (cats != null && cats.Count > 0))
				sb.Append("\n");

			if (!string.IsNullOrEmpty(summary))
				sb.Append(summary);

			if (cats != null)
			{
				foreach (var kv in cats)
				{
					sb.Append("\n<b>").Append(kv.Key).Append("</b>\n");
					sb.Append(kv.Value);
				}
			}
		}

		/// <summary>
		/// Adds a module (name stub) to the completion data
		/// </summary>
		/// <param name="ModuleName"></param>
		/// <param name="AssocModule"></param>
		public void AddModule(DModule module, string nameOverride)
		{
			if (string.IsNullOrEmpty(nameOverride))
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
            if (iconName == "md-keyword")
			    addExpansion(text, "ASKW", description);
            else
                addExpansion(text, "ASOP", description);
		}

		void addExpansion(string name, string type, string desc)
		{
            if (nameMatches(name))
			{
				expansions.Append(name.Replace("\r", string.Empty).Replace('\n', '\a')).Append(':').Append(type).Append(':');
				expansions.Append(desc.Replace("\r", string.Empty).Replace('\n', '\a')).Append('\n');
			}
		}

        bool nameMatches(string name)
        {
            if (name == null)
                return false;
            if (exact)
                return name.StartsWith(prefix);
            else
                return name.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0;
        }

		public readonly StringBuilder expansions = new StringBuilder();
		string prefix;
        bool exact;
	}
}
