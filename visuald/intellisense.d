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
import std.c.windows.windows;
import std.c.windows.com;

import sdk.vsi.vsshell;

import dpackage;
import config;
import comutil;
import logutil;
import hierutil;
import fileutil;
import simplelexer;

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

	static struct JSONscope
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
		
	Definition[] findDefinition(string name)
	{
		Definition[] defs;
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
					
					void findDefs(JSONValue[string] object, JSONscope* sc)
					{
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
										
										if(nm == name)
										{
											Definition def;
											def.name = name;
											def.filename = filename;
											def.inScope = msc.toString();
											
											if(JSONValue* k = "kind" in memberobj)
												if(k.type == JSON_TYPE.STRING)
													def.kind = k.str;
											if(JSONValue* ln = "line" in memberobj)
												if(ln.type == JSON_TYPE.INTEGER)
													def.line = cast(int)ln.integer - 1;
											if(JSONValue* typ = "type" in memberobj)
												if(typ.type == JSON_TYPE.STRING)
													def.type = typ.str;
											defs ~= def;
										}
										
										findDefs(memberobj, &msc);
									}
								}
							}
					}
				
					JSONscope sc = JSONscope(null, modname);
					findDefs(object, &sc);
				}
			}
		}
		return defs;
	}

	JSONValue mModules;
	string mFilename;
	d_time mModified;
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
							ProjectOptions opt = cfg.GetProjectOptions();
							if(opt.doXGeneration)
							{
								string xfile = opt.replaceEnvironment(opt.xfilename, cfg);
								xfile = makeFilenameAbsolute(xfile, cfg.GetProjectDir());
								if(xfile.length && std.file.exists(xfile))
									addunique(files, xfile);
							}
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
	}
	
	Definition[] findDefinition(string name)
	{
		Definition[] defs;
		foreach(info; mInfos)
			defs ~= info.findDefinition(name);
		return defs;
	}

	LibraryInfo[] mInfos;

}
