// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.fileutil;

import sdk.port.base;
import sdk.win32.shellapi;

import stdext.array;
import stdext.file;
import stdext.string;
import stdext.path;

import std.algorithm;
import std.ascii : isAlpha;
import std.path;
import std.file;
import std.string;
import std.conv;
import std.utf;
import std.stdio;
import std.regex;

//-----------------------------------------------------------------------------
long[string] gCachedFileTimes;
alias AssociativeArray!(string, long) _wa1; // fully instantiate type info

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
void getOldestNewestFileTime(string[] files, out long oldest, out long newest, out string oldestFile, out string newestFile)
{
	oldest = long.max;
	newest = long.min;
	foreach(file; files)
	{
		file = canonicalPath(file);
		if (file.length == 6 && file[0..3] == "//./" && isAlpha(file[4]) && file[5] == ':')
			continue; // since version 1.40, LDC produces a dependency on "\\.\c:"
		long ftm;
		if(auto ptm = file in gCachedFileTimes)
			ftm = *ptm;
		else
		{
			if(!exists(file))
			{
			L_fileNotFound:
				oldest = long.min;
				newest = long.max;
				oldestFile = newestFile = file;
				break;
			}
version(all)
			ftm = timeLastModified(file).stdTime();
else
{
			WIN32_FILE_ATTRIBUTE_DATA fad;
			if(!GetFileAttributesExW(std.utf.toUTF16z(file), /*GET_FILEEX_INFO_LEVELS.*/GetFileExInfoStandard, &fad))
				goto L_fileNotFound;
			ftm = *cast(long*) &fad.ftLastWriteTime;
}
			gCachedFileTimes[file] = ftm;
		}
		if(ftm > newest)
		{
			newest = ftm;
			newestFile = file;
		}
		if(ftm < oldest)
		{
			oldest = ftm;
			oldestFile = file;
		}
	}
}

long getNewestFileTime(string[] files, out string newestFile)
{
	string oldestFile;
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest, oldestFile, newestFile);
	return newest;
}

long getOldestFileTime(string[] files, out string oldestFile)
{
	string newestFile;
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest, oldestFile, newestFile);
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
		len = GetShortPathNameW(wfname, sbuf.ptr, cast(DWORD)sbuf.length);
		sptr = sbuf.ptr;
	}
	else
		sptr = spath.ptr;
	if(len == 0)
		return "";
	return to!string(sptr[0..len]);
}

string createNewPackageInFolder(string dir, string base)
{
	string ndir = normalizeDir(dir);
	dir = ndir[0..$-1]; // remove trailing '/'
	if (!exists(dir) || !isDir(dir))
		return null;

	string name = base;
	int num = 0;
	while(exists(ndir ~ name) || exists(ndir ~ name ~ ".d") || exists(ndir ~ name ~ ".di"))
	{
		num++;
		name = base ~ to!string(num);
	}
	try
	{
		mkdir(ndir ~ name);
	}
	catch(FileException)
	{
		return null;
	}
	return name;
}

string[] findDRuntimeFiles(string path, string sub, bool deep, bool cfiles = false, bool internals = false)
{
	string[] files;
	if(!isExistingDir(path ~ sub))
		return files;
	foreach(string file; dirEntries(path ~ sub, SpanMode.shallow))
	{
		if(_startsWith(file, path))
			file = file[path.length .. $];
		if (deep && isExistingDir(path ~ file))
		{
			string[] exclude = [ "\\internal", "\\freebsd", "\\linux", "\\osx", "\\posix", "\\solaris" ];
			if (internals)
				exclude = exclude[1..$];
			if (!any!(e => file.endsWith(e))(exclude))
				files ~= findDRuntimeFiles(path, file, deep, cfiles, internals);
			continue;
		}
		string bname = baseName(file);
		if(globMatch(bname, "openrj.d"))
			continue;
		if(globMatch(bname, "minigzip.c") || globMatch(bname, "example.c"))
			continue;
		if(globMatch(bname, "bss_section.c") || globMatch(bname, "dylib_fixes.c") || globMatch(bname, "osx_tls.c"))
			continue;

		if(cfiles)
		{
			if(globMatch(bname, "*.c"))
				if(!contains(files, file))
					files ~= file;
		}
		else if(globMatch(bname, "*.d"))
			if(string* pfile = contains(files, file ~ "i"))
				*pfile = file;
			else
				files ~= file;
		else if(globMatch(bname, "*.di"))
		{
			// use the d file instead if available
			string dfile = "..\\src\\" ~ file[0..$-1];
			if(std.file.exists(path ~ dfile))
				file = dfile;
			if(!contains(files, file[0..$-1]))
				files ~= file;
		}
	}
	return files;
}

///////////////////////////////////////////////////////////////
static struct SymLineInfo
{
	string sym;
	int firstLine;
	uint[] offsets;
}

// map symbol + offset to line in disasm dump
SymLineInfo[string] readDisasmFile(string asmfile)
{
	SymLineInfo[string] symInfos;

	__gshared static Regex!char resym, resym2, resym3, resym4, reoff, reoff2;

	if(resym.empty) // dumpbin/llvm-objdump
		resym = regex(r"^([A-Za-z_][^ \t:]*):$");   // <non numeric symbol>:
	if(resym2.empty) // obj2asm
		resym2 = regex(r"^[ \t]*assume[ \t]+[Cc][Ss]:([A-Za-z_][^ \t]*)[ \t]*$");   // assume CS:<non numeric symbol>
	if(resym3.empty) // objconv
		resym3 = regex(r"^([A-Za-z_][^ \t]*)[ \t]+PROC[ \t]+NEAR[ \t]*$");   // <non numeric symbol> PROC NEAR
	if(resym4.empty) // gcc-objdump
		resym4 = regex(r"^[0-9A-Fa-f]+[ \t]*\<([A-Za-z_][^>]*)\>:[ \t]*$");  // 000000 <non numeric symbol>

	if(reoff.empty())
		reoff = regex(r"^([0-9A-Fa-f]+):.*$"); // <hex number>:
	if(reoff2.empty())
		reoff2 = regex(r"[^;]*;[ \t:]*([0-9A-Fa-f]+) _.*$"); // ; <hex number> _

	int ln = 0;
	SymLineInfo info;
	File asmf = File(asmfile);
	foreach(line; asmf.byLine())
	{
		ln++;
		if (line.length == 0)
		{
			// intermediate lines in objconv output happen to contain a \t
			if (info.offsets.length)
			{
				symInfos[info.sym] = info;
				info.sym = null;
				info.offsets = null;
			}
			continue;
		}
		line = toUTF8Safe(line);
		line = strip(line);
		auto rematch = match(line, resym);
		if (rematch.empty())
			rematch = match(line, resym2);
		if (rematch.empty())
			rematch = match(line, resym3);
		if (rematch.empty())
			rematch = match(line, resym4);
		if (!rematch.empty())
		{
			if (info.offsets.length)
				symInfos[info.sym] = info;

			info.sym = rematch.captures[1].idup;
			info.firstLine = ln;
			info.offsets = null;
			continue;
		}
		rematch = match(line, reoff);
		if (rematch.empty())
			rematch = match(line, reoff2);
		if (!rematch.empty())
		{
			uint off = rematch.captures[1].to!uint(16);
			info.offsets ~= off;
		}
		else if (info.sym.length)
		{
			if (info.offsets.length)
				info.offsets ~= info.offsets[$-1];
			else
				info.offsets ~= 0;
		}
	}
	if (info.offsets.length)
		symInfos[info.sym] = info;
	return symInfos;
}

unittest
{
	string dumpbin = r"
Dump of file Debug\winmain.obj

File Type: COFF OBJECT

WinMain:
  0000000000000000: 55                 push        rbp
  0000000000000001: 48 8B EC           mov         rbp,rsp
                    00
  0000000000000004: 48 83 EC 28        sub         rsp,28h

; obj2asm style
	assume CS:_D7winmain9myWinMainFPvPvPaiZi
  0000000000000000: 55                 push        rbp
  0000000000000001: 48 8B EC           mov         rbp,rsp
  0000000000000004: 48 83 EC 30        sub         rsp,30h

; objconv style
_WinMain@16 PROC NEAR
;  COMDEF _WinMain@16
        push    ebp                                     ; 0000 _ 55
        mov     ebp, esp                                ; 0001 _ 8B. EC
ASSUME  fs:NOTHING
        push    48                                      ; 0003 _ 6A, 30
	" /* explicite trailing spaces before nl */ ~ "
; Note: No jump seems to point here
        mov     ecx, offset FLAT:?_009                  ; 0005 _ B9, 00000000(segrel)

Disassembly of section .text: GNU objdump

0000000000000000 <_foo>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
";
	auto deleteme = "deleteme";
	std.file.write(deleteme, dumpbin);
	scope(exit) std.file.remove(deleteme);

	auto symInfo = readDisasmFile(deleteme);
	assert(symInfo.length == 4);
	assert(symInfo["WinMain"].firstLine == 6);
	assert(symInfo["WinMain"].offsets.length == 4);
	assert(symInfo["_D7winmain9myWinMainFPvPvPaiZi"].offsets.length == 3);
	assert(symInfo["_WinMain@16"].firstLine == 19);
	assert(symInfo["_WinMain@16"].offsets.length == 8);
	assert(symInfo["_WinMain@16"].offsets[3] == 1);
	assert(symInfo["_foo"].offsets.length == 2);
}

struct LineInfo
{
	string sym;
	int offset;
}

// map line in source to symbol and offset in object file
LineInfo[] readLineInfoFile(string linefile, string srcfile)
{
	__gshared static Regex!char reoffline;
	if(reoffline.empty)
		reoffline = regex(r"^Off 0x([0-9A-Fa-f]+): *Line ([0-9]+)$");   // Off 0x%x: Line %d

	srcfile = toLower(normalizePath(srcfile));
	string sym;
	bool curfile;
	LineInfo[] lineInfos;

	File linef = File(linefile);
	foreach(line; linef.byLine())
	{
		line = toUTF8Safe(line);
		line = strip(line);
		if (line.startsWith("Sym:"))
			sym = strip(line[4 .. $]).idup;
		else if (line.startsWith("File:"))
		{
			auto file = toLower(normalizePath(strip(line[5 .. $])));
			if (srcfile.contains('\\') != file.contains('\\'))
			{
				srcfile = srcfile[lastIndexOf(srcfile, '\\')+1 .. $];
				file = file[lastIndexOf(file, '\\')+1 .. $];
			}
			curfile = (srcfile == file);
		}
		else if (curfile)
		{
			auto rematch = match(line, reoffline);
			if (!rematch.empty())
			{
				int off = rematch.captures[1].to!uint(16);
				int ln = rematch.captures[2].to!uint(10);
				if (ln >= lineInfos.length)
					lineInfos.length = ln + 100;
				if (lineInfos[ln].sym.ptr is null)
					lineInfos[ln] = LineInfo(sym, off);
			}
		}
	}
	return lineInfos;
}

unittest
{
	string dumpline = r"
Sym: WinMain
File: WindowsApp1\winmain.d
	Off 0x0: Line 7
	Off 0x23: Line 9
	Off 0x2a: Line 18
	Off 0x37: Line 20
Sym: _D7winmain7WinMainWPvPvPaiZ2ehMFC6object9ThrowableZv
File: WindowsApp1\winmain.d
	Off 0x0: Line 11
	Off 0xc: Line 13
	Off 0x19: Line 14
	Off 0xfffffffe: Line 16" /* bad offset generated by DMD */ ~ "
";
	auto deleteme = "deleteme";
	std.file.write(deleteme, dumpline);
	scope(exit) std.file.remove(deleteme);

	auto infos = readLineInfoFile(deleteme, r"WindowsApp1\winmain.d");
	assert(infos.length > 20);
	assert(infos[7].sym == "WinMain" && infos[7].offset == 0);
	assert(infos[20].sym == "WinMain" && infos[20].offset == 0x37);
	assert(infos[13].sym == "_D7winmain7WinMainWPvPvPaiZ2ehMFC6object9ThrowableZv" && infos[13].offset == 0xc);
	assert(infos[14].sym == "_D7winmain7WinMainWPvPvPaiZ2ehMFC6object9ThrowableZv" && infos[14].offset == 0x19);
}
