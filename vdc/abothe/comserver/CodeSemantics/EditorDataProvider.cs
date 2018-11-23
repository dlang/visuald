using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
		private uint _modificationCount;

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

		public uint ModificationCount()
		{
			return _modificationCount;
		}

		public void ConfigureEnvironment(
			string importLines,
			string versionIdLines,
			string debugIdLines,
			uint flags)
		{
			var uniqueImports = uniqueDirectories(importLines);

			var versionIds = string.IsNullOrWhiteSpace(versionIdLines) ? new string[0]
				: versionIdLines.Split(newlineSeparator, StringSplitOptions.RemoveEmptyEntries);
			var debugIds = string.IsNullOrWhiteSpace(debugIdLines) ? new string[0]
				: debugIdLines.Split(newlineSeparator, StringSplitOptions.RemoveEmptyEntries);

			var isDebug = (flags & 2) != 0;
			var debugLevel = (flags >> 16) & 0xff;
			var versionNumber = (flags >> 8) & 0xff;

			if (_cacheView == null ||
				!(_cacheView as VDserverParseCacheView).PackageRootDirs.SequenceEqual(uniqueImports) ||
				isDebug != _isDebug || debugLevel != _debugLevel || versionNumber != _versionNumber ||
				!versionIds.SequenceEqual(_versionIds) || !debugIds.SequenceEqual(debugIds))
			{
				_cacheView = new VDserverParseCacheView(uniqueImports);
				_isDebug = isDebug;
				_debugLevel = debugLevel;
				_versionNumber = versionNumber;
				_versionIds = versionIds;
				_debugIds = debugIds;
				_modificationCount++;
			}

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

	}
}