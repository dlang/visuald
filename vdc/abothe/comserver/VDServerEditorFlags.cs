using System;

namespace DParserCOMServer
{
	[Flags]
	public enum VDServerEditorFlags:uint
	{
		Unittest = 1,
		DebugAssert = 2,
		x64 = 4,
		Coverage = 8,
		DDoc = 16,
		NoBoundsCheck = 32,
		GNU = 64,
		LDC = 0x4000000,
		CRuntime_Microsoft = 0x8000000,
		/// <summary>
		/// GNU or LDC
		/// </summary>
		CRuntime_MinGW = 0x4000040,
		ShowUFCSItems = 0x2000000,
		EnableMixinAnalysis = 0x1000000,
		HideDeprecatedNodes = 128
	}
}