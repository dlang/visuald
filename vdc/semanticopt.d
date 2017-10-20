// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.semanticopt;

version(MARS)
{
	struct TextPos
	{
		enum line = 0; // always defined
	}
}
else
{
	import vdc.semantic;
	import vdc.util;
	import vdc.versions;
}

struct VersionInfo
{
	TextPos defined;     // line -1 if not defined yet
	TextPos firstUsage;  // line int.max if not used yet
}

struct VersionDebug
{
	int level;
	VersionInfo[string] identifiers;

	bool reset(int lev, string[] ids)
	{
		if(lev == level && ids.length == identifiers.length)
		{
			bool different = false;
			foreach(id; ids)
				if(id !in identifiers)
					different = true;
			if(!different)
				return false;
		}

		level = lev;
		identifiers = identifiers.init;
		foreach(id; ids)
			identifiers[id] = VersionInfo();

		return true;
	}

	bool preDefined(string ident) const
	{
		if(auto vi = ident in identifiers)
			return vi.defined.line >= 0;
		return false;
	}

	bool defined(string ident, TextPos pos)
	{
		version(MARS)
		{
			return (ident in identifiers) != null;
		}
		else
		{
			if(auto vi = ident in identifiers)
			{
				if(pos < vi.defined)
					semanticErrorPos(pos, "identifier " ~ ident ~ " used before defined");

				if(pos < vi.firstUsage)
					vi.firstUsage = pos;

				return vi.defined.line >= 0;
			}
			VersionInfo vi;
			vi.defined.line = -1;
			vi.firstUsage = pos;
			identifiers[ident] = vi;
			return false;
		}
	}

	version(MARS) {} else
	void define(string ident, TextPos pos)
	{
		if(auto vi = ident in identifiers)
		{
			if(pos > vi.firstUsage)
				semanticErrorPos(pos, "identifier " ~ ident ~ " defined after usage");
			if(pos < vi.defined)
				vi.defined = pos;
		}

		VersionInfo vi;
		vi.firstUsage.line = int.max;
		vi.defined = pos;
		identifiers[ident] = vi;
	}
}

class Options
{
	string[] importDirs;
	string[] stringImportDirs;

	public /* debug & version handling */ {
	bool unittestOn;
	bool x64;
	bool msvcrt;
	bool debugOn;
	bool coverage;
	bool doDoc;
	bool noBoundsCheck;
	bool gdcCompiler;
	bool ldcCompiler;
	bool noDeprecated;
	bool mixinAnalysis;
	bool UFCSExpansions;
	VersionDebug debugIds;
	VersionDebug versionIds;

	int changeCount;

	bool setImportDirs(string[] dirs)
	{
		if(dirs == importDirs)
			return false;

		importDirs = dirs.dup;
		changeCount++;
		return true;
	}
	bool setStringImportDirs(string[] dirs)
	{
		if(dirs == stringImportDirs)
			return false;

		stringImportDirs = dirs.dup;
		changeCount++;
		return true;
	}
	bool setVersionIds(int level, string[] versionids)
	{
		if(!versionIds.reset(level, versionids))
			return false;
		changeCount++;
		return true;
	}
	bool setDebugIds(int level, string[] debugids)
	{
		if(!debugIds.reset(level, debugids))
			return false;
		changeCount++;
		return true;
	}

	bool versionEnabled(string ident)
	{
		int pre = versionPredefined(ident);
		if(pre == 0)
			return versionIds.defined(ident, TextPos());

		return pre > 0;
	}

	bool versionEnabled(int level)
	{
		return level <= versionIds.level;
	}

	bool debugEnabled(string ident)
	{
		return debugIds.defined(ident, TextPos());
	}

	bool debugEnabled(int level)
	{
		return level <= debugIds.level;
	}

	int versionPredefined(string ident)
	{
		version(MARS) {} else
		{
			int* p = ident in sPredefinedVersions;
			if(!p)
				return 0;
			if(*p)
				return *p;
		}

		switch(ident)
		{
			case "unittest":
				return unittestOn ? 1 : -1;
			case "assert":
				return unittestOn || debugOn ? 1 : -1;
			case "D_Coverage":
				return coverage ? 1 : -1;
			case "D_Ddoc":
				return doDoc ? 1 : -1;
			case "D_NoBoundsChecks":
				return noBoundsCheck ? 1 : -1;
			case "Win32":
			case "X86":
			case "D_InlineAsm_X86":
				return x64 ? -1 : 1;
			case "CRuntime_DigitalMars":
				return msvcrt ? -1 : 1;
			case "CRuntime_Microsoft":
				return msvcrt ? 1 : -1;
			case "MinGW":
				return gdcCompiler || (ldcCompiler && !msvcrt) ? 1 : -1;
			case "Win64":
			case "X86_64":
			case "D_InlineAsm_X86_64":
			case "D_LP64":
				return x64 ? 1 : -1;
			case "GNU":
				return gdcCompiler ? 1 : -1;
			case "LDC":
				return ldcCompiler ? 1 : -1;
			case "DigitalMars":
				return gdcCompiler || ldcCompiler ? -1 : 1;
			default:
				assert(false, "inconsistent predefined versions");
		}
	}

	}
}

