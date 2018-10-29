using System;

namespace DParserCOMServer
{
	[Flags]
	public enum VDServerEditorFlags:uint
	{
		[Obsolete]
		Unittest = 1,
		[Obsolete]
		DebugAssert = 2,
		[Obsolete]
		x64 = 4,
		[Obsolete]
		Coverage = 8,
		[Obsolete]
		DDoc = 16,
		[Obsolete]
		NoBoundsCheck = 32,
		[Obsolete]
		GNU = 64,
		[Obsolete]
		LDC = 0x4000000,
		[Obsolete]
		CRuntime_Microsoft = 0x8000000,
		/// <summary>
		/// GNU or LDC
		/// </summary>
		[Obsolete]
		CRuntime_MinGW = 0x4000040,
		ShowUFCSItems = 0x2000000,
		EnableMixinAnalysis = 0x1000000,
		HideDeprecatedNodes = 128
	}
}