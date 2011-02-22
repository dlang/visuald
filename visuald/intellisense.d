// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module intellisense;

import std.json;
import std.file;
import std.utf;
import std.date;
import std.conv;
import std.string;
import std.algorithm;
import std.regex;

import core.memory;
import windows;

import sdk.port.vsi;
import sdk.vsi.vsshell;

import dpackage;
import config;
import comutil;
import logutil;
import hierutil;
import fileutil;
import simplelexer;

enum MatchType
{
	Exact,
	CaseInsensitive,
	StartsWith,
	RegExp
}

struct SearchData
{
	string[] names;
	Regex!char[] res;

	enum
	{ 
		kFieldName = 1 << 0,
		kFieldType = 1 << 1,
		kFieldScope = 1 << 2
	}
	
	ubyte searchFields = kFieldName;
	bool wholeWord;
	bool caseSensitive;
	bool useRegExp;
	bool noDupsOnSameLine;
	bool findQualifiedName;

	bool init(string[] nms)
	{
		try
		{
			if(useRegExp)
				foreach(string nm; nms)
					res ~= regex(nm, caseSensitive ? "" : "i");
			else
				names = nms;
		}
		catch(Exception)
		{
			return false;
		}
		return true;
	}

	string getQualifiedName(JSONscope *sc, JSONValue[string] obj)
	{
		string name;
		if(JSONValue* n = "name" in obj)
			if(n.type == JSON_TYPE.STRING)
				name = n.str;
		
		string scname = sc.toString();
		if(JSONValue* n = "kind" in obj)
			if(n.type == JSON_TYPE.STRING)
				if(n.str == "module")
					name = "";
		
		if(name.length == 0)
			name = scname;
		else if (scname.length != 0)
			name = scname ~ "." ~ name;
		return name;
	}
	
	bool matchDefinition(JSONscope *sc, JSONValue[string] obj)
	{
		if(findQualifiedName && names.length > 0)
			return sc.toString() == names[0];
		
		if((!useRegExp && names.length == 0) || (useRegExp && res.length == 0))
			return true;
		
		string name, type, inScope;
		if(searchFields & kFieldName)
			if(JSONValue* n = "name" in obj)
				if(n.type == JSON_TYPE.STRING)
					name = caseSensitive ? n.str : tolower(n.str);
		
		if(searchFields & kFieldType)
			if(JSONValue* typ = "type" in obj)
				if(typ.type == JSON_TYPE.STRING)
					type = caseSensitive ? typ.str : tolower(typ.str);

		if(searchFields & kFieldScope)
			inScope = sc ? (caseSensitive ? sc.toString() : tolower(sc.toString())) : "";
		
		return matchNames(name, type, inScope);
	}

	bool pruneSubtree(JSONscope *sc, JSONValue[string] obj)
	{
		if(findQualifiedName && names.length > 0)
		{
			string name = sc.toString();
			return !startsWith(names[0], name);
		}
		return false;
	}
	
	static bool isIdentChar(dchar ch)
	{
		return isalnum(ch) || ch == '_';
	}
	static bool isWordBoundary(dchar ch1, dchar ch2)
	{
		return !isIdentChar(ch1) || !isIdentChar(ch2);
	}

	bool matchNames(string name, string type, string inScope)
	{
		bool matches = false;
		if(useRegExp)
		{
			bool matchRegex(string txt, Regex!char re)
			{
				auto m = match(name, re);
				if(m.empty() || m.hit.length == 0)
					return false;
				if(!wholeWord)
					return true;
				foreach(mx; m)
					if((mx.pre.length == 0 || isWordBoundary(mx.pre[$-1], mx.hit[0])) &&
					   (mx.post.length == 0 || isWordBoundary(mx.post[0], mx.hit[$-1])))
						return true;
				return false;
			}
			
			for(int i = 0; i < res.length; i++)
			{
				if(searchFields & kFieldName)
					if(matchRegex(name, res[i]))
						continue;
				if(searchFields & kFieldType)
					if(matchRegex(type, res[i]))
						continue;
				if(searchFields & kFieldScope)
					if(matchRegex(inScope, res[i]))
						continue;
				return false;
			}
		}
		else
		{
			bool matchString(string txt, string str)
			{
				CaseSensitive cs = caseSensitive ? CaseSensitive.yes : CaseSensitive.no;
				int pos = 0;
				int p = pos + indexOf(name[pos..$], str, cs);
				while(p >= pos)
				{
					if(!wholeWord)
						return true;
					
					if((p == 0 || isWordBoundary(txt[p-1], txt[0])) &&
					   (p + str.length >= txt.length || isWordBoundary(txt[p + str.length - 1], txt[p + str.length])))
						return true;
					
					pos = p + 1;
					p = pos + indexOf(name[pos..$], str, cs);
				}
				return false;
			}
			
			for(int i = 0; i < names.length; i++)
			{
				if(searchFields & kFieldName)
					if(matchString(name, names[i]))
						continue;
				if(searchFields & kFieldType)
					if(matchString(type, names[i]))
						continue;
				if(searchFields & kFieldScope)
					if(matchString(inScope, names[i]))
						continue;
				return false;
			}
		}
		return true;
	}
}

struct JSONscope
{
	JSONscope* parent;
	string name;
	
	string toString()
	{
		string nm = name;
		if(parent && nm.length > 0)
			nm = parent.toString() ~ "." ~ nm;
		else if(parent)
			nm = parent.toString();
		return nm;
	}
}
	
class LibraryInfo
{
	bool readJSON(string fileName)
	{
		try
		{
			string text = cast(string) std.file.read(fileName);
			size_t decidx = 0;
			if(decode(text, decidx) == 0xfeff)
				text = text[decidx..$];

			mModules = parseJSON(text);
			mFilename = fileName;
			mModified = lastModified(fileName);
			return true;
		}
		catch(JSONException rc)
		{
			string msg = rc.toString();
			logCall("EXCEPTION: " ~ msg);
		} 
		catch(FileException rc)
		{
			string msg = rc.toString();
			logCall("EXCEPTION: " ~ msg);
		}
		return false;
	}

	// dg_match returns:
	// 0 - continue search
	// 1 - stop search
	// 2 - continue search, but prune subtree
	bool iterateObjects(int delegate(string filename, JSONscope* sc, JSONValue[string] object) dg_match)
	{
		if(mModules.type == JSON_TYPE.ARRAY)
		{
			JSONValue[] modules = mModules.array;
			foreach(JSONValue mod; modules)
			{
				if(mod.type == JSON_TYPE.OBJECT)
				{
					string filename;
					string modname;
					JSONValue[string] object = mod.object;
					if(JSONValue* v = "file" in object)
						if(v.type == JSON_TYPE.STRING)
							filename = v.str;
					if(JSONValue* v = "name" in object)
						if(v.type == JSON_TYPE.STRING)
							modname = v.str;
					
					int iterate(JSONValue[string] object, JSONscope* sc)
					{
						int res = dg_match(filename, sc, object);
						if(res == 1)
							return 1;
						if(res == 2)
							return 0;
						
						if(JSONValue* m = "members" in object)
							if(m.type == JSON_TYPE.ARRAY)
							{
								JSONValue[] members = m.array;
								foreach(member; members)
								{
									if(member.type == JSON_TYPE.OBJECT)
									{
										string nm;
										JSONValue[string] memberobj = member.object;
										if(JSONValue* n = "name" in memberobj)
											if(n.type == JSON_TYPE.STRING)
												nm = n.str;
										JSONscope msc = JSONscope(sc, nm);
										
										res = iterate(memberobj, &msc);
										if(res > 0)
											return res;
									}
								}
							}

						return 0;
					}
				
					JSONscope sc = JSONscope(null, modname);
					if(iterate(object, &sc))
						return true;
				}
			}
		}
		return false;
	}

	Definition[] findDefinition(ref SearchData sd)
	{
		Definition[] defs;

		//GC.disable();
		
	debug(FINDDEF) {
		int cnt = 0;
		int cntKind = 0;
		int cntLine = 0;
		int cntType = 0;
		int countDef(string filename, JSONscope* sc, JSONValue[string] memberobj)
		{
			if(sd.pruneSubtree(sc, memberobj))
				return 2;
			if(sd.matchDefinition(sc, memberobj))
			{
				if(JSONValue* n = "name" in memberobj)
					if(n.type == JSON_TYPE.STRING)
						cnt++;
				if(JSONValue* k = "kind" in memberobj)
					if(k.type == JSON_TYPE.STRING)
						cntKind++;
				if(JSONValue* ln = "line" in memberobj)
					if(ln.type == JSON_TYPE.INTEGER)
						cntLine++;
				if(JSONValue* typ = "type" in memberobj)
					if(typ.type == JSON_TYPE.STRING)
						cntType++;
			}
			return 0;
		}
		iterateObjects(&countDef);
	}
		
		int findDef(string filename, JSONscope* sc, JSONValue[string] memberobj)
		{
			if(sd.pruneSubtree(sc, memberobj))
				return 2;
			if(sd.matchDefinition(sc, memberobj))
			{
				Definition def;
				def.filename = filename;
				def.inScope = sc ? sc.toString() : "";
				
				if(JSONValue* n = "name" in memberobj)
					if(n.type == JSON_TYPE.STRING)
						def.name = n.str;
				if(JSONValue* k = "kind" in memberobj)
					if(k.type == JSON_TYPE.STRING)
						def.kind = k.str;
				if(JSONValue* ln = "line" in memberobj)
					if(ln.type == JSON_TYPE.INTEGER)
						def.line = cast(int)ln.integer - 1;
				if(JSONValue* typ = "type" in memberobj)
					if(typ.type == JSON_TYPE.STRING)
						def.type = typ.str;
				
				bool add = true;
				if(sd.noDupsOnSameLine)
				{
					foreach(d; defs)
						if(d.filename == def.filename && d.line == def.line)
							add = false;
				}
				if(add)
					defs ~= def;
			}
			return 0;
		}
		
		iterateObjects(&findDef);
		
		//GC.enable();
		return defs;
	}

	string[] findCompletions(ref SearchData sd)
	{
		string[] cplts;

		int findCplt(string filename, JSONscope* sc, JSONValue[string] memberobj)
		{
			if(JSONValue* n = "name" in memberobj)
				if(n.type == JSON_TYPE.STRING)
					if(startsWith(n.str, sd.names[0]))
						addunique(cplts, n.str);
			return 0;
		}
		iterateObjects(&findCplt);
		
		return cplts;
	}

	JSONValue mModules;
	string mFilename;
	std.date.d_time mModified;
}

struct ParameterInfo
{
	string rettype;
	string[] name;
	string[] display;
	string[] desc;
	
	bool initialize(string type)
	{
		wstring text = to!wstring(type);
		TokenInfo[] lineInfo = ScanLine(SimpleLexer.State.kWhite, text);
		
		if(lineInfo.length == 0)
			return false;
		int pos = lineInfo.length - 1;
		if(text[lineInfo[pos].StartIndex .. lineInfo[pos].EndIndex] != ")")
			return false; // not a function
		
		int braceLevel = 1;
		pos--;
		string ident;
		int endpos = lineInfo[pos].EndIndex;

		void prependParam()
		{
			wstring wdisp = text[lineInfo[pos].EndIndex .. endpos];
			string disp = strip(to!string(wdisp));
			if(disp.length)
			{
				name = ident ~ name;
				display = disp ~ display;
				desc = "" ~ desc;
				ident = "";
			}
			endpos = lineInfo[pos].StartIndex;
		}
		
		while(pos > 0 && braceLevel > 0)
		{
			wstring tok = text[lineInfo[pos].StartIndex .. lineInfo[pos].EndIndex];
			if(ident.length == 0 && lineInfo[pos].type == TokenColor.Identifier)
				ident = to!string(tok);
			else if (tok == ",")
				prependParam();
			else if(tok == ")")
				braceLevel++;
			else if(tok == "(")
			{
				braceLevel--;
				if(braceLevel == 0)
					prependParam();
			}
			pos--;
		}
		
		wstring wret = text[0 .. endpos];
		rettype = strip(to!string(wret));
		return braceLevel == 0;
	}
}

struct Definition
{
	string name;
	string kind;
	string filename;
	string type;
	int line;

	string inScope; // enclosing scope

	ParameterInfo* paramInfo;
	ParameterInfo* GetParamInfo()
	{
		if(!paramInfo)
		{
			paramInfo = new ParameterInfo;
			paramInfo.initialize(type);
		}
		return paramInfo;
	}		
	
	string GetReturnType() 
	{
		return GetParamInfo().rettype;
	}
	
	int GetParameterCount() 
	{
		return GetParamInfo().name.length;
	}
	
	void GetParameterInfo(int parameter, out string name, out string display, out string description)
	{
		ParameterInfo* info = GetParamInfo();
		if(parameter < 0 || parameter >= info.name.length)
			return;
		
		name = info.name[parameter];
		display = info.display[parameter];
		description = info.desc[parameter];
	}
}

class LibraryInfos
{
	this()
	{
//		auto info = new LibraryInfo;
//		info.readJSON(r"m:\s\d\visuald\trunk\bin\Debug\visuald.json");
//		mInfos ~= info;
	}

	string[] findJSONFiles()
	{
		string[] files = Package.GetGlobalOptions().getJSONFiles();
		
		auto srpSolution = queryService!(IVsSolution);
		scope(exit) release(srpSolution);
		auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
		scope(exit) release(solutionBuildManager);

		if(srpSolution && solutionBuildManager)
		{
			IEnumHierarchies pEnum;
			if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION|EPF_MATCHTYPE, &g_projectFactoryCLSID, &pEnum) == S_OK)
			{
				scope(exit) release(pEnum);
				IVsHierarchy pHierarchy;
				while(pEnum.Next(1, &pHierarchy, null) == S_OK)
				{
					scope(exit) release(pHierarchy);
					IVsProjectCfg activeCfg;
					if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
					{
						scope(exit) release(activeCfg);
						if(Config cfg = qi_cast!Config(activeCfg))
						{
							scope(exit) release(cfg);
							cfg.addJSONFiles(files);
						}
					}
				}
			}
		}
		return files;
	}

	void updateDefinitions()
	{
		string[] files = findJSONFiles();
		
		// remove files no longer found and update modified files
		for(int i = 0; i < mInfos.length; )
		{
			int idx = arrIndex(files, mInfos[i].mFilename);
			if(idx < 0)
				mInfos = mInfos[0 .. i] ~ mInfos[i+1 .. $];
			else
			{
				files = files[0 .. idx] ~ files[idx+1 .. $];
				if(mInfos[i].mModified != lastModified(mInfos[i].mFilename))
					mInfos[i].readJSON(mInfos[i].mFilename);
				i++;
			}
		}
		
		// add new files
		foreach(file; files)
		{
			auto info = new LibraryInfo;
			if(info.readJSON(file))
				mInfos ~= info;
		}
		
		debug(FINDDEF) findDefinition("");
	}
	
	string[] findCompletions(string name, bool caseSensitive)
	{
		SearchData sd;
		sd.caseSensitive = caseSensitive;
		if(name.length)
			sd.names ~= name;
		
		string[] completions;
		foreach(info; mInfos)
			completions ~= info.findCompletions(sd);
		return completions;
	}
	
	Definition[] findDefinition(string name)
	{
		SearchData sd;
		sd.wholeWord = true;
		sd.caseSensitive = true;
		sd.noDupsOnSameLine = true;
		if(name.length)
			sd.names ~= name;
		return findDefinition(sd);
	}
	
	Definition[] findDefinition(ref SearchData sd)
	{
		Definition[] defs;
		foreach(info; mInfos)
			defs ~= info.findDefinition(sd);
		return defs;
	}

	LibraryInfo[] mInfos;

}
