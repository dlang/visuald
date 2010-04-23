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
					JSONValue[string] object = mod.object;
					if(JSONValue* v = "file" in object)
						if(v.type == JSON_TYPE.STRING)
							filename = v.str;
					
					void findDefs(JSONValue[string] object)
					{
						if(JSONValue* m = "members" in object)
							if(m.type == JSON_TYPE.ARRAY)
							{
								JSONValue[] members = m.array;
								foreach(member; members)
								{
									if(member.type == JSON_TYPE.OBJECT)
									{
										JSONValue[string] memberobj = member.object;
										if(JSONValue* n = "name" in memberobj)
											if(n.type == JSON_TYPE.STRING && n.str == name)
											{
												Definition def;
												def.filename = filename;
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
										findDefs(memberobj);
									}
								}
							}
					}
				
					findDefs(object);
				}
			}
		}
		return defs;
	}

	JSONValue mModules;
	string mFilename;
	d_time mModified;
}

struct Definition
{
	string kind;
	string filename;
	string type;
	int line;
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
