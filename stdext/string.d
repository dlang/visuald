// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module stdext.string;

import std.utf;
import std.string;
import std.ascii;
import std.conv;
import std.array;

size_t endofStringCStyle(string text, size_t pos, dchar term = '\"', dchar esc = '\\')
{
	while(pos < text.length)
	{
		dchar ch = decode(text, pos);
		if(ch == esc)
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

string[] tokenizeArgs(string text, bool semi_is_seperator = true, bool space_is_seperator = true)
{
	string[] args;
	size_t pos = 0;
	while(pos < text.length)
	{
		size_t startpos = pos;
		dchar ch = decode(text, pos);
		if(isWhite(ch))
			continue;

		size_t endpos = pos;
		while(pos < text.length)
		{
			if(ch == '\"')
			{
				pos = endofStringCStyle(text, pos, '\"', 0);
				ch = 0;
			}
			else
			{
				ch = decode(text, pos);
			}
			if(isWhite(ch) && (space_is_seperator || ch != ' '))
				break;
			if(semi_is_seperator && ch == ';')
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

	if (endofStringCStyle(arg, 1, '\"', 0) != arg.length)
		return arg;

	return arg[1..$-1];
}

string replaceCrLfSemi(string s)
{
	return replace(replace(s, "\n", ";"), "\r", "");
}

string replaceSemiCrLf(string s)
{
	return replace(s, ";", "\r\n");
}

string insertCr(string s)
{
	string ns;
	while(s.length > 0)
	{
		auto p = s.indexOf('\n');
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

version(unittest)
unittest
{
	string t = insertCr("a\nb\r\ncd\n\ne\n\r\nf");
	assert(t == "a\r\nb\r\ncd\r\n\r\ne\r\n\r\nf");
}

S escapeString(S)(S s)
{
	s = replace(s, "\\"w, "\\\\"w);
	s = replace(s, "\t"w, "\\t"w);
	s = replace(s, "\r"w, "\\r"w);
	s = replace(s, "\n"w, "\\n"w);
	return s;
}

int countVisualSpaces(S)(S txt, int tabSize, int* txtpos = null)
{
	int p = 0;
	int n = 0;
	while(n < txt.length && isWhite(txt[n]))
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

int visiblePosition(S)(S txt, int tabSize, int idx)
{
	if(idx > txt.length)
		idx = cast(int)txt.length;

	int p = 0;

	for(int n = 0; n < idx; n++)
		if(txt[n] == '\t')
			p = p + tabSize - (p % tabSize);
		else
			p++;

	return p;
}

int nextTabPosition(int n, int tabSize)
{
	return n + tabSize - n % tabSize;
}

S createVisualSpaces(S)(int n, int tabSize, int tabOff = 0)
{
	S s;
	if(tabSize < 2)
	{
		for(int i = 0; i < n; i++)
			s ~= " ";
	}
	else
	{
		while (n > 0 && tabOff > 0 && tabOff < tabSize)
		{
			s ~= " ";
			tabOff++;
			n--;
		}
		while(n >= tabSize)
		{
			s ~= "\t";
			n -= tabSize;
		}
		while(n > 0)
		{
			s ~= " ";
			n--;
		}
	}
	return s;
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
			while(r < q && !isWhite(s[r]))
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

//alias startsWith _startsWith;

// munch deprecated in phobos
inout(char)[] _munch(ref inout(char)[] s, const(char)[] pattern) @safe pure @nogc
{
	size_t j = s.length;
	foreach (i, dchar c; s)
	{
		if (pattern.indexOf(c) < 0)
		{
			j = i;
			break;
		}
	}
	auto head = s[0 .. j];
	s = s[j .. $];
	return head;
}

bool parseLong(ref const(char)[] txt, out long res)
{
	_munch(txt, " \t\n\r");
	int n = 0;
	while(n < txt.length && isDigit(txt[n]))
		n++;
	if(n <= 0)
		return false;
	res = to!long(txt[0..n]);
	txt = txt[n..$];
	return true;
}

inout(char)[] parseNonSpace(ref inout(char)[] txt)
{
	_munch(txt, " \t\n\r");
	int n = 0;
	while(n < txt.length && !isWhite(txt[n]))
		n++;
	auto res = txt[0..n];
	txt = txt[n..$];
	return res;
}

T[] firstLine(T)(T[] s)
{
	for(size_t i = 0; i < s.length; i++)
		if(s[i] == '\n' || s[i] == '\r')
			return s[0..i];
	return s;
}

char kInvalidUTF8Replacement = '?';

inout(char)[] toUTF8Safe(inout(char)[] text)
{
	char[] modtext;
	for(size_t p = 0; p < text.length; p++)
	{
		ubyte ch = text[p];
		if((ch & 0xc0) == 0xc0)
		{
			auto q = p;
			for(int s = 0; s < 5 && ((ch << s) & 0xc0) == 0xc0; s++, q++)
				if(q >= text.length || (text[q] & 0xc0) != 0x80)
					goto L_invalid;
			p = q;
		}
		else if(ch & 0x80)
		{
		L_invalid:
			if(modtext.length == 0)
				modtext = text.dup;
			modtext[p] = kInvalidUTF8Replacement;
		}
	}
	if(modtext.length)
		return cast(inout(char)[]) modtext;
	return text;
}

string toUTF8Safe(const(wchar)[] text)
{
	wchar[] modtext;
	void invalidChar(size_t pos)
	{
		if(modtext.length == 0)
			modtext = text.dup;
		modtext[pos] = kInvalidUTF8Replacement;
	}

	for(size_t p = 0; p < text.length; p++)
	{
		ushort ch = text[p];
		if(ch >= 0xD800 && ch <= 0xDFFF)
		{
			if(p + 1 >= text.length)
				invalidChar(p);
			else
			{
				if (text[p+1] < 0xD800 || text[p+1] > 0xDFFF)
				{
					invalidChar(p);   // invalid surragate pair
					invalidChar(p+1);
				}
				p++;
			}
		}
	}
	return toUTF8(modtext.length ? modtext : text);
}

string toUTF8Safe(const(dchar)[] text)
{
	dchar[] modtext;
	for(size_t p = 0; p < text.length; p++)
		if(!isValidDchar(text[p]))
		{
			if(modtext.length == 0)
				modtext = text.dup;
			modtext[p] = kInvalidUTF8Replacement;
		}
	return toUTF8(modtext.length ? modtext : text);
}

dchar decodeBwd(Char)(const(Char) txt, ref size_t pos)
{
	assert(pos > 0);
	uint len = strideBack(txt, pos);
	pos -= len;
	size_t p = pos;
	dchar ch = decode(txt, p);
	assert(pos + len == p);
	return ch;
}

bool isASCIIString(string s)
{
	foreach (dchar c; s)
		if (!isASCII(c))
			return false;
	return true;
}

/*
* Expand an OMF, DMD-generated compressed identifier into its full form
*
* This function only has a visible effect for OMF binaries (Win32),
* as compression is otherwise not used.
*
* See_Also: `compiler/src/dmd/backend/compress.d`
*
* copied from druntime as this function is removed for dmd 2.110
*/
string decodeDmdString( const(char)[] ln, ref size_t p ) nothrow pure @safe
{
	string s;
	uint zlen, zpos;

	static bool isAlpha( char val )
	{
		return ('a' <= val && 'z' >= val) ||
			('A' <= val && 'Z' >= val) ||
			(0x80 & val); // treat all unicode as alphabetic
	}
	static bool isDigit( char val ) nothrow
	{
		return '0' <= val && '9' >= val;
	}

	// decompress symbol
	while ( p < ln.length )
	{
		int ch = cast(ubyte) ln[p++];
		if ( (ch & 0xc0) == 0xc0 )
		{
			zlen = (ch & 0x7) + 1;
			zpos = ((ch >> 3) & 7) + 1; // + zlen;
			if ( zpos > s.length )
				break;
			s ~= s[$ - zpos .. $ - zpos + zlen];
		}
		else if ( ch >= 0x80 )
		{
			if ( p >= ln.length )
				break;
			int ch2 = cast(ubyte) ln[p++];
			zlen = (ch2 & 0x7f) | ((ch & 0x38) << 4);
			if ( p >= ln.length )
				break;
			int ch3 = cast(ubyte) ln[p++];
			zpos = (ch3 & 0x7f) | ((ch & 7) << 7);
			if ( zpos > s.length )
				break;
			s ~= s[$ - zpos .. $ - zpos + zlen];
		}
		else if ( isAlpha(cast(char)ch) || isDigit(cast(char)ch) || ch == '_' )
			s ~= cast(char) ch;
		else
		{
			p--;
			break;
		}
	}
	return s;
}
