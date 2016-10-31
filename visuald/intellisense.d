// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.intellisense;

import std.json;
import std.file;
import std.utf;
import std.datetime;
import std.conv;
import std.string;
import std.algorithm;

import std.regex;
import std.array;
import std.path : baseName, stripExtension;
//import stdext.fred;

import stdext.path;
import stdext.array;

import core.memory;
import core.demangle;
import visuald.windows;

import sdk.port.vsi;
import sdk.vsi.vsshell;

import visuald.dpackage;
import visuald.dlangsvc;
import visuald.config;
import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.pkgutil;
import visuald.stringutil;

import vdc.lexer;

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
		kFieldScope = 1 << 2,
		kFieldDeco = 1 << 3,
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
		
		string name, type, deco, inScope;
		if(searchFields & kFieldName)
			if(JSONValue* n = "name" in obj)
				if(n.type == JSON_TYPE.STRING)
					name = caseSensitive ? n.str : toLower(n.str);
		
		if(searchFields & kFieldType)
			if(JSONValue* typ = "type" in obj)
				if(typ.type == JSON_TYPE.STRING)
					type = caseSensitive ? typ.str : toLower(typ.str);

		if(searchFields & kFieldDeco)
			if(JSONValue* dec = "deco" in obj)
				if(dec.type == JSON_TYPE.STRING)
					deco = caseSensitive ? dec.str : toLower(dec.str);

		if(searchFields & kFieldScope)
			inScope = sc ? (caseSensitive ? sc.toString() : toLower(sc.toString())) : "";
		
		return matchNames(name, type, deco, inScope);
	}

	bool matchDefinition(BrowseNode node)
	{
		if(findQualifiedName && names.length > 0)
			return node.GetScope() == names[0];
		
		if((!useRegExp && names.length == 0) || (useRegExp && res.length == 0))
			return true;
		
		string name, type, deco, inScope;
		if(searchFields & kFieldName)
			name = caseSensitive ? node.name : toLower(node.name);
		
		if(searchFields & kFieldType)
			type = caseSensitive ? node._type : toLower(node._type);

		if(searchFields & kFieldDeco)
			deco = caseSensitive ? node.deco : toLower(node.deco);

		if(searchFields & kFieldScope)
			inScope = caseSensitive ? node.GetScope() : toLower(node.GetScope());
		
		return matchNames(name, type, deco, inScope);
	}

	void addDefinition(ref Definition[] defs, ref Definition def)
	{
		bool add = true;
		if(noDupsOnSameLine)
		{
			foreach(d; defs)
				if(d.filename == def.filename && d.line == def.line)
					add = false;
		}
		if(add)
			defs ~= def;
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
	
	bool pruneSubtree(BrowseNode node)
	{
		if(findQualifiedName && names.length > 0)
		{
			string name = node.GetScope();
			return !startsWith(names[0], name);
		}
		return false;
	}
	
	static bool isIdentChar(dchar ch)
	{
		return dLex.isIdentifierCharOrDigit(ch);
	}
	static bool isWordBoundary(dchar ch1, dchar ch2)
	{
		return !isIdentChar(ch1) || !isIdentChar(ch2);
	}

	bool matchNames(string name, string type, string deco, string inScope)
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
				if(searchFields & kFieldDeco)
					if(matchRegex(deco, res[i]))
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
				int p = pos + indexOfPath(name[pos..$], str, cs);
				while(p >= pos)
				{
					if(!wholeWord)
						return true;
					
					if((p == 0 || isWordBoundary(txt[p-1], txt[0])) &&
					   (p + str.length >= txt.length || isWordBoundary(txt[p + str.length - 1], txt[p + str.length])))
						return true;
					
					pos = p + 1;
					p = pos + indexOfPath(name[pos..$], str, cs);
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
				if(searchFields & kFieldDeco)
					if(matchString(deco, names[i]))
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

// filter out stuff written by dmd 2.062alpha
bool isDeclarationKind(string kind)
{
	switch(kind)
	{
		case "import":
		case "static import":
		case "alias this":
		case "static assert":
		case "template instance":
		case "mixin":
			return false;
		default:
			return true;
	}
}

string demangleType(string type, string name)
{
	string sym = "_D7__Sym__" ~ type;
	string s = cast(string) demangle(sym);
	if(s == sym) // cannot demangle
		return type;
	s = s.replace("__Sym__", "");
	return s;
}

void getDeclarationInfo(D)(D def, JSONValue[string] obj)
{
	if(JSONValue* n = "name" in obj)
		if(n.type == JSON_TYPE.STRING)
			def.name = n.str;

	if(JSONValue* ln = "line" in obj)
		if(ln.type == JSON_TYPE.INTEGER)
			def.line = cast(int)ln.integer - 1;

	if(JSONValue* typ = "type" in obj)
	{
		if(typ.type == JSON_TYPE.STRING)
			def._type = typ.str;
	}
	// dmd 2.062:
	if(JSONValue* dec = "deco" in obj)
		if(dec.type == JSON_TYPE.STRING)
			def.deco = dec.str;
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
			mModified = timeLastModified(fileName);
			return true;
		}
		catch(JSONException rc)
		{
			string msg = rc.toString();
			writeToBuildOutputPane(fileName ~ ": " ~ msg);
			logCall("EXCEPTION: " ~ msg);
		} 
		catch(UTFException rc)
		{
			string msg = rc.toString();
			writeToBuildOutputPane(fileName ~ ": " ~ msg);
			logCall("EXCEPTION: " ~ msg);
		}
		catch(FileException rc)
		{
			string msg = rc.toString();
			writeToBuildOutputPane(fileName ~ ": " ~ msg);
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

	JSONValue[] getModules()
	{
		if(mModules.type == JSON_TYPE.ARRAY)
			return mModules.array;
		return null;
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
				
				if(JSONValue* k = "kind" in memberobj)
					if(k.type == JSON_TYPE.STRING)
						def.kind = k.str;
				if(!isDeclarationKind(def.kind))
					return 2;

				getDeclarationInfo(def, memberobj);
				sd.addDefinition(defs, def);
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
					{
						// strip template arguments and constraint
						string s = n.str;
						int pos = indexOf(s, '(');
						if(pos >= 0)
							s = s[0..pos];
						addunique(cplts, s);
					}
			return 0;
		}
		iterateObjects(&findCplt);
		
		return cplts;
	}

	JSONValue mModules;
	string mFilename;
	SysTime mModified;
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
		TokenInfo[] lineInfo = dLex.ScanLine(Lexer.State.kWhite, text);
		
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
			if(ident.length == 0 && lineInfo[pos].type == TokenCat.Identifier)
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
	string deco;
	string help;
	int line;

	private string _type;
	@property string type() const
	{
		if(_type.length == 0 && deco.length)
			(cast()this)._type = demangleType(deco, name);
		return _type; 
	}
	void setType(string t)
	{
		_type = t;
	}

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

	void setFromBrowseNode(BrowseNode node)
	{
		filename = node.GetFile();
		line = node.line;
		inScope = node.GetScope();
		name = node.name;
		kind = node.kind;
		_type = node._type;
		deco = node.deco;
	}
}

class LibraryInfos
{
	alias BrowseInfo INFO;
	alias BrowseNode VALUE;
	
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
		bool modified = false;
		
		// remove files no longer found and update modified files
		for(int i = 0; i < mInfos.length; )
		{
			int idx = arrIndex(files, mInfos[i].mFilename);
			if(idx < 0)
			{
				mInfos = mInfos[0 .. i] ~ mInfos[i+1 .. $];
				modified = true;
			}
			else
			{
				files = files[0 .. idx] ~ files[idx+1 .. $];
				auto filetime = timeLastModified(mInfos[i].mFilename);
				if(mInfos[i].mModified != filetime)
				{
					mInfos[i].readJSON(mInfos[i].mFilename);
					modified = true;
				}
				i++;
			}
		}
		
		// add new files
		foreach(file; files)
		{
			auto info = new INFO;
			if(info.readJSON(file))
			{
				mInfos ~= info;
				modified = true;
			}
		}
		
		if(modified)
			mUpdateCounter++;
		
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

	VALUE findClass(string name, VALUE lookupScope)
	{
		return null;
	}
	
	INFO findInfo(string name)
	{
		foreach(info; mInfos)
		{
			string iname = getNameWithoutExt(info.mFilename);
			if(icmp(name, iname) == 0)
				return info;
		}
		return null;
	}
	
	@property int updateCounter() { return mUpdateCounter; }
	
	INFO[] mInfos;
	int mUpdateCounter;
}

class BrowseNode
{
	string name;
	string kind;
	string deco;
	
	private string _type;
	@property string type() { return _type; }

	int line;
	
	BrowseNode parent;
	BrowseNode[] members;
	
	string GetFile()
	{
		if(parent)
			return parent.GetFile();
		return null;
	}
	string GetBase()
	{
		return null;
	}
	string[] GetInterfaces()
	{
		return null;
	}
	string GetScope()
	{
		if(!parent)
			return null;
		
		string pname = parent.name;
		for(auto p = parent.parent; p; p = p.parent)
		{
			if(pname.length && p.name.length)
				pname = p.name ~ "." ~ pname;
			else
				pname = p.name ~ pname;
		}
		return pname;
	}
}

class ModuleBrowseNode : BrowseNode
{
	string file;
	
	override string GetFile()
	{
		return file;
	}
}

class ClassBrowseNode : BrowseNode
{
	string base;
	string[] interfaces;

	override string GetBase()
	{
		return base;
	}
	override string[] GetInterfaces()
	{
		return interfaces;
	}
}

class BrowseInfo
{
	string mFilename;
	SysTime mModified;
	
	BrowseNode[] mModules;

	bool readJSON(string fileName)
	{
		LibraryInfo info = new LibraryInfo;
		if(!info.readJSON(fileName))
			return false;
		
		mFilename = info.mFilename;
		mModified = info.mModified;
		destroy(mModules);
		
		createModules(info);
		if(Config cfg = getProjectConfig(mFilename))
		{
			if (auto proj = cfg.GetProject())
				proj.ClearLineChanges();
			release(cfg);
		}
		return true;
	}

	static BrowseNode createNode(JSONValue[string] memberobj)
	{
		string kind;
		if(JSONValue* k = "kind" in memberobj)
			if(k.type == JSON_TYPE.STRING)
				kind = k.str;
		
		BrowseNode node;
		if(kind == "module")
		{
			auto n = new ModuleBrowseNode;
			if(JSONValue* v = "file" in memberobj)
				if(v.type == JSON_TYPE.STRING)
					n.file = v.str;
			node = n;
			if("name" !in memberobj)
				node.name = stripExtension(baseName(n.file));
		}
		else if (kind == "class" || kind == "interface")
		{
			auto n = new ClassBrowseNode;
			if(JSONValue* base = "base" in memberobj)
				if(base.type == JSON_TYPE.STRING)
					n.base = base.str;
			if(JSONValue* iface = "interfaces" in memberobj)
				if(iface.type == JSON_TYPE.ARRAY)
					foreach(m; iface.array)
						if(m.type == JSON_TYPE.STRING)
							n.interfaces ~= m.str;
			node = n;
		}
		else
		{
			if(kind == "function")
			{
				if(JSONValue* n = "name" in memberobj)
					if(n.type == JSON_TYPE.STRING)
						if (n.str.startsWith("__unittest") || n.str.startsWith("__invariant"))
							return null;

				if(!("endline" in memberobj))
					kind = "function decl";
			}
			node = new BrowseNode;
		}

		node.kind = kind;
		getDeclarationInfo(node, memberobj);
		
		return node;
	}
	
	static void removeEponymousTemplate(BrowseNode n)
	{
		if(n.parent && n.members.length == 1 && n.line == n.members[0].line &&
		   (n.kind == "template" || n.kind == n.members[0].kind))
		{
			if(startsWith(n.name, n.members[0].name ~ "("))
			{
				n.members[0].name = n.name;
				foreach(ref m; n.parent.members)
					if(m == n)
						m = n.members[0];
			}
		}
	}
	
	void createModules(LibraryInfo info)
	{
		if(info.mModules.type == JSON_TYPE.ARRAY)
		{
			JSONValue[] modules = info.mModules.array;
			foreach(JSONValue mod; modules)
			{
				if(mod.type == JSON_TYPE.OBJECT)
				{
					void iterate(JSONValue[string] object, BrowseNode parent)
					{
						BrowseNode node = createNode(object);
						if(!node)
							return;

						if(parent)
						{
							parent.members ~= node;
							node.parent = parent;
						}
						else
							mModules ~= node;
						
						if(JSONValue* m = "members" in object)
							if(m.type == JSON_TYPE.ARRAY)
							{
								JSONValue[] members = m.array;
								foreach(member; members)
									if(member.type == JSON_TYPE.OBJECT)
										iterate(member.object, node);
							}
						
						removeEponymousTemplate(node);
					}
					
					iterate(mod.object, null);
				}
			}
		}
	}

	// dg_match returns:
	// 0 - continue search
	// 1 - stop search
	// 2 - continue search, but prune subtree
	bool iterateNodes(int delegate(BrowseNode node) dg_match)
	{
		foreach(mod; mModules)
		{
			int iterate(BrowseNode node)
			{
				int res = dg_match(node);
				if(res == 1)
					return 1;
				if(res == 2)
					return 0;

				foreach(n; node.members)
				{
					res = iterate(n);
					if(res > 0)
						return res;
				}
				return 0;
			}
			if(iterate(mod) == 1)
				return true;
		}
		return false;
	}
	
	Definition[] findDefinition(ref SearchData sd)
	{
		Definition[] defs;

		int findDef(BrowseNode node)
		{
			if(sd.pruneSubtree(node))
				return 2;
			if(!isDeclarationKind(node.kind))
				return 2;
			if(sd.matchDefinition(node))
			{
				Definition def;
				def.setFromBrowseNode(node);
				sd.addDefinition(defs, def);
			}
			return 0;
		}
		
		iterateNodes(&findDef);
		return defs;
	}

	string[] findCompletions(ref SearchData sd)
	{
		string[] cplts;

		int findCplt(BrowseNode node)
		{
			if(startsWith(node.name, sd.names[0]))
			{
				// strip template arguments and constraint
				string s = node.name;
				int pos = indexOf(s, '(');
				if(pos >= 0)
					s = s[0..pos];
				addunique(cplts, s);
			}
			return 0;
		}
		iterateNodes(&findCplt);
		
		return cplts;
	}
}
