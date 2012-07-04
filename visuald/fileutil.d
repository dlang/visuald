// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.fileutil;

import visuald.windows;

import stdext.path;

import std.path;
import std.file;
import std.string;
import std.conv;
import std.utf;

//-----------------------------------------------------------------------------
long[string] gCachedFileTimes;

void clearCachedFileTimes()
{
	long[string] empty;
	gCachedFileTimes = empty; // = gCachedFileTimes.init;
}

void removeCachedFileTime(string file)
{
	file = canonicalPath(file);
	gCachedFileTimes.remove(file);
}

//-----------------------------------------------------------------------------
void getOldestNewestFileTime(string[] files, out long oldest, out long newest)
{
	oldest = long.max;
	newest = long.min;
	foreach(file; files)
	{
		file = canonicalPath(file);
		long ftm;
		if(auto ptm = file in gCachedFileTimes)
			ftm = *ptm;
		else
		{
			if(!exists(file))
				goto L_fileNotFound;
			ftm = timeLastModified(file).stdTime();
			gCachedFileTimes[file] = ftm;
		}
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

bool moveFileToRecycleBin(string fname)
{
	SHFILEOPSTRUCT fop;
	fop.wFunc = FO_DELETE;
	fop.fFlags = FOF_NO_UI | FOF_NORECURSION | FOF_FILESONLY | FOF_ALLOWUNDO;
	wstring wname = to!wstring(fname);
	wname ~= "\000\000";
	fop.pFrom = wname.ptr;

	if(SHFileOperation(&fop) != 0)
		return false;
	return !fop.fAnyOperationsAborted;
}

string shortFilename(string fname)
{
	wchar* sptr;
	auto wfname = toUTF16z(fname);
	wchar[256] spath;
	DWORD len = GetShortPathNameW(wfname, spath.ptr, spath.length);
	if(len > spath.length)
	{
		wchar[] sbuf = new wchar[len];
		len = GetShortPathNameW(wfname, sbuf.ptr, sbuf.length);
		sptr = sbuf.ptr;
	}
	else
		sptr = spath.ptr;
	if(len == 0)
		return "";
	return to!string(sptr[0..len]);
}
