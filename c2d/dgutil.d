// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module c2d.dgutil;

import std.string;
import std.ascii;
import std.utf;
import std.path;
import std.array;
import core.exception;

//////////////////////////////////////////////////////////////////////////////

class SyntaxException : Exception
{
	this(string msg)
	{
		super(msg);
		count++;
	}

	static int count;
}

void throwException(string msg)
{
	throw new SyntaxException(msg);
}

void throwException(int line, string msg)
{
	throw new SyntaxException(format("(%d): ", line) ~ msg);
}

void assume(T)(T cond, int line = __LINE__, string file = __FILE__)
{
	debug if(!cond)
		throw new AssertError(file, line);
	assert(cond);
}

void assume(T)(T cond, string msg, int line = __LINE__, string file = __FILE__)
{
	debug if(!cond)
		throw new AssertError(msg, file, line);
	assert(cond);
}

//////////////////////////////////////////////////////////////////////////////

string getNameWithoutExt(string fname)
{
	string bname = baseName(fname);
	string name = stripExtension(bname);
	if(name.length == 0)
		name = bname;
	return name;
}

//////////////////////////////////////////////////////////////////////////////

string reindent(string txt, int indent, int tabsize)
{
	string ntxt;
	size_t pos = 0;
	for( ; ; )
	{
		ptrdiff_t p = indexOf(txt[pos .. $], '\n');
		if(p < 0)
			break;
		ntxt ~= txt[pos .. pos + p + 1];
		pos += p + 1;
		int indentation = 0;
		for(p = pos; p < txt.length; p++)
		{
			if(txt[p] == ' ')
				indentation++;
			else if(txt[p] == '\t')
				indentation = tabsize == 0 ? (indentation + 8) & ~7 : ((indentation + tabsize) / tabsize) * tabsize;
			else
				break;
		}
		indentation += indent;
		if(indentation < 0)
			indentation = 0;

		string spaces = replicate("\t", tabsize == 0 ? 0 : indentation / tabsize)
			          ~ replicate(" ", tabsize == 0 ? indentation : indentation % tabsize);
		ntxt ~= spaces;
		pos = p;
	}
	ntxt ~= txt[pos .. $];
	return ntxt;
}

string cpp_string(string txt)
{
	string ntxt;
	bool escapeNext = false;
	foreach(dchar ch; txt)
	{
		if(escapeNext)
		{
			switch(ch)
			{
			case '\\': ch = '\\'; break;
			case 'a':  ch = '\a'; break;
			case 'r':  ch = '\r'; break;
			case 'n':  ch = '\n'; break;
			case 't':  ch = '\t'; break;
			case '"':  ch = '\"'; break;
			case '\'': ch = '\''; break;
			default:   break;
			}
			escapeNext = false;
		}
		else if(ch == '\\')
		{
			escapeNext = true;
			continue;
		}
		ntxt ~= toUTF8((&ch)[0..1]);
	}
	return ntxt;
}

string removeDuplicateEmptyLines(string txt)
{
	string ntxt;
	size_t npos = 0;
	size_t pos = 0;
	while(pos < txt.length)
	{
		dchar ch = decode(txt, pos);
		if(ch == '\n')
		{
			uint nl = 0;
			size_t nlpos = pos; // positions after nl
			size_t lastnlpos = pos;
			while(pos < txt.length)
			{
				ch = decode(txt, pos);
				if(ch == '\n')
				{
					nl++;
					lastnlpos = pos;
				}
				else if(!isWhite(ch))
					break;
			}
			if(nl > 1)
			{
				ntxt ~= txt[npos .. nlpos];
				ntxt ~= '\n';
				npos = lastnlpos;
			}
		}
	}
	ntxt ~= txt[npos .. pos];
	return ntxt;
}

unittest
{
	string txt;
	txt = removeDuplicateEmptyLines("abc\n\n\nefg");
	assume(txt == "abc\n\nefg");
	txt = removeDuplicateEmptyLines("abc\n\nefg");
	assume(txt == "abc\n\nefg");
}

//////////////////////////////////////////////////////////////////////////////

unittest
{
	string txt =
		"\nvoid foo()\n"
		~ "{\n"
		~ "    if(1)\n"
		~ "\tx = 0;\n"
		~ "}";
	string exp =
		"\n    void foo()\n"
		~ "    {\n"
		~ "\tif(1)\n"
		~ "\t    x = 0;\n"
		~ "    }";

	string res = reindent(txt, 4, 8);
	assume(res == exp);
}

