// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module stringutil;

import std.c.stdlib;
import std.windows.charset;
import std.path;
import std.utf;
import std.string;
import std.ctype;

string ellipseString(string s, int maxlen)
{
	if (s.length > maxlen - 1)
		s = s[0 .. maxlen - 4] ~ "...";
	return s;
}


void addFileMacros(string path, string base, ref string[string] replacements)
{
	replacements[base ~ "PATH"] = path;
	replacements[base ~ "DIR"] = getDirName(path);
	string filename = getBaseName(path);
	string ext = getExt(path);
	replacements[base ~ "FILENAME"] = filename;
	replacements[base ~ "EXT"] = ext;
	string name = getName(filename);
	replacements[base ~ "NAME"] = name.length == 0 ? filename : name;
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
			string id = toupper(s[i + 2 .. i + 2 + len]);
			string nid;
			if(string *ps = id in replacements)
				nid = *ps;
			else if(char* pe = getenv(std.windows.charset.toMBSz(id)))
				version(D_Version2)
					nid = fromMBSz(cast(immutable)pe);
				else
					nid = fromMBSz(pe);
			
			int *p = id in lastReplacePos;
			if(!p || *p <= i)
			{
				s = s[0 .. i] ~ nid ~ s[i + 3 + len .. $];
				lastReplacePos[id] = i + nid.length;
				continue;
			}
		}
		i++;
	}

	return s;
}

uint endofStringCStyle(string text, uint pos, dchar term = '\"')
{
	while(pos < text.length)
	{
		dchar ch = decode(text, pos);
		if(ch == '\\')
		{
			if (pos >= text.length)
				break;
			ch = decode(text, pos);
		}
		else if(ch == term)
			return pos;
	}
	return pos;
}

string[] tokenizeArgs(string text)
{
	string[] args;
	uint pos = 0;
	while(pos < text.length)
	{
		uint startpos = pos;
		dchar ch = decode(text, pos);
		if(isspace(ch))
			continue;

		uint endpos = pos;
		while(pos < text.length)
		{
			if(ch == '\"')
			{
				pos = endofStringCStyle(text, pos);
				ch = 0;
			}
			else
			{
				ch = decode(text, pos);
			}
			if(isspace(ch))
				break;
			endpos = pos;
		}
		args ~= text[startpos .. endpos];
	}
	return args;
}

string unquoteArgument(string arg)
{
	if(arg.length <= 0 || arg[0] != '\"')
		return arg;

	if (endofStringCStyle(arg, 1) != arg.length)
		return arg;

	return arg[1..$-1];
}

string replaceCrLf(string s)
{
	return replace(replace(s, "\n", ";"), "\r", "");
}

string insertCr(string s)
{
	string ns;
	while(s.length > 0)
	{
		int p = s.indexOf('\n');
		if(p < 0)
			break;
		if(p > 0 && s[p-1] == '\r')
			ns ~= s[0 .. p+1];
		else
			ns ~= s[0 .. p] ~ "\r\n";
		s = s[p+1 .. $];
	}
	return ns ~ s;
}

unittest
{
	string t = insertCr("a\nb\r\ncd\n\ne\n\r\nf");
	assert(t == "a\r\nb\r\ncd\r\n\r\ne\r\n\r\nf");
}

int countVisualSpaces(S)(S txt, int tabSize, int* txtpos)
{
	int p = 0;
	int n = 0;
	while(n < txt.length && isspace(txt[n]))
	{
		if(txt[n] == '\t')
			p = p + tabSize - (p % tabSize);
		else
			p++;
		n++;
	}
	if(txtpos)
		*txtpos = n;
	return p;
}

// extract value from a series of #define values
string extractDefine(string s, string def)
{
	for(int p = 0; p < s.length; p++)
	{
		while(p < s.length && (s[p] == ' ' || s[p] == '\t'))
			p++;
		int q = p;
		while(q < s.length && s[q] != '\n' && s[q] != '\r')
			q++;
		
		if(_startsWith(s[p .. $], "#define") && (s[p+7] == ' ' || s[p+7] == '\t'))
		{
			p += 7;
			while(p < s.length && (s[p] == ' ' || s[p] == '\t'))
				p++;
			if(_startsWith(s[p .. $], def) && (s[p+def.length] == ' ' || s[p+def.length] == '\t'))
			{
				p += def.length;
				while(p < s.length && (s[p] == ' ' || s[p] == '\t'))
					p++;
				return s[p .. q];
			}
		}
		p = q;
	}
	return "";
}

string extractDefines(string s)
{
	string m;
	for(int p = 0; p < s.length; p++)
	{
		while(p < s.length && (s[p] == ' ' || s[p] == '\t'))
			p++;
		int q = p;
		while(q < s.length && s[q] != '\n' && s[q] != '\r')
			q++;
		
		if(_startsWith(s[p .. $], "#define") && (s[p+7] == ' ' || s[p+7] == '\t'))
		{
			p += 7;
			int b = p;
			while(p < q && (s[p] == ' ' || s[p] == '\t'))
				p++;
			int r = p;
			while(r < q && !isspace(s[r]))
				r++;
			if(r < q)
			{
				m ~= "const " ~ s[p..r] ~ " = " ~ s[r..q] ~ ";\n";
			}
		}
		p = q;
	}
	return m;
}

// endsWith does not work reliable and crashes on page end
bool _endsWith(string s, string e)
{
	return (s.length >= e.length && s[$-e.length .. $] == e);
}

// startsWith causes compile error when used in ctfe
bool _startsWith(string s, string w)
{
	return (s.length >= w.length && s[0 .. w.length] == w);
}

version(D_Version2) {} else {

// for D1 compatibility
bool startsWith(string s, string e)
{
	return (s.length >= e.length && s[0 .. e.length] == e);
}

}
