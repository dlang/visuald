using System;
using System.Collections.Generic;
using System.IO;
using D_Parser.Completion;
using D_Parser.Misc;

namespace DParserCOMServer.CodeSemantics
{
	public class EditorDataProvider
	{
		private VDserverParseCacheView _cacheView;
		private string[] _versionIds;
		private string[] _debugIds;
		private bool _isDebug;
		private uint _debugLevel;
		private uint _versionNumber;

		private static readonly char[] newlineSeparator = { '\n' };

		public EditorData MakeEditorData()
		{
			var editorData = new EditorData
			{
				ParseCache = _cacheView,
				IsDebug = _isDebug,
				DebugLevel = _debugLevel,
				VersionNumber = _versionNumber,
				GlobalDebugIds = _debugIds,
				GlobalVersionIds = _versionIds
			};
			editorData.NewResolutionContexts();
			return editorData;
		}

		public void ConfigureEnvironment(
			string importLines,
			string versionIdLines,
			string debugIdLines,
			uint flags)
		{
			_cacheView = new VDserverParseCacheView(uniqueDirectories(importLines));

			var versionIds = string.IsNullOrWhiteSpace(versionIdLines) ? new HashSet<string>()
				: new HashSet<string>(versionIdLines.Split(newlineSeparator, StringSplitOptions.RemoveEmptyEntries));
			setupVersionIds(versionIds, flags);
			_versionIds = new string[versionIds.Count];
			versionIds.CopyTo(_versionIds);
			_debugIds = string.IsNullOrWhiteSpace(debugIdLines) ? new string[0]
				: debugIdLines.Split(newlineSeparator, StringSplitOptions.RemoveEmptyEntries);

			_isDebug = (flags & 2) != 0;
			_debugLevel = (flags >> 16) & 0xff;
			_versionNumber = (flags >> 8) & 0xff;

			CompletionOptions.Instance.ShowUFCSItems = (flags & 0x2000000) != 0;
			CompletionOptions.Instance.DisableMixinAnalysis = (flags & 0x1000000) == 0;
			CompletionOptions.Instance.HideDeprecatedNodes = (flags & 128) != 0;
			CompletionOptions.Instance.CompletionTimeout = -1; // 2000;
		}

		public static string normalizePath(string path)
		{
			path = Path.GetFullPath(path);
			return path.ToLower();
		}

		public static string normalizeDir(string dir)
		{
			dir = normalizePath(dir);
			if (dir.Length != 0 && dir[dir.Length - 1] != Path.DirectorySeparatorChar)
				dir += Path.DirectorySeparatorChar;
			return dir;
		}

		public static string[] uniqueDirectories(string imp)
		{
			var impDirs = imp.Split(newlineSeparator, StringSplitOptions.RemoveEmptyEntries);
			string[] normDirs = new string[impDirs.Length];
			for (int i = 0; i < impDirs.Length; i++)
				normDirs[i] = normalizeDir(impDirs[i]);

			string[] uniqueDirs = new string[impDirs.Length];
			int unique = 0;
			for (int i = 0; i < normDirs.Length; i++)
			{
				int j;
				for (j = 0; j < normDirs.Length; j++)
					if (i != j && normDirs[i].StartsWith(normDirs[j]))
						if (normDirs[i] != normDirs[j] || j < i)
							break;
				if (j >= normDirs.Length)
					uniqueDirs[unique++] = normDirs[i];
			}

			Array.Resize(ref uniqueDirs, unique);
			return uniqueDirs;
		}

		static void setupVersionIds(HashSet<String> versions, uint flags)
		{
			versions.Add("Windows");
			versions.Add("LittleEndian");
			versions.Add("D_HardFloat");
			versions.Add("all");
			versions.Add("D_Version2");
			if ((flags & 1) != 0)
				versions.Add("unittest");
			if ((flags & 2) != 0)
				versions.Add("assert");
			if ((flags & 4) != 0)
			{
				versions.Add("Win64");
				versions.Add("X86_64");
				versions.Add("D_InlineAsm_X86_64");
				versions.Add("D_LP64");
			}
			else
			{
				versions.Add("Win32");
				versions.Add("X86");
				versions.Add("D_InlineAsm_X86");
			}
			if ((flags & 8) != 0)
				versions.Add("D_Coverage");
			if ((flags & 16) != 0)
				versions.Add("D_Ddoc");
			if ((flags & 32) != 0)
				versions.Add("D_NoBoundsChecks");
			if ((flags & 64) != 0)
				versions.Add("GNU");
			else if ((flags & 0x4000000) != 0)
				versions.Add("LDC");
			else
				versions.Add("DigitalMars");
			if ((flags & 0x8000000) != 0)
				versions.Add("CRuntime_Microsoft");
			else if ((flags & 0x4000040) != 0) // GNU or LDC
				versions.Add("CRuntime_MinGW");
			else
				versions.Add("CRuntime_DigitalMars");
		}
	}
}