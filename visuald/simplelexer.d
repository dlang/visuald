// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module simplelexer;

//import idl.vsi.textmgr;
import sdk.port.vsi;

import std.ctype;
import std.utf;
import std.uni;
import std.conv;

// current limitations:
// - nested comments must not nest more than 255 times
// - braces must not nest more than 4095 times inside token string
// - number of different delimiters must not exceed 256

enum TokenColor : int
{
	Text,
	Keyword,
	Comment,
	Identifier,
	String,
	Literal,
	Text2,
	Operator,

	DisabledKeyword,
	DisabledComment,
	DisabledIdentifier,
	DisabledString,
	DisabledLiteral,
	DisabledText,
	DisabledOperator
}

enum TokenType : int
{
	Unknown,
	Text,
	Keyword,
	Identifier,
	String,
	Literal,
	Operator,
	Delimiter,
	LineComment,
	Comment
}

struct TokenInfo
{
	TokenColor type;
	int StartIndex;
	int EndIndex;
}

///////////////////////////////////////////////////////////////////////////////

class SimpleLexer
{
	enum State
	{
		kWhite,
		kBlockComment,
		kNestedComment,
		kStringCStyle,
		kStringWysiwyg,
		kStringAltWysiwyg,
		kStringDelimited,
		kStringDelimitedNestedBracket,
		kStringDelimitedNestedParen,
		kStringDelimitedNestedBrace,
		kStringDelimitedNestedAngle,
		kStringHex,    // for now, treated as State.kStringWysiwyg
		kStringToken,  // encoded by tokenStringLevel > 0
		kStringEscape, // removed in D2.026
	}

	// lexer scan state is: ___TTNNS
	// TT: token string nesting level
	// NN: comment nesting level/string delimiter id
	// S: State
	static State scanState(int state) { return cast(State) (state & 0xf); }
	static int nestingLevel(int state) { return (state >> 4) & 0xff; } // used for state kNestedComment and kStringDelimited
	static int tokenStringLevel(int state) { return (state >> 12) & 0xff; }
	static int getOtherState(int state) { return (state & 0xfff00000); }

	static int toState(State s, int nesting, int tokLevel, int otherState)
	{
		assert(s >= State.kWhite && s <= State.kStringDelimitedNestedAngle);
		assert(nesting < 32);
		assert(tokLevel < 32);

		return s | ((nesting & 0xff) << 4) | ((tokLevel & 0xff) << 12) | otherState;
	}

	static string[256] s_delimiters;
	static int s_nextDelimiter;

	static int getDelimiterIndex(string delim)
	{
		int idx = (s_nextDelimiter - 1) & 0xff;
		for( ; idx != s_nextDelimiter; idx = (idx - 1) & 0xff)
			if(delim == s_delimiters[idx])
				return idx;

		s_nextDelimiter = (s_nextDelimiter + 1) & 0xff;
		s_delimiters[idx] = delim;
		return idx;
	}

	static int scanIdentifier(wstring text, int startpos, ref uint pos)
	{
		while(pos < text.length)
		{
			uint nextpos = pos;
			dchar ch = decode(text, nextpos);
			if(!isIdentifierChar(ch) && !isdigit(ch))
				break;
			pos = nextpos;
		}
		string ident = toUTF8(text[startpos .. pos]);

		if(ident in keywords_map)
			return TokenColor.Keyword;

		return TokenColor.Identifier;
	}

	static int scanOperator(wstring text, int startpos, ref uint pos)
	{
		return TokenColor.Operator;
	}
	
	static dchar trydecode(wstring text, ref uint pos)
	{
		if(pos >= text.length)
			return 0;
		dchar ch = decode(text, pos);
		return ch;
	}

	static void skipDigits(wstring text, ref uint pos, int base)
	{
		while(pos < text.length)
		{
			uint nextpos = pos;
			dchar ch = decode(text, nextpos);
			if(ch != '_')
				if(base < 16 && (ch < '0' || ch >= '0' + base))
					break;
				else if(base == 16 && !isxdigit(ch))
					break;
			pos = nextpos;
		}
	}

	static int scanNumber(wstring text, dchar ch, ref uint pos)
	{
		// pos after first digit
		int base = 10;
		if(ch == '0')
		{
			uint prevpos = pos;
			ch = trydecode(text, pos);
			ch = tolower(ch);
			if(ch == 'b')
				base = 2;
			else if (ch == 'x')
				base = 16;
			else
			{
				base = 8;
				pos = prevpos;
			}
		}

		// pos now after prefix or first digit
		skipDigits(text, pos, base);
		// pos now after last digit of integer part

		uint nextpos = pos;
		ch = trydecode(text, nextpos);

		if((base == 10 && tolower(ch) == 'e') || (base == 16 && tolower(ch) == 'p'))
			goto L_exponent;
		if(base >= 10 && ch == '.')
		{
			// float
			pos = nextpos;
			skipDigits(text, pos, base);

			nextpos = pos;
			ch = trydecode(text, nextpos);
			if((base == 10 && tolower(ch) == 'e') || (base == 16 && tolower(ch) == 'p'))
			{
L_exponent:
				// exponent
				pos = nextpos;
				ch = trydecode(text, nextpos);
				if(ch == '-' || ch == '+')
					pos = nextpos;
				skipDigits(text, pos, 10);
			}

			// suffix
			nextpos = pos;
			ch = trydecode(text, nextpos);
			if(ch == 'L' || toupper(ch) == 'F')
			{
				pos = nextpos;
				ch = trydecode(text, nextpos);
			}
			if(ch == 'i')
				pos = nextpos;
		}
		else
		{
			// check integer suffix
			if(toupper(ch) == 'U')
			{
				pos = nextpos;
				ch = trydecode(text, nextpos);
				if(ch == 'L')
					pos = nextpos;
			}
			else if (ch == 'L')
			{
				pos = nextpos;
				ch = trydecode(text, nextpos);
				if(toupper(ch) == 'U')
					pos = nextpos;
			}
		}
		return TokenColor.Literal;
	}

	static State scanBlockComment(wstring text, ref uint pos)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			while(ch == '*')
			{
				if (pos >= text.length)
					return State.kBlockComment;
				ch = decode(text, pos);
				if(ch == '/')
					return State.kWhite;
			}
		}
		return State.kBlockComment;
	}

	static State scanNestedComment(wstring text, ref uint pos, ref int nesting)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			while(ch == '/')
			{
				if (pos >= text.length)
					return State.kNestedComment;
				ch = decode(text, pos);
				if(ch == '+')
				{
					nesting++;
					goto nextChar;
				}
			}
			while(ch == '+')
			{
				if (pos >= text.length)
					return State.kNestedComment;
				ch = decode(text, pos);
				if(ch == '/')
				{
					nesting--;
					if(nesting == 0)
						return State.kWhite;
					break;
				}
			}
		nextChar:;
		}
		return State.kNestedComment;
	}

	static State scanStringWysiwyg(wstring text, ref uint pos)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == '"')
				return State.kWhite;
		}
		return State.kStringWysiwyg;
	}

	static State scanStringAltWysiwyg(wstring text, ref uint pos)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == '`')
				return State.kWhite;
		}
		return State.kStringAltWysiwyg;
	}

	static State scanStringCStyle(wstring text, ref uint pos, dchar term)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == '\\')
			{
				if (pos >= text.length)
					break;
				ch = decode(text, pos);
			}
			else if(ch == term)
				return State.kWhite;
		}
		return State.kStringCStyle;
	}

	static State startDelimiterString(wstring text, ref uint pos, ref int nesting)
	{
		nesting = 1;

		uint startpos = pos;
		dchar ch = trydecode(text, pos);
		State s = State.kStringDelimited;
		if(ch == '[')
			s = State.kStringDelimitedNestedBracket;
		else if(ch == '(')
			s = State.kStringDelimitedNestedParen;
		else if(ch == '{')
			s = State.kStringDelimitedNestedBrace;
		else if(ch == '<')
			s = State.kStringDelimitedNestedAngle;
		else
		{
			if(isIdentifierChar(ch))
				scanIdentifier(text, startpos, pos);
			string delim = toUTF8(text[startpos .. pos]);
			nesting = getDelimiterIndex(delim);
		}
		return s;
	}

	static bool isStartingComment(wstring txt, ref int idx)
	{
		if(idx >= 0 && idx < txt.length-1 && txt[idx] == '/' && (txt[idx+1] == '*' || txt[idx+1] == '+'))
			return true;
		if((txt[idx] == '*' || txt[idx] == '+') && idx > 0 && txt[idx-1] == '/')
		{
			idx--;
			return true;
		}
		return false;
	}
	
	static bool isEndingComment(wstring txt, ref int idx)
	{
		if(idx < txt.length && idx > 0 && txt[idx] == '/' && (txt[idx-1] == '*' || txt[idx-1] == '+'))
		{
			idx--;
			return true;
		}
		if(idx < txt.length-1 && idx >= 0 && (txt[idx] == '*' || txt[idx] == '+') && txt[idx+1] == '/')
			return true;
		return false;
	}
	
	static bool isIdentifierChar(dchar ch)
	{
		return isUniAlpha(ch) || ch == '_' || ch == '@';
	}
	
	static bool isIdentifier(S)(S text)
	{
		if(text.length == 0)
			return false;
		
		uint pos;
		dchar ch = decode(text, pos);
		if(!isIdentifierChar(ch))
			return false;
		
		while(pos < text.length)
		{
			ch = decode(text, pos);
			if(!isIdentifierChar(ch) && !isdigit(ch))
				return false;
		}
		return true;
	}

	static bool isInteger(S)(S text)
	{
		if(text.length == 0)
			return false;

		uint pos;
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(!isdigit(ch))
				return false;
		}
		return true;
	}
	
	static bool isBracketPair(dchar ch1, dchar ch2)
	{
		switch(ch1)
		{
		case '{': return ch2 == '}';
		case '}': return ch2 == '{';
		case '(': return ch2 == ')';
		case ')': return ch2 == '(';
		case '[': return ch2 == ']';
		case ']': return ch2 == '[';
		default:  return false;
		}
	}

	static bool isOpeningBracket(dchar ch)
	{
	    return ch == '[' || ch == '(' || ch == '{';
	}

	static bool isClosingBracket(dchar ch)
	{
	    return ch == ']' || ch == ')' || ch == '}';
	}

	static dchar openingBracket(State s)
	{
		switch(s)
		{
		case State.kStringDelimitedNestedBracket: return '[';
		case State.kStringDelimitedNestedParen:   return '(';
		case State.kStringDelimitedNestedBrace:   return '{';
		case State.kStringDelimitedNestedAngle:   return '<';
		default: break;
		}
		assert(0);
	}

	static dchar closingBracket(State s)
	{
		switch(s)
		{
		case State.kStringDelimitedNestedBracket: return ']';
		case State.kStringDelimitedNestedParen:   return ')';
		case State.kStringDelimitedNestedBrace:   return '}';
		case State.kStringDelimitedNestedAngle:   return '>';
		default: break;
		}
		assert(0);
	}

	static bool isCommentOrSpace(int type, wstring text)
	{
		return (type == TokenColor.Comment || (type == TokenColor.Text && isspace(text[0])));
	}

	static State scanNestedDelimiterString(wstring text, ref uint pos, State s, ref int nesting)
	{
		dchar open  = openingBracket(s);
		dchar close = closingBracket(s);

		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == open)
				nesting++;
			else if(ch == close && nesting > 0)
				nesting--;
			else if(ch == '"' && nesting == 0)
				return State.kWhite;
		}
		return s;
	}

	static State scanDelimitedString(wstring text, ref uint pos, int delim)
	{
		string delimiter = s_delimiters[delim];

		while(pos < text.length)
		{
			uint startpos = pos;
			dchar ch = decode(text, pos);
			if(isIdentifierChar(ch))
				scanIdentifier(text, startpos, pos);
			string ident = toUTF8(text[startpos .. pos]);
			if(ident == delimiter)
			{
				ch = decode(text, pos);
				if(ch == '"')
					return State.kWhite;
			}
		}
		return State.kStringDelimited;
	}

	static int scan(ref int state, in wstring text, ref uint pos)
	{
		State s = scanState(state);
		int nesting = nestingLevel(state);
		int tokLevel = tokenStringLevel(state);
		int otherState = getOtherState(state);

		int type = TokenColor.Text;
		uint startpos = pos;

		switch(s)
		{
		case State.kWhite:
			dchar ch = decode(text, pos);
			if(ch == 'r' || ch == 'x' || ch == 'q')
			{
				int prevpos = pos;
				dchar nch = trydecode(text, pos);
				if(nch == '"' && ch == 'q')
				{
					s = startDelimiterString(text, pos, nesting);
					if(s == State.kStringDelimited)
						goto case State.kStringDelimited;
					else
						goto case State.kStringDelimitedNestedBracket;
				}
				else if(tokLevel == 0 && ch == 'q' && nch == '{')
				{
					tokLevel = 1;
					break;
				}
				else if(nch == '"')
				{
					goto case State.kStringWysiwyg;
				}
				else
				{
					pos = prevpos;
					type = scanIdentifier(text, startpos, pos);
				}
			}
			else if(isIdentifierChar(ch))
				type = scanIdentifier(text, startpos, pos);
			else if(isdigit(ch))
				type = scanNumber(text, ch, pos);
			else if (ch == '/')
			{
				int prevpos = pos;
				ch = trydecode(text, pos);
				if (ch == '/')
				{
					// line comment
					type = TokenColor.Comment;
					pos = text.length;
				}
				else if (ch == '*')
				{
					s = scanBlockComment(text, pos);
					type = TokenColor.Comment;
				}
				else if (ch == '+')
				{
					nesting = 1;
					s = scanNestedComment(text, pos, nesting);
					type = TokenColor.Comment;
				}
				else
				{
					// step back to position after '/'
					pos = prevpos;
					type = scanOperator(text, startpos, pos);
				}
			}
			else if (ch == '"')
				goto case State.kStringCStyle;

			else if (ch == '`')
				goto case State.kStringAltWysiwyg;
			
			else if (ch == '\'')
			{
				s = scanStringCStyle(text, pos, '\'');
				type = TokenColor.String;
			}
			else if (tokLevel > 0)
			{
				if(ch == '{')
					tokLevel++;
				if (ch == '}')
					tokLevel--;
				type = TokenColor.String;
			}
			else if(!isspace(ch))
				type = scanOperator(text, startpos, pos);
			break;

		case State.kBlockComment:
			s = scanBlockComment(text, pos);
			type = TokenColor.Comment;
			break;

		case State.kNestedComment:
			s = scanNestedComment(text, pos, nesting);
			type = TokenColor.Comment;
			break;

		case State.kStringCStyle:
			s = scanStringCStyle(text, pos, '"');
			type = TokenColor.String;
			break;

		case State.kStringWysiwyg:
			s = scanStringWysiwyg(text, pos);
			type = TokenColor.String;
			break;

		case State.kStringAltWysiwyg:
			s = scanStringAltWysiwyg(text, pos);
			type = TokenColor.String;
			break;

		case State.kStringDelimited:
			s = scanDelimitedString(text, pos, nesting);
			type = TokenColor.String;
			break;

		case State.kStringDelimitedNestedBracket:
		case State.kStringDelimitedNestedParen:
		case State.kStringDelimitedNestedBrace:
		case State.kStringDelimitedNestedAngle:
			s = scanNestedDelimiterString(text, pos, s, nesting);
			type = TokenColor.String;
			break;

		default:
			break;
		}
		state = toState(s, nesting, tokLevel, otherState);
		return tokLevel > 0 ? TokenColor.String : type;
	}
}

///////////////////////////////////////////////////////////////
TokenInfo[] ScanLine(int iState, wstring text)
{
	TokenInfo[] lineInfo;
	for(uint pos = 0; pos < text.length; )
	{
		TokenInfo info;
		info.StartIndex = pos;
		info.type = cast(TokenColor) SimpleLexer.scan(iState, text, pos);
		info.EndIndex = pos;
		lineInfo ~= info;
	}
	return lineInfo;
}

///////////////////////////////////////////////////////////////

__gshared int[string] keywords_map; // maps to TOK enumerator

shared static this() 
{
	foreach(i, s; keywords)
	    keywords_map[s] = i;
}

const string keywords[] = 
[
	"this",
	"super",
	"assert",
	"null",
	"true",
	"false",
	"cast",
	"new",
	"delete",
	"throw",
	"module",
	"pragma",
	"typeof",
	"typeid",
	"template",

	"void",
	"byte",
	"ubyte",
	"short",
	"ushort",
	"int",
	"uint",
	"long",
	"ulong",
	"cent",
	"ucent",
	"float",
	"double",
	"real",
	"bool",
	"char",
	"wchar",
	"dchar",
	"ifloat",
	"idouble",
	"ireal",

	"cfloat",
	"cdouble",
	"creal",

	"delegate",
	"function",

	"is",
	"if",
	"else",
	"while",
	"for",
	"do",
	"switch",
	"case",
	"default",
	"break",
	"continue",
	"synchronized",
	"return",
	"goto",
	"try",
	"catch",
	"finally",
	"with",
	"asm",
	"foreach",
	"foreach_reverse",
	"scope",

	"struct",
	"class",
	"interface",
	"union",
	"enum",
	"import",
	"mixin",
	"static",
	"final",
	"const",
	"typedef",
	"alias",
	"override",
	"abstract",
	"volatile",
	"debug",
	"deprecated",
	"in",
	"out",
	"inout",
	"lazy",
	"auto",

	"align",
	"extern",
	"private",
	"package",
	"protected",
	"public",
	"export",

	"body",
	"invariant",
	"unittest",
	"version",
	//{	"manifest",	TOKmanifest	},

	// Added after 1.0
	"ref",
	"macro",
	"pure",
	"nothrow",
	"__thread",
	"__traits",
	"__overloadset",
	"__FILE__",
	"__LINE__",
	"shared",
	"immutable",
	
	"@disable",
	"@property",
	"@safe",
	"@system",
	"@trusted",
	
];

string genKeywordsEnum(string[] kwords)
{
	string enums = "enum {";
	foreach(kw; kwords)
	{
		if(kw[0] == '@')
			kw = kw[1..$];
		enums ~= "TOK_" ~ kw ~ ",";
	}
	enums ~= "TOK_numKeywords }";
	return enums;
}

mixin(genKeywordsEnum(keywords));

const string[] operators =
[
	"lcurly",           "{",
	"rcurly",           "}",
	"lparen",           "(",
	"rparen",           ")",
	"lbracket",         "[",
	"rbracket",         "]",
	"semicolon",        ";",
	"colon",            ":",
	"comma",            ",",
	"dot",              ".",
	"xor",              "^",
	"xorass",           "^=",
	"assign",           "=",
	"lt",               "<",
	"gt",               ">",
	"le",               "<=",
	"ge",               ">=",
	"equal",            "==",
	"notequal",         "!=",

	"unord",            "!<>=",
	"ue",               "!<>",
	"lg",               "<>",
	"leg",              "<>=",
	"ule",              "!>",
	"ul",               "!>=",
	"uge",              "!<",
	"ug",               "!<=",

	"not",              "!",
	"shl",              "<<",
	"shr",              ">>",
	"ushr",             ">>>",
	"add",              "+",
	"min",              "-",
	"mul",              "*",
	"div",              "/",
	"mod",              "%",
	"slice",            "..",
	"dotdotdot",        "...",
	"and",              "&",
	"andand",           "&&",
	"or",               "|",
	"oror",             "||",
	"array",            "[]",
//	"address",          "&",
//	"star",             "*",
	"tilde",            "~",
	"dollar",           "$",
	"plusplus",         "++",
	"minusminus",       "--",
//	"preplusplus",      "++",
//	"preminusminus",    "--",
	"question",         "?",
//	"neg",              "-",
//	"uadd",             "+",
	"addass",           "+=",
	"minass",           "-=",
	"mulass",           "*=",
	"divass",           "/=",
	"modass",           "%=",
	"shlass",           "<<=",
	"shrass",           ">>=",
	"ushrass",          ">>>=",
	"andass",           "&=",
	"orass",            "|=",
	"catass",           "~=",
//	"cat",              "~",
//	"identity",         "is",
//	"notidentity",      "!is",

	"pow",              "^^",
	"powass",           "^^=",

/+
	"plus",             "++",
	"pow",              "^^",
	"powass",           "^^==",
	"minus",            "--",
+/
];

string genOperatorEnum(string[] ops)
{
	string enums = "enum {";
	for(int o = 0; o < ops.length; o += 2)
	{
		enums ~= "TOK_" ~ ops[o] ~ ",";
	}
	enums ~= "TOK_numOperators }";
	return enums;
}

mixin(genOperatorEnum(operators));

enum TOK_error = -1;

bool _stringEqual(string s1, string s2, int length)
{
	if(s1.length < length || s2.length < length)
		return false;
	for(int i = 0; i < length; i++)
		if(s1[i] != s2[i])
			return false;
	return true;
}

string genOperatorParser(string peekch, string getch)
{
	// create sorted list of operators
	int[] opIndex;
	for(int o = 0; o < operators.length; o += 2)
	{
		string op = operators[o+1];
		int p = 0;
		while(p < opIndex.length)
		{
			assert(op != operators[opIndex[p]+1], "duplicate operator " ~ op);
			if(op < operators[opIndex[p]+1])
				break;
			p++;
		}
		// array slicing does not work in CTFE?
		// opIndex ~= opIndex[0..p] ~ o ~ opIndex[p..$];
		int[] nIndex;
		for(int i = 0; i < p; i++)
			nIndex ~= opIndex[i];
		nIndex ~= o;
		for(int i = p; i < opIndex.length; i++)
			nIndex ~= opIndex[i];
		opIndex = nIndex;
	}
	
	int matchlen = 0;
	string indent = "";
	string[] defaults = [ "error" ];
	string txt = indent ~ "dchar ch;\n";
	for(int o = 0; o < opIndex.length; o++)
	{
		string op = operators[opIndex[o]+1];
		string nextop;
		if(o + 1 < opIndex.length)
			nextop = operators[opIndex[o+1]+1];
		
		while(op.length > matchlen)
		{
			if(matchlen > 0)
				txt ~= indent ~ "case '" ~ op[matchlen-1] ~ "':\n";
			indent ~= "  ";
			txt ~= indent ~ "ch = " ~ getch ~ ";\n";
			txt ~= indent ~ "switch(ch)\n";
			txt ~= indent ~ "{\n";
			indent ~= "  ";
			int len = (matchlen > 0 ? matchlen - 1 : 0);
			while(len > 0 && defaults[len] == defaults[len+1])
				len--;
			txt ~= indent ~ "default: len = " ~ to!string(len) ~ "; return TOK_" ~ defaults[$-1] ~ ";\n";
			//txt ~= indent ~ "case '" ~ op[matchlen] ~ "':\n";
			defaults ~= defaults[$-1];
			matchlen++;
		}
		if(nextop.length > matchlen && nextop[0..matchlen] == op)
		{
			if(matchlen > 0)
				txt ~= indent ~ "case '" ~ op[matchlen-1] ~ "':\n";
			indent ~= "  ";
			txt ~= indent ~ "ch = " ~ getch ~ ";\n";
			txt ~= indent ~ "switch(ch)\n";
			txt ~= indent ~ "{\n";
			indent ~= "  ";
			txt ~= indent ~ "default: len = " ~ to!string(matchlen) ~ "; return TOK_" ~ operators[opIndex[o]] ~ "; // " ~ op ~ "\n";
			defaults ~= operators[opIndex[o]];
			matchlen++;
		}
		else
		{
			txt ~= indent ~ "case '" ~ op[matchlen-1] ~ "': len = " ~ to!string(matchlen) ~ "; return TOK_" ~ operators[opIndex[o]] ~ "; // " ~ op ~ "\n";
		
			while(nextop.length < matchlen || (matchlen > 0 && !_stringEqual(op, nextop, matchlen-1)))
			{
				matchlen--;
				indent = indent[0..$-2];
				txt ~= indent ~ "}\n";
				indent = indent[0..$-2];
				defaults = defaults[0..$-1];
			}
		}
	}
	return txt;
}

// pragma(msg, genOperatorParser("peekch()", "getch()"));

int parseOperator()
{
	dchar getch() { return 0; }
	int len;

	mixin(genOperatorParser("peekch()", "getch()"));
}

