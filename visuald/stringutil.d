// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.stringutil;

import visuald.windows;
import visuald.comutil;

import std.c.stdlib;
//import std.windows.charset;
import std.path;
import std.utf;
import std.string;
import std.ascii;
import std.conv;
import std.array;

string ellipseString(string s, int maxlen)
{
	if (s.length > maxlen - 1)
		s = s[0 .. maxlen - 4] ~ "...";
	return s;
}


void addFileMacros(string path, string base, ref string[string] replacements)
{
	replacements[base ~ "PATH"] = path;
	replacements[base ~ "DIR"] = dirName(path);
	string filename = baseName(path);
	string ext = extension(path);
	if(ext.startsWith("."))
		ext = ext[1..$];
	replacements[base ~ "FILENAME"] = filename;
	replacements[base ~ "EXT"] = ext;
	string name = stripExtension(filename);
	replacements[base ~ "NAME"] = name.length == 0 ? filename : name;
}

string getEnvVar(string var)
{
	wchar wbuf[256];
	const(wchar)* wvar = toUTF16z(var);
	uint cnt = GetEnvironmentVariable(wvar, wbuf.ptr, 256);
	if(cnt < 256)
		return to_string(wbuf.ptr, cnt);
	wchar[] pbuf = new wchar[cnt+1];
	cnt = GetEnvironmentVariable(wvar, pbuf.ptr, cnt + 1);
	return to_string(pbuf.ptr, cnt);
}

string replaceMacros(string s, string[string] replacements)
{
	int[string] lastReplacePos;

	for(int i = 0; i + 2 < s.length; )
	{
		if(s[i .. i+2] == "$(")
		{
			int len = indexOf(s[i+2 .. $], ')');
			if(len < 0)
				break;
			string id = toUpper(s[i + 2 .. i + 2 + len]);
			string nid;
			if(string *ps = id in replacements)
				nid = *ps;
			else
				nid = getEnvVar(id);
			
			int *p = id in lastReplacePos;
			if(!p || *p <= i)
			{
				s = s[0 .. i] ~ nid ~ s[i + 3 + len .. $];
				int difflen = nid.length - (len + 3);
				foreach(ref int pos; lastReplacePos)
					if(pos > i)
						pos += difflen;
				lastReplacePos[id] = i + nid.length;
				continue;
			}
		}
		else if(s[i .. i+2] == "$$")
			s = s[0 .. i] ~ s[i + 1 .. $];
		i++;
	}

	return s;
}

S createPasteString(S)(S s)
{
	S t;
	bool wasWhite = false;
	foreach(dchar ch; s)
	{
		if(t.length > 30)
			return t ~ "...";
		bool isw = isWhite(ch);
		if(ch == '&')
			t ~= "&&";
		else if(!isw)
			t ~= ch;
		else if(!wasWhite)
			t ~= ' ';
		wasWhite = isw;
	}
	return t;		
}