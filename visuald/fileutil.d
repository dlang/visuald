// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module fileutil;

import std.c.windows.windows;
import std.string;
import std.stream;
import std.path;
import std.file;
import std.utf;

extern(Windows)	UINT GetSystemDirectoryW(LPWSTR lpBuffer, UINT uSize);

string normalizeDir(string dir)
{
	if(dir.length == 0)
		return ".\\";
	dir = replace(dir, "/", "\\");
	if(dir[$-1] == '\\')
		return dir;
	return dir ~ "\\";
}

string normalizePath(string path)
{
	return replace(path, "/", "\\");
}

string makeFilenameAbsolute(string file, string workdir)
{
	if(!isabs(file))
		file = workdir ~ "\\" ~ file;
	return file;
}

void makeFilenamesAbsolute(string[] files, string workdir)
{
	foreach(ref file; files)
	{
		if(!isabs(file))
			file = makeFilenameAbsolute(file, workdir);
	}
}

string quoteFilename(string fname)
{
	if(fname.length >= 2 && fname[0] == '\"' && fname[$-1] == '\"')
		return fname;
	if(fname.indexOf('$') >= 0 || indexOf(fname, ' ') >= 0)
		fname = "\"" ~ fname ~ "\"";
	return fname;
}

string quoteNormalizeFilename(string fname)
{
	return quoteFilename(normalizePath(fname));
}

string getNameWithoutExt(string fname)
{
	string bname = getBaseName(fname);
	string name = getName(bname);
	if(name.length == 0)
		name = bname;
	return name;
}

string getCmdPath()
{
	wchar buffer[260];
	UINT len = GetSystemDirectoryW(buffer.ptr, 260);
	string p = toUTF8(buffer[0 .. len]);
	return normalizeDir(p) ~ "cmd.exe";
}

//-----------------------------------------------------------------------------
void getOldestNewestFileTime(string[] files, out long oldest, out long newest)
{
	oldest = long.max;
	newest = long.min;
	foreach(file; files)
	{
		if(!exists(file))
			goto L_fileNotFound;
		long ftc, fta, ftm;
		getTimes(file, ftc, fta, ftm);
		if(ftm > newest)
			newest = ftm;
		if(ftm < oldest)
			oldest = ftm;
	}
	return;

L_fileNotFound:
	oldest = long.min;
	newest = long.max;
}

long getNewestFileTime(string[] files)
{
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest);
	return newest;
}

long getOldestFileTime(string[] files)
{
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest);
	return oldest;
}

bool compareCommandFile(string cmdfile, string cmdline)
{
	try
	{
		if(!exists(cmdfile))
			return false;
		string lastCmd = cast(string)std.file.read(cmdfile);
		if (strip(cmdline) != strip(lastCmd))
			return false;
	}
	catch(Exception)
	{
		return false;
	}
	return true;
}

//-----------------------------------------------------------------------------
string[string][string] parseIni(string fname)
{
	string currentSection;
	try
	{
		string[string][string] ini;
		File file = new File(fname);
		while(!file.eof())
		{
			string ln = file.readLine().idup;
			ln = strip(ln);
			int pos = indexOf(ln, ']');
			if(pos >= 0 && startsWith(ln, "["))
			{
				currentSection = ln[1..pos];
			}
			else if ((pos = indexOf(ln, '=')) >= 1)
			{
				string name = strip(ln[0 .. pos]);
				string value = strip(ln[pos + 1 .. $]);
				ini[currentSection][name] = value;
			}
		}
		return ini;
	}
	catch(Exception e)
	{
		return null;
	}
}

string makeRelative(string file, string path)
{
	if(!isabs(file))
		return file;
	if(!isabs(path))
		return file;

	file = replace(file, "/", "\\");
	path = replace(path, "/", "\\");
	if(path[$-1] != '\\')
		path ~= "\\";

	string lfile = tolower(file);
	string lpath = tolower(path);

	int posfile = 0;
	for( ; ; )
	{
		int idxfile = indexOf(lfile, '\\');
		int idxpath = indexOf(lpath, '\\');
		assert(idxpath >= 0);

		if(idxfile < 0 || idxfile != idxpath || lfile[0..idxfile] != lpath[0 .. idxpath])
		{
			if(posfile == 0)
				return file;

			// path longer than file path or different subdirs
			string res;
			while(idxpath >= 0)
			{
				res ~= "..\\";
				lpath = lpath[idxpath + 1 .. $];
				idxpath = indexOf(lpath, '\\');
			}
			return res ~ file[posfile .. $];
		}
		
		lfile = lfile[idxfile + 1 .. $];
		lpath = lpath[idxpath + 1 .. $];
		posfile += idxfile + 1;
		
		if(lpath.length == 0)
		{
			// file longer than path
			return file[posfile .. $];
		}
	}
}

unittest
{
	string file = "c:\\a\\bc\\def\\ghi.d";
	string path = "c:\\a\\bc\\x";
	string res = makeRelative(file, path);
	assert(res == "..\\def\\ghi.d");

	file = "c:\\a\\bc\\def\\ghi.d";
	path = "c:\\a\\bc\\def";
	res = makeRelative(file, path);
	assert(res == "ghi.d");

	file = "c:\\a\\bc\\def\\Ghi.d";
	path = "c:\\a\\bc\\Def\\ggg\\hhh\\iii";
	res = makeRelative(file, path);
	assert(res == "..\\..\\..\\Ghi.d");

	file = "d:\\a\\bc\\Def\\ghi.d";
	path = "c:\\a\\bc\\def\\ggg\\hhh\\iii";
	res = makeRelative(file, path);
	assert(res == file);
}


version(D_Version2) {} else {

void mkdirRecurse(string outdir)
{
    // TODO
    mkdir(outdir);
}

}
