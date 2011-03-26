// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module simplelexer;

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
	DisabledOperator,

	StringKeyword,
	StringComment,
	StringIdentifier,
	StringString,
	StringLiteral,
	StringText,
	StringOperator,
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
		kStringTokenFirst,  // after 'q', but before '{' to pass '{' as single operator
		kStringToken,  // encoded by tokenStringLevel > 0
		kStringHex,    // for now, treated as State.kStringWysiwyg
		kStringEscape, // removed in D2.026, not supported
	}

	// lexer scan state is: ___TTNNS
	// TT: token string nesting level
	// NN: comment nesting level/string delimiter id
	// S: State
	static State scanState(int state) { return cast(State) (state & 0xf); }
	static int nestingLevel(int state) { return (state >> 4) & 0xff; } // used for state kNestedComment and kStringDelimited
	static int tokenStringLevel(int state) { return (state >> 12) & 0xff; }
	static int getOtherState(int state) { return (state & 0xfff00000); }

	static bool sTokenizeTokenString = true;
	static bool sSplitNestedComments = true;
	static bool sAllowDollarInIdentifiers = false;
	
	static int toState(State s, int nesting, int tokLevel, int otherState)
	{
		static assert(State.kStringToken <= 15);
		assert(s >= State.kWhite && s <= State.kStringToken);
		assert(nesting < 32);
		assert(tokLevel < 32);

		return s | ((nesting & 0xff) << 4) | ((tokLevel & 0xff) << 12) | otherState;
	}

	static bool isStringState(State state) { return state >= State.kStringCStyle; }
	static bool isCommentState(State state) { return state == State.kBlockComment || state == State.kNestedComment; }

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

	static int scanIdentifier(S)(S text, int startpos, ref uint pos, int* pid = null)
	{
		while(pos < text.length)
		{
			uint nextpos = pos;
			dchar ch = decode(text, nextpos);
			if(!isIdentifierCharOrDigit(ch))
				break;
			pos = nextpos;
		}
		string ident = toUTF8(text[startpos .. pos]);

		if(int* pident = ident in keywords_map)
		{
			if(pid)
				*pid = *pident;
			return TokenColor.Keyword;
		}

		if(int* pident = ident in specials_map)
		{
			if(pid)
				*pid = TOK_StringLiteral;
			return TokenColor.String;
		}

		if(pid)
			*pid = TOK_Identifier;
		return TokenColor.Identifier;
	}

	static int scanOperator(S)(S text, uint startpos, ref uint pos, int* pid = null)
	{
		int len;
		int id = parseOperator(text, startpos, len);
		if(id == TOK_error)
			return TokenColor.Text;
		
		if(pid)
			*pid = id;
		pos = startpos + len;
		return TokenColor.Operator;
	}
	
	static dchar trydecode(S)(S text, ref uint pos)
	{
		if(pos >= text.length)
			return 0;
		dchar ch = decode(text, pos);
		return ch;
	}

	static void skipDigits(S)(S text, ref uint pos, int base)
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

	static int scanNumber(S)(S text, dchar ch, ref uint pos, int* pid = null)
	{
		// pos after first digit
		int base = 10;
		uint nextpos = pos;
		if(ch == '.')
			goto L_float;

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

		nextpos = pos;
		ch = trydecode(text, nextpos);

		if((base == 10 && tolower(ch) == 'e') || (base == 16 && tolower(ch) == 'p'))
			goto L_exponent;
		uint trypos = nextpos;
		if(base >= 8 && ch == '.' && trydecode(text, trypos) != '.') // ".." is the slice token
		{
			// float
			if(base < 10)
				base = 10;
L_float:
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
L_floatLiteral:
				pos = nextpos;
				ch = trydecode(text, nextpos);
			}
			if(ch == 'i')
L_complexLiteral:
				pos = nextpos;
			if(pid)
				*pid = TOK_FloatLiteral;
		}
		else
		{
			// check integer suffix
			if(ch == 'i')
				goto L_complexLiteral;
			if(toupper(ch) == 'F')
				goto L_floatLiteral;

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
				if(ch == 'i')
					goto L_complexLiteral;
				if(toupper(ch) == 'U')
					pos = nextpos;
			}
			if(pid)
				*pid = TOK_IntegerLiteral;
		}
		return TokenColor.Literal;
	}

	static State scanBlockComment(S)(S text, ref uint pos)
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

	static State scanNestedComment(S)(S text, uint startpos, ref uint pos, ref int nesting)
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
					if(sSplitNestedComments && pos > startpos + 2)
					{
						pos -= 2;
						return State.kNestedComment;
					}
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
					if(sSplitNestedComments)
						return State.kNestedComment;
					break;
				}
			}
		nextChar:;
		}
		return State.kNestedComment;
	}

	static State scanStringPostFix(S)(S text, ref uint pos)
	{
		uint nextpos = pos;
		dchar ch = trydecode(text, nextpos);
		if(ch == 'c' || ch == 'w' || ch == 'd')
			pos = nextpos;
		return State.kWhite;
	}
	
	static State scanStringWysiwyg(S)(S text, ref uint pos)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == '"')
				return scanStringPostFix(text, pos);
		}
		return State.kStringWysiwyg;
	}

	static State scanStringAltWysiwyg(S)(S text, ref uint pos)
	{
		while(pos < text.length)
		{
			dchar ch = decode(text, pos);
			if(ch == '`')
				return scanStringPostFix(text, pos);
		}
		return State.kStringAltWysiwyg;
	}

	static State scanStringCStyle(S)(S text, ref uint pos, dchar term)
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
				return scanStringPostFix(text, pos);
		}
		return State.kStringCStyle;
	}

	static State startDelimiterString(S)(S text, ref uint pos, ref int nesting)
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
		else if(ch == 0 || isspace(ch)) // bad delimiter, fallback to wysiwyg string
			s = State.kStringWysiwyg;
		else
		{
			if(isIdentifierChar(ch))
				scanIdentifier(text, startpos, pos);
			string delim = toUTF8(text[startpos .. pos]);
			nesting = getDelimiterIndex(delim);
		}
		return s;
	}

	static State scanTokenString(S)(S text, ref uint pos, ref int tokLevel)
	{
		int state = toState(State.kWhite, 0, 0, 0);
		int id = -1;
		while(pos < text.length && tokLevel > 0)
		{
			int type = scan(state, text, pos, id);
			if(id == TOK_lcurly)
				tokLevel++;
			else if(id == TOK_rcurly)
				tokLevel--;
		}
		return (tokLevel > 0 ? State.kStringToken : State.kWhite);
	}

	static bool isStartingComment(S)(S txt, ref int idx)
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
	
	static bool isEndingComment(S)(S txt, ref int pos)
	{
		if(pos < txt.length && pos > 0 && txt[pos] == '/' && (txt[pos-1] == '*' || txt[pos-1] == '+'))
		{
			pos--;
			return true;
		}
		if(pos < txt.length-1 && pos >= 0 && (txt[pos] == '*' || txt[pos] == '+') && txt[pos+1] == '/')
			return true;
		return false;
	}
	
	static bool isIdentifierChar(dchar ch)
	{
		if(sAllowDollarInIdentifiers && ch == '$')
			return true;
		return isUniAlpha(ch) || ch == '_' || ch == '@';
	}
	
	static bool isIdentifierCharOrDigit(dchar ch)
	{
		return isIdentifierChar(ch) || isdigit(ch);
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
			if(!isIdentifierCharOrDigit(ch))
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

	static bool isCommentOrSpace(S)(int type, S text)
	{
		return (type == TokenColor.Comment || (type == TokenColor.Text && isspace(text[0])));
	}

	static State scanNestedDelimiterString(S)(S text, ref uint pos, State s, ref int nesting)
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
				return scanStringPostFix(text, pos);
		}
		return s;
	}

	static State scanDelimitedString(S)(S text, ref uint pos, ref int delim)
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
				ch = trydecode(text, pos);
				if(ch == '"')
				{
					delim = 0; // reset delimiter id, it shadows nesting
					return scanStringPostFix(text, pos);
				}
			}
		}
		return State.kStringDelimited;
	}

	static int scan(S)(ref int state, in S text, ref uint pos, ref int id)
	{
		State s = scanState(state);
		int nesting = nestingLevel(state);
		int tokLevel = tokenStringLevel(state);
		int otherState = getOtherState(state);

		int type = TokenColor.Text;
		uint startpos = pos;
		dchar ch;

		id = TOK_Space;
		
		switch(s)
		{
		case State.kWhite:
			ch = decode(text, pos);
			if(ch == 'r' || ch == 'x' || ch == 'q')
			{
				int prevpos = pos;
				dchar nch = trydecode(text, pos);
				if(nch == '"' && ch == 'q')
				{
					s = startDelimiterString(text, pos, nesting);
					if(s == State.kStringDelimited)
						goto case State.kStringDelimited;
					else if(s == State.kStringWysiwyg)
						goto case State.kStringWysiwyg;
					else
						goto case State.kStringDelimitedNestedBracket;
				}
				else if(tokLevel == 0 && ch == 'q' && nch == '{')
				{
					type = TokenColor.String;
					id = TOK_StringLiteral;
					if(sTokenizeTokenString)
					{
						pos = prevpos;
						s = State.kStringTokenFirst;
					}
					else
					{
						tokLevel = 1;
						s = scanTokenString(text, pos, tokLevel);
					}
					break;
				}
				else if(nch == '"')
				{
					goto case State.kStringWysiwyg;
				}
				else
				{
					pos = prevpos;
					type = scanIdentifier(text, startpos, pos, &id);
				}
			}
			else if(isIdentifierChar(ch))
				type = scanIdentifier(text, startpos, pos, &id);
			else if(isdigit(ch))
				type = scanNumber(text, ch, pos, &id);
			else if (ch == '.')
			{
				uint nextpos = pos;
				ch = trydecode(text, nextpos);
				if(isdigit(ch))
					type = scanNumber(text, '.', pos, &id);
				else
					type = scanOperator(text, startpos, pos, &id);
			}
			else if (ch == '/')
			{
				int prevpos = pos;
				ch = trydecode(text, pos);
				if (ch == '/')
				{
					// line comment
					type = TokenColor.Comment;
					id = TOK_Comment;
					while(pos < text.length && decode(text, pos) != '\n') {}
				}
				else if (ch == '*')
				{
					s = scanBlockComment(text, pos);
					type = TokenColor.Comment;
					id = TOK_Comment;
				}
				else if (ch == '+')
				{
					nesting = 1;
					s = scanNestedComment(text, startpos, pos, nesting);
					type = TokenColor.Comment;
					id = TOK_Comment;
				}
				else
				{
					// step back to position after '/'
					pos = prevpos;
					type = scanOperator(text, startpos, pos, &id);
				}
			}
			else if (ch == '"')
				goto case State.kStringCStyle;

			else if (ch == '`')
				goto case State.kStringAltWysiwyg;
			
			else if (ch == '\'')
			{
				s = scanStringCStyle(text, pos, '\'');
				id = TOK_CharacterLiteral;
				type = TokenColor.String;
			}
			else if (ch == '#')
			{
				// display #! or #line as line comment
				type = TokenColor.Comment;
				id = TOK_Comment;
				while(pos < text.length && decode(text, pos) != '\n') {}
			}
			else
			{
				if (tokLevel > 0)
				{
					if(ch == '{')
						tokLevel++;
					else if (ch == '}')
						tokLevel--;
					if(!isspace(ch))
						type = scanOperator(text, startpos, pos, &id);
					id = TOK_StringLiteral;
				}
				else if(!isspace(ch))
					type = scanOperator(text, startpos, pos, &id);
			}
			break;

		case State.kStringTokenFirst:
			ch = decode(text, pos);
			assert(ch == '{');

			tokLevel = 1;
			type = TokenColor.Operator;
			id = TOK_StringLiteral;
			s = State.kWhite;
			break;
			
		case State.kStringToken:
			type = TokenColor.String;
			id = TOK_StringLiteral;
			s = scanTokenString(text, pos, tokLevel);
			break;
			
		case State.kBlockComment:
			s = scanBlockComment(text, pos);
			type = TokenColor.Comment;
			id = TOK_Comment;
			break;

		case State.kNestedComment:
			s = scanNestedComment(text, pos, pos, nesting);
			type = TokenColor.Comment;
			id = TOK_Comment;
			break;

		case State.kStringCStyle:
			s = scanStringCStyle(text, pos, '"');
			type = TokenColor.String;
			id = TOK_StringLiteral;
			break;

		case State.kStringWysiwyg:
			s = scanStringWysiwyg(text, pos);
			type = TokenColor.String;
			id = TOK_StringLiteral;
			break;

		case State.kStringAltWysiwyg:
			s = scanStringAltWysiwyg(text, pos);
			type = TokenColor.String;
			id = TOK_StringLiteral;
			break;

		case State.kStringDelimited:
			s = scanDelimitedString(text, pos, nesting);
			type = TokenColor.String;
			id = TOK_StringLiteral;
			break;

		case State.kStringDelimitedNestedBracket:
		case State.kStringDelimitedNestedParen:
		case State.kStringDelimitedNestedBrace:
		case State.kStringDelimitedNestedAngle:
			s = scanNestedDelimiterString(text, pos, s, nesting);
			type = TokenColor.String;
			id = TOK_StringLiteral;
			break;

		default:
			break;
		}
		state = toState(s, nesting, tokLevel, otherState);
		
		if(tokLevel > 0)
			id = TOK_StringLiteral;
		return type;
	}
	
	static int scan(S)(ref int state, in S text, ref uint pos)
	{
		int id;
		return scan(state, text, pos, id);
	}
}

///////////////////////////////////////////////////////////////
TokenInfo[] ScanLine(S)(int iState, S text)
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
__gshared int[string] specials_map; // maps to TOK enumerator

shared static this() 
{
	foreach(i, s; keywords)
		keywords_map[s] = TOK_begin_Keywords + i;

	foreach(i, s; specials)
		specials_map[s] = i;
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
	"__gshared",
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

// not listed as keywords, but "special tokens"
const string specials[] = 
[
	"__DATE__",
	"__EOF__",
	"__TIME__",
	"__TIMESTAMP__",
	"__VENDOR__",
	"__VERSION__",
];

////////////////////////////////////////////////////////////////////////
enum
{
	TOK_begin_Generic,
	TOK_Space = TOK_begin_Generic,
	TOK_Comment,
	TOK_Identifier,
	TOK_IntegerLiteral,
	TOK_FloatLiteral,
	TOK_StringLiteral,
	TOK_CharacterLiteral,
	TOK_EOF,
	TOK_end_Generic
}

string genKeywordEnum(string kw)
{
	if(kw[0] == '@')
		kw = kw[1..$];
	return "TOK_" ~ kw;
}

string genKeywordsEnum(T)(string[] kwords, T begin)
{
	string enums = "enum { TOK_begin_Keywords = " ~ to!string(begin) ~ ", ";
	bool first = true;
	foreach(kw; kwords)
	{
		enums ~= genKeywordEnum(kw);
		if(first)
		{
			first = false;
			enums ~= " = TOK_begin_Keywords";
		}
		enums ~= ",";
	}
	enums ~= "TOK_end_Keywords }";
	return enums;
}

mixin(genKeywordsEnum(keywords, "TOK_end_Generic"));

const string[2][] operators =
[
	[ "lcurly",           "{" ],
	[ "rcurly",           "}" ],
	[ "lparen",           "(" ],
	[ "rparen",           ")" ],
	[ "lbracket",         "[" ],
	[ "rbracket",         "]" ],
	[ "semicolon",        ";" ],
	[ "colon",            ":" ],
	[ "comma",            "," ],
	[ "dot",              "." ],

	// binary operators
	[ "xor",              "^" ],
	[ "assign",           "=" ],
	[ "lt",               "<" ],
	[ "gt",               ">" ],
	[ "le",               "<=" ],
	[ "ge",               ">=" ],
	[ "equal",            "==" ],
	[ "notequal",         "!=" ],

	[ "unord",            "!<>=" ],
	[ "ue",               "!<>" ],
	[ "lg",               "<>" ],
	[ "leg",              "<>=" ],
	[ "ule",              "!>" ],
	[ "ul",               "!>=" ],
	[ "uge",              "!<" ],
	[ "ug",               "!<=" ],
	[ "notcontains",      "!in" ],
	[ "notidentity",      "!is" ],

	[ "shl",              "<<" ],
	[ "shr",              ">>" ],
	[ "ushr",             ">>>" ],
	[ "add",              "+" ],
	[ "min",              "-" ],
	[ "mul",              "*" ],
	[ "div",              "/" ],
	[ "mod",              "%" ],
	[ "pow",              "^^" ],
	[ "and",              "&" ],
	[ "andand",           "&&" ],
	[ "or",               "|" ],
	[ "oror",             "||" ],
	[ "tilde",            "~" ],
	
	[ "xorass",           "^=" ],
	[ "addass",           "+=" ],
	[ "minass",           "-=" ],
	[ "mulass",           "*=" ],
	[ "divass",           "/=" ],
	[ "modass",           "%=" ],
	[ "powass",           "^^=" ],
	[ "shlass",           "<<=" ],
	[ "shrass",           ">>=" ],
	[ "ushrass",          ">>>=" ],
	[ "andass",           "&=" ],
	[ "orass",            "|=" ],
	[ "catass",           "~=" ],

	// end of binary operators
	
	[ "not",              "!" ],
	[ "dollar",           "$" ],
	[ "slice",            ".." ],
	[ "dotdotdot",        "..." ],
	[ "plusplus",         "++" ],
	[ "minusminus",       "--" ],
	[ "question",         "?" ],
/+
	[ "array",            "[]" ],
	// symbols with duplicate meaning
	[ "address",          "&" ],
	[ "star",             "*" ],
	[ "preplusplus",      "++" ],
	[ "preminusminus",    "--" ],
	[ "neg",              "-" ],
	[ "uadd",             "+" ],
	[ "cat",              "~" ],
	[ "identity",         "is" ],
	[ "plus",             "++" ],
	[ "minus",            "--" ],
+/
];

string genOperatorEnum(T)(string[2][] ops, T begin)
{
	string enums = "enum { TOK_begin_Operators = " ~ to!string(begin) ~ ", ";
	bool first = true;
	for(int o = 0; o < ops.length; o++)
	{
		enums ~= "TOK_" ~ ops[o][0];
		if(first)
		{
			first = false;
			enums ~= " = TOK_begin_Operators";
		}
		enums ~= ",";
	}
	enums ~= "TOK_end_Operators }";
	return enums;
}

mixin(genOperatorEnum(operators, "TOK_end_Keywords"));

enum TOK_binaryOperatorFirst = TOK_xor;
enum TOK_binaryOperatorLast  = TOK_catass;
enum TOK_assignOperatorFirst = TOK_xorass;
enum TOK_assignOperatorLast  = TOK_catass;

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

string genOperatorParser(string getch)
{
	// create sorted list of operators
	int[] opIndex;
	for(int o = 0; o < operators.length; o++)
	{
		string op = operators[o][1];
		int p = 0;
		while(p < opIndex.length)
		{
			assert(op != operators[opIndex[p]][1], "duplicate operator " ~ op);
			if(op < operators[opIndex[p]][1])
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
		string op = operators[opIndex[o]][1];
		string nextop;
		if(o + 1 < opIndex.length)
			nextop = operators[opIndex[o+1]][1];
		
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
			txt ~= indent ~ "default: len = " ~ to!string(matchlen) ~ "; return TOK_" ~ operators[opIndex[o]][0] ~ "; // " ~ op ~ "\n";
			defaults ~= operators[opIndex[o]][0];
			matchlen++;
		}
		else
		{
			string case_txt = "case '" ~ op[matchlen-1] ~ "':";
			if(isalnum(op[matchlen-1]))
				case_txt ~= " ch = getch(); if(isalnum(ch)) goto default;\n" ~ indent ~ "  ";
			txt ~= indent ~ case_txt ~ " len = " ~ to!string(matchlen) ~ "; return TOK_" ~ operators[opIndex[o]][0] ~ "; // " ~ op ~ "\n";
		
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

int parseOperator(S)(S txt, uint pos, ref int len)
{
	dchar getch() 
	{
		if(pos >= txt.length)
			return 0;
		return decode(txt, pos);
	}
	
	mixin(genOperatorParser("getch()"));
}

////////////////////////////////////////////////////////////////////////
version(none)
{
	pragma(msg, genKeywordsEnum(keywords, "TOK_end_Generic"));
	pragma(msg, genOperatorEnum(operators, "TOK_end_Keywords"));
	pragma(msg, genOperatorParser("getch()"));
}

string tokenString(int id)
{
	switch(id)
	{
		case TOK_Space:            return " ";
		case TOK_Comment:          return "/**/";
		case TOK_Identifier:       return "Identifier";
		case TOK_IntegerLiteral:   return "IntegerLiteral";
		case TOK_FloatLiteral:     return "FloatLiteral";
		case TOK_StringLiteral:    return "StringtLiteral";
		case TOK_CharacterLiteral: return "CharacterLiteral";
		case TOK_EOF:              return "__EOF__";
		case TOK_begin_Keywords: .. case TOK_end_Keywords - 1:
			return keywords[id - TOK_begin_Keywords];
		case TOK_begin_Operators: .. case TOK_end_Operators - 1:
			return operators[id - TOK_begin_Operators][1];
		default:
			assert(false);
	}
}

string operatorName(int id)
{
	switch(id)
	{
		case TOK_begin_Operators: .. case TOK_end_Operators - 1:
			return operators[id - TOK_begin_Operators][0];
		default:
			assert(false);
	}
}
