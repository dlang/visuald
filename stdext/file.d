// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module stdext.file;

import stdext.path;
import stdext.array;
import stdext.string;

import std.file;
import std.path;
import std.utf;
import std.conv;
import std.array;
import std.string;
import std.ascii;

import core.sys.windows.windows;
import core.bitop;

bool isExistingDir(string dir)
{
	return std.file.exists(dir) && std.file.isDir(dir);
}

string getCmdPath()
{
	wchar[260] buffer;
	UINT len = GetSystemDirectoryW(buffer.ptr, 260);
	string p = toUTF8(buffer[0 .. len]);
	return normalizeDir(p) ~ "cmd.exe";
}


//-----------------------------------------------------------------------------
string readUtf8(string fname, uint upTo = -1U)
{
	/* Convert all non-UTF-8 formats to UTF-8.
	* BOM : http://www.unicode.org/faq/utf_bom.html
	* 00 00 FE FF  UTF-32BE, big-endian
	* FF FE 00 00  UTF-32LE, little-endian
	* FE FF        UTF-16BE, big-endian
	* FF FE        UTF-16LE, little-endian
	* EF BB BF     UTF-8
	*/
	static ubyte[4] bomUTF32BE = [ 0x00, 0x00, 0xFE, 0xFF ]; // UTF-32, big-endian
	static ubyte[4] bomUTF32LE = [ 0xFF, 0xFE, 0x00, 0x00 ]; // UTF-32, little-endian
	static ubyte[2] bomUTF16BE = [ 0xFE, 0xFF ];             // UTF-16, big-endian
	static ubyte[2] bomUTF16LE = [ 0xFF, 0xFE ];             // UTF-16, little-endian
	static ubyte[3] bomUTF8    = [ 0xEF, 0xBB, 0xBF ];       // UTF-8

	ubyte[] data = cast(ubyte[]) std.file.read(fname, upTo);
	if(data.length >= 4 && data[0..4] == bomUTF32BE[])
		foreach(ref d; cast(uint[]) data)
			d = bswap(d);
	if(data.length >= 2 && data[0..2] == bomUTF16BE[])
		foreach(ref d; cast(ushort[]) data)
			d = bswap(d) >> 16;

	if(data.length >= 4 && data[0..4] == bomUTF32LE[])
		return toUTF8(cast(dchar[]) data[4..$]);
	if(data.length >= 2 && data[0..2] == bomUTF16LE[])
		return toUTF8(cast(wchar[]) data[2..$]);
	if(data.length >= 3 && data[0..3] == bomUTF8[])
		return toUTF8(cast(string) data[3..$]);

	return cast(string)data;
}

//-----------------------------------------------------------------------------
string[string][string] parseIniText(string txt)
{
	string currentSection;
	string[string][string] ini;
	string content;
	foreach(string ln; txt.splitLines())
	{
		ln = strip(ln);
		auto pos = indexOf(ln, ']');
		if(pos >= 0 && startsWith(ln, "["))
		{
			if(currentSection.length)
			{
				ini[currentSection][""] ~= content;
				content = "";
			}
			currentSection = ln[1..pos];
		}
		else
		{
			content ~= ln ~ "\n";
			if ((pos = indexOf(ln, '=')) >= 1)
			{
				string name = strip(ln[0 .. pos]);
				string value = strip(ln[pos + 1 .. $]);
				ini[currentSection][name] = value;
			}
		}
	}
	if(currentSection.length)
		ini[currentSection][""] ~= content;
	return ini;
}

// extract assignments from a section
string[2][] parseIniSectionAssignments(string txt)
{
	string[2][] values;
	foreach(string ln; txt.splitLines())
	{
		auto pos = indexOf(ln, '=');
		if (pos >= 1)
		{
			// stripping is not done by cmd when using "SET", but dmd does it (optlink does not)
			string id = strip(ln[0..pos]);
			string val = strip(ln[pos+1..$]);
			if(id.length && id[0] != ';')
				values ~= [id, val];
		}
	}
	return values;
}

string[string][string] parseIni(string fname, bool utf8)
{
	try
	{
		import std.windows.charset;

		void[] content = std.file.read(fname);
		string txt;
		if (utf8)
			txt = to!string(content);
		else
			txt = fromMBSz((cast(string)content ~ '0').ptr);

		return parseIniText(txt);
	}
	catch(Exception e)
	{
	}
	return null;
}


//-----------------------------------------------------------------------------
string[] expandFileListPattern(string file, string workdir)
{
	string[] files;
	SpanMode mode = SpanMode.shallow;
	if (file[0] == '+')
	{
		mode = SpanMode.depth;
		file = file[1..$];
	}
	string path = dirName(file);
	path = makeFilenameAbsolute(path, workdir);
	string pattern = baseName(file);
	foreach (string name; dirEntries(path, mode))
		if (globMatch(baseName(name), pattern))
			addunique(files, makeRelative(name, workdir));
	return files;
}

string[] addFileListPattern(string[] files, string file, string workdir)
{
	if (indexOf(file, '*') >= 0 || indexOf(file, '?') >= 0)
		addunique(files, expandFileListPattern(file, workdir));
	else
		addunique(files, file);
	return files;
}

string[] expandFileList(string[] filespecs, string workdir)
{
	string[] files;
	foreach(file; filespecs)
	{
		if (file.startsWith("-"))
		{
			string[] exclude = addFileListPattern([], file[1..$], workdir);
			foreach(ex; exclude)
				stdext.array.remove(files, ex);
		}
		else
			files = addFileListPattern(files, file, workdir);
	}
	return files;
}

//-----------------------------------------------------------------------------
string[] expandResponseFiles(string[] args, string workdir)
{
	for(size_t a = 0; a < args.length; a++)
	{
		string arg = unquoteArgument(args[a]);
		if(arg.startsWith("@"))
		{
			// read arguments from response file
			try
			{
				string rsp = makeFilenameAbsolute(arg[1..$], workdir);
				string[] fargs = tokenizeArgs(to!string(std.file.read(rsp)));
				args = args[0..a] ~ fargs ~ args[a+1 .. $];
				--a;
			}
			catch(Exception e)
			{
			}
		}
	}
	return args;
}
