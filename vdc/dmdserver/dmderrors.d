
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
__gshared string gErrorFile;
__gshared char[] gErrorMessages;
__gshared char[] gOtherErrorMessages;
__gshared bool gErrorWasSupplemental;

void errorPrint(const ref Loc loc, Color headerColor, const(char)* header,
				const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null) nothrow
{
	if (!loc.filename)
		return;

	try synchronized(gErrorSync)
	{
		bool other = _stricmp(loc.filename, gErrorFile) != 0;
		while (header && std.ascii.isWhite(*header))
			header++;
		bool supplemental = !header && !*header;

		__gshared char[4096] buf;
		int len = 0;
		if (other)
		{
			len = snprintf(buf.ptr, buf.length, "%s(%d):", loc.filename, loc.linnum);
		}
		else
		{
			int llen = snprintf(buf.ptr, buf.length, "%d,%d,%d,%d:", loc.linnum, loc.charnum - 1, loc.linnum, loc.charnum);
			gErrorMessages ~= buf[0..llen];
			if (supplemental)
				gErrorMessages ~= gOtherErrorMessages;
			gOtherErrorMessages = null;
		}
		if (p1 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p1);
		if (p2 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p2);
		if (len < buf.length)
			len += vsnprintf(buf.ptr + len, buf.length - len, format, ap);
		char nl = other ? '\a' : '\n';
		if (len < buf.length)
			buf[len++] = nl;
		else
			buf[$-1] = nl;

		version(DebugServer) dbglog(buf[0..len]);

		if (other)
		{
			if (gErrorWasSupplemental)
			{
				if (gErrorMessages.length && gErrorMessages[$-1] == '\n')
					gErrorMessages[$-1] = '\a';
				gErrorMessages ~= buf[0..len];
				gErrorMessages ~= '\n';
			}
			else if (supplemental)
				gOtherErrorMessages ~= buf[0..len];
			else
			{
				gErrorWasSupplemental = false;
				gOtherErrorMessages = buf[0..len].dup;
			}
		}
		else
		{
			gErrorMessages ~= buf[0..len];
			gErrorWasSupplemental = supplemental;
		}
	}
	catch(Exception e)
	{

	}
}

void initErrorFile(string fname)
{
	synchronized(gErrorSync)
	{
		gErrorFile = fname;
		gErrorMessages = null;
		gOtherErrorMessages = null;
		gErrorWasSupplemental = false;

		import std.functional;
		diagnosticHandler = toDelegate(&errorPrint);
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

