using System.Text;
using D_Parser.Completion.ToolTips;

namespace DParserCOMServer
{
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
}