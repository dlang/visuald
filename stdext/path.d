// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module stdext.path;

import std.path;
import std.array;
import std.string;
import std.conv;

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

string canonicalPath(string path)
{
	return toLower(replace(path, "/", "\\"));
}

string makeFilenameAbsolute(string file, string workdir)
{
	if(!isabs(file) && workdir.length)
	{
		if(file == ".")
			file = workdir;
		else
			file = workdir ~ "\\" ~ file;
	}
	return file;
}

void makeFilenamesAbsolute(string[] files, string workdir)
{
	foreach(ref file; files)
	{
		if(!isabs(file) && workdir.length)
			file = makeFilenameAbsolute(file, workdir);
	}
}

string removeDotDotPath(string file)
{
	// assumes \\ used as path separator
	for( ; ; )
	{
		// remove duplicate back slashes
		int pos = indexOf(file[1..$], "\\\\");
		if(pos < 0)
			break;
		file = file[0..pos+1] ~ file[pos + 2 .. $];
	}
	for( ; ; )
	{
		int pos = indexOf(file, "\\..\\");
		if(pos < 0)
			break;
		int lpos = lastIndexOf(file[0..pos], '\\');
		if(lpos < 0)
			break;
		file = file[0..lpos] ~ file[pos + 3 .. $];
	}
	for( ; ; )
	{
		int pos = indexOf(file, "\\.\\");
		if(pos < 0)
			break;
		file = file[0..pos] ~ file[pos + 2 .. $];
	}
	return file;
}

string makeFilenameCanonical(string file, string workdir)
{
	file = makeFilenameAbsolute(file, workdir);
	file = removeDotDotPath(file);
	return file;
}

void makeFilenamesCanonical(string[] files, string workdir)
{
	foreach(ref file; files)
	{
		file = makeFilenameCanonical(file, workdir);
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

string safeFilename(string fname, string rep = "-") // - instead of _ to not possibly be part of a module name
{
	string safefile = fname;
	foreach(char ch; ":\\/")
		safefile = replace(safefile, to!string(ch), rep);
	return safefile;
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

	string lfile = toLower(file);
	string lpath = toLower(path);

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
