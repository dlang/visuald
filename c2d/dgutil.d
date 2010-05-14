// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module dgutil;

import std.string;
import std.ctype;

//////////////////////////////////////////////////////////////////////////////

class SyntaxException : Exception
{
	this(string msg) { super(msg); }
}

void throwException(string msg)
{
	throw new SyntaxException(msg);
}

void throwException(int line, string msg)
{
	throw new SyntaxException(format("(%d):", line) ~ msg);
}

//////////////////////////////////////////////////////////////////////////////

string reindent(string txt, int indent, int tabsize)
{
	string ntxt;
	int pos = 0;
	for( ; ; )
	{
		int p = indexOf(txt[pos .. $], '\n');
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
				indentation = ((indentation + tabsize) / tabsize) * tabsize;
			else
				break;
		}
		indentation += indent;
		if(indentation < 0)
			indentation = 0;
		
		string spaces = repeat("\t", indentation / tabsize) ~ repeat(" ", indentation % tabsize);
		ntxt ~= spaces;
		pos = p;
	}
	ntxt ~= txt[pos .. $];
	return ntxt;
}

//////////////////////////////////////////////////////////////////////////////

unittest
{
	string txt = "\nvoid foo()\n"
	             "{\n"
		     "    if(1)\n"
		     "\tx = 0;\n"
		     "}";
	string exp = "\n    void foo()\n"
	             "    {\n"
		     "\tif(1)\n"
		     "\t    x = 0;\n"
		     "    }";

	string res = reindent(txt, 4, 8);
	assert(res == exp);
}

