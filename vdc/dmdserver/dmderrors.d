// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2019 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.dmderrors;

import dmd.console;
import dmd.errors;
import dmd.globals;

import std.ascii;
import std.string;

import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.wchar_ : wcslen;

shared(Object) gErrorSync = new Object;
private __gshared // under gErrorSync lock
{
	string gErrorFile;
	string gErrorMessages;
	string gOtherErrorMessages;

	private string gLastHeader;
	private string[] gLastErrorMsgs; // all but first are supplemental
	private Loc[] gLastErrorLocs;
}

void flushLastError()
{
	if (gLastErrorLocs.empty)
		return;
	assert(gLastErrorLocs.length == gLastErrorMsgs.length);

	char[1014] buf;
	char[] genErrorMessage(size_t pos)
	{
		char[] msg;
		if (pos < gLastErrorLocs.length)
		{
			Loc loc = gLastErrorLocs[pos];
			int len = snprintf(buf.ptr, buf.length, "%d,%d,%d,%d:", loc.linnum, loc.charnum - 1, loc.linnum, loc.charnum);
			msg ~= buf[0..len];
		}

		msg ~= gLastHeader;
		for (size_t i = 0; i < gLastErrorLocs.length; i++)
		{
			if (i > 0)
				msg ~= "\a";

			Loc loc = gLastErrorLocs[i];
			if (i == pos)
			{
				if (i > 0)
					msg ~= "--> ";
			}
			else if (loc.filename)
			{
				int len = snprintf(buf.ptr, buf.length, "%s(%d): ", loc.filename, loc.linnum);
				msg ~= buf[0..len];
			}
			msg ~= gLastErrorMsgs[i];
		}
		return msg;
	}

	size_t otherLocs;
	foreach (loc; gLastErrorLocs)
		if (!loc.filename || _stricmp(loc.filename, gErrorFile) != 0)
			otherLocs++;

	if (otherLocs == gLastErrorLocs.length)
	{
		gOtherErrorMessages ~= genErrorMessage(size_t.max) ~ "\n";
	}
	else
	{
		for (size_t i = 0; i < gLastErrorLocs.length; i++)
		{
			Loc loc = gLastErrorLocs[i];
			if (loc.filename && _stricmp(loc.filename, gErrorFile) == 0)
			{
				gErrorMessages ~= genErrorMessage(i) ~ "\n";
				gLastHeader = "Info: ";
			}
		}
	}

	gLastHeader = null;
	gLastErrorLocs.length = 0;
	gLastErrorMsgs.length = 0;
}

bool errorPrint(const ref Loc loc, Color headerColor, const(char)* header,
				const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null) nothrow
{
	if (!loc.filename)
		return true;

	try synchronized(gErrorSync)
	{
		bool other = _stricmp(loc.filename, gErrorFile) != 0;
		while (header && std.ascii.isWhite(*header))
			header++;
		bool supplemental = !header || !*header;

		if (!supplemental)
			flushLastError();

		__gshared char[4096] buf;
		int len = 0;
		if (header && *header)
			gLastHeader = header[0..strlen(header)].idup;
		if (p1 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p1);
		if (p2 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p2);
		if (len < buf.length)
			len += vsnprintf(buf.ptr + len, buf.length - len, format, ap);

		gLastErrorMsgs ~= buf[0..len].dup;
		gLastErrorLocs ~= loc;
	}
	catch(Exception e)
	{
		// tame synchronized "throwing"
	}
	return true;
}

void initErrorMessages(string fname)
{
	synchronized(gErrorSync)
	{
		gErrorFile = fname;
		gErrorMessages = null;
		gOtherErrorMessages = null;

		gLastErrorLocs = null;
		gLastErrorMsgs = null;

		import std.functional;
		diagnosticHandler = toDelegate(&errorPrint);
	}
}

string getErrorMessages(bool other = false)
{
	synchronized(gErrorSync)
	{
		flushLastError();
		return other ? gOtherErrorMessages : gErrorMessages;
	}
}

int _stricmp(const(char)*str1, string s2) nothrow
{
	const(char)[] s1 = str1[0..strlen(str1)];
	return icmp(s1, s2);
}

int _stricmp(const(wchar)*str1, wstring s2) nothrow
{
	const(wchar)[] s1 = str1[0..wcslen(str1)];
	return icmp(s1, s2);
}

