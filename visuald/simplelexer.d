module simplelexer;

//import idl.vsi.textmgr;
import sdk.port.base;

import std.ctype;
import std.utf;
import std.uni;
import std.conv;

// current limitations:
// - nested comments must not nest more than 255 times
// - braces must not nest more than 4095 times inside token string
// - number of different delimiters must not exceed 256

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

	static State scanState(int state) { return cast(State) (state & 0xf); }
	static int nestingLevel(int state) { return (state >> 4) & 0xff; } // used for state kNestedComment and kStringDelimited
	static int tokenStringLevel(int state) { return (state >> 12); }

	static int toState(State s, int nesting, int tokLevel)
	{
		assert(s >= State.kWhite && s <= State.kStringDelimitedNestedAngle);
		assert(nesting < 32);
		assert(tokLevel < 32);

		return s | (nesting << 4) | (tokLevel << 12); 
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
			if(!isUniAlpha(ch) && !isdigit(ch) && ch != '_')
				break;
			pos = nextpos;
		}
		string ident = toUTF8(text[startpos .. pos]);

		if(ident in keywords_map)
			return TokenColor.Keyword;

		return TokenColor.Identifier;
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
			if(isUniAlpha(ch) || ch == '_')
				scanIdentifier(text, startpos, pos);
			string delim = toUTF8(text[startpos .. pos]);
			nesting = getDelimiterIndex(delim);
		}
		return s;
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
			if(isUniAlpha(ch) || ch == '_')
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

version(D_Version2)
{
	static string str1 = "string";
	static string str2 = r"string";
/+	static string str3 = q"X
	    (stri)ng "
X";+/
}

	static int scan(ref int state, in wstring text, ref uint pos)
	{
		State s = scanState(state);
		int nesting = nestingLevel(state);
		int tokLevel = tokenStringLevel(state);

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
			else if(isUniAlpha(ch) || ch == '_')
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
					// step back to position after '/'
					pos = prevpos;
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
		state = toState(s, nesting, tokLevel);
		return tokLevel > 0 ? TokenColor.String : type;
	}
}

struct empty_t {}

empty_t[string] keywords_map;

static this() {
	empty_t empty;
	foreach(string s; keywords)
	    keywords_map[s] = empty;
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
	"immutable"
];

