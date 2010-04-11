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

import logutil;

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
}

struct Definition
{
	string kind;
	string filename;
	int line;
}

class LibraryInfos
{
	this()
	{
		auto info = new LibraryInfo;
		info.readJSON(r"m:\s\d\visuald\trunk\bin\Debug\visuald.json");
		mInfos ~= info;
	}
	
	LibraryInfo[] mInfos;
	
	Definition[] findDefinition(string name)
	{
		Definition[] defs;
		foreach(info; mInfos)
			defs ~= info.findDefinition(name);
		return defs;
	}
}
