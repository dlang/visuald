// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module c2d.tokenizer;

import std.ascii;
import std.string;
import std.utf;

version = V2;
// version = Java;
// version = IDL;
version = dollar_in_ident;

class Token
{
	// very basic C++ tokenizer, interested only in:
	enum {
		Comment,
		Newline,
		Identifier,
		Number,
		String,

		Namespace,
		Struct,
		Class,
		Union,
		Enum,
		
		Typedef, // 10
		Extern,
		Static,
		Const,
		__In,
		
		__Out,
		__Body,
		__Asm,
		__Declspec,
		If,
		
		Else,  // 20
		Do,
		While,
		For,
		Return,
		
		Break,
		Continue,
		Switch,
		Goto,
		Delete,

		BraceL, // 30
		BraceR,
		BracketL,
		BracketR,
		ParenL,
		ParenR,

		Equal,
		Unequal,
		LessThan,
		LessEq,
		
		GreaterThan, // 40
		GreaterEq,
		Unordered,
		LessGreater,
		LessEqGreater,
		
		UnordGreater,
		UnordGreaterEq,
		UnordLess,
		UnordLessEq,
		UnordEq,

		Shl, // 50
		Shr,
		Comma,
		Asterisk,
		Ampersand,
		
		Assign,
		Dot,
		Elipsis,
		Colon,
		DoubleColon,
		
		Semicolon, // 60
		Tilde,
		Question,
		Exclamation,
		Deref,
		
		Plus,
		PlusPlus,
		Minus,
		MinusMinus,
		Div,
		
		Mod, // 70
		Xor,
		Or,
		OrOr,
		AmpAmpersand,
		
		AddAsgn,
		SubAsgn,
		MulAsgn,
		DivAsgn,
		ModAsgn,
		
		AndAsgn, // 80
		XorAsgn,
		OrAsgn,
		ShlAsgn,
		ShrAsgn,

		PPinclude,
		PPdefine,
		PPundef,
		PPif,
		PPifdef,
		
		PPifndef, // 90
		PPelse,
		PPelif,
		PPendif,
		PPother,
		PPinsert, // helper for reparsing

		Fis,
		FisFis,
		Macro,
		Other,
		
		EOF, // 100
		V1Tokens
	}

version(V2)
{
	enum {
		New = V1Tokens,
		Static_if,
		Mixin,
		Case,
		Default,
		Operator,
		Version,
		Sizeof,
		This,
		Static_cast,
		Dynamic_cast,
		Reinterpret_cast,
		Const_cast,
		Empty,    // helper for unspecified identifier in declaration
		Interface,
		Template,
	}
}
version(Java)
{
	enum {
		Instanceof = V1Tokens,
	}
}
	static bool isPPToken(int type)
	{
		switch(type)
		{
			case PPinclude, PPdefine, PPundef, PPif, PPifdef, PPifndef, 
			     PPelse, PPelif, PPendif, PPother:
				return true;
			default:
				return false;
		}
	}

	static bool needsTrailingSemicolon(int type)
	{
		switch(type)
		{
			case Class, Struct, Union, Enum, Typedef:
				return true;
			default:
				return false;
		}
	}

	static string toString(int type)
	{
		switch(type)
		{
		case Namespace:	     return "namespace";
		case Struct:	     return "struct";
		case Class:	     return "class";
		case Union:	     return "union";
		case Enum:	     return "enum";
		case Typedef:	     return "typedef";
		case Extern:	     return "extern";
		case Static:	     return "static";
		case Const:	     return "const";
		case __In:	     return "__in";
		case __Out:	     return "__out";
		case __Body:	     return "__body";

		case __Asm:	     return "__asm";
		case __Declspec:     return "__declspec";
		case If:	     return "if";
		case Else:	     return "else";
		case Do:	     return "do";
		case While:	     return "while";
		case For:	     return "for";
		case Return:	     return "return";
		case Break:	     return "break";
		case Continue:	     return "continue";
		case Switch:	     return "switch";
		case Goto:	     return "goto";
		case Delete:	     return "delete";

		case BraceL:	     return "{";
		case BraceR:	     return "}";
		case BracketL:	     return "[";
		case BracketR:	     return "]";
		case ParenL:	     return "(";
		case ParenR:	     return ")";

		case Equal:	     return "==";
		case Unequal:	     return "!=";
		case LessThan:	     return "<";
		case LessEq:	     return "<=";
		case GreaterThan:    return ">";
		case GreaterEq:	     return ">=";

		case Unordered:	     return "!<>=";
		case LessGreater:    return "<>";
		case LessEqGreater:  return "<>=";
		case UnordGreater:   return "!<=";
		case UnordGreaterEq: return "!<";
		case UnordLess:	     return "!>=";
		case UnordLessEq:    return "!>";
		case UnordEq:	     return "!<>";

		case Shl:	     return "<<";
		case Shr:	     return ">>";
		case Comma:	     return ",";
		case Asterisk:	     return "*";
		case Ampersand:	     return "&";
		case Assign:	     return "=";
		case Dot:	     return ".";
		case Elipsis:	     return "...";
		case Colon:	     return ":";
		case DoubleColon:    return "::";
		case Semicolon:	     return ";";
		case Tilde:	     return "~";
		case Question:	     return "?";
		case Exclamation:    return "!";
		case Deref:	     return "->";
		case Plus:	     return "+";
		case PlusPlus:	     return "++";
		case Minus:	     return "-";
		case MinusMinus:     return "--";
		case Div:	     return "/";
		case Mod:	     return "%";
		case Xor:	     return "^";
		case Or:	     return "|";
		case OrOr:	     return "||";
		case AmpAmpersand:   return "&&";
		case AddAsgn:	     return "+=";
		case SubAsgn:	     return "-=";
		case MulAsgn:	     return "*=";
		case DivAsgn:	     return "/=";
		case ModAsgn:	     return "%=";
		case AndAsgn:	     return "&=";
		case XorAsgn:	     return "^=";
		case OrAsgn:	     return "|=";
		case ShlAsgn:	     return "<<=";
		case ShrAsgn:	     return ">>=";

		case PPinclude:	     return "#include";
		case PPdefine:	     return "#define";
		case PPundef:	     return "#undef";
		case PPif:	     return "#if";
		case PPifdef:	     return "#ifdef";
		case PPifndef:	     return "#ifndef";
		case PPelse:	     return "#else";
		case PPelif:	     return "#elif";
		case PPendif:	     return "#endif";

		case Fis:	     return "#";
		case FisFis:	     return "##";

version(V2)
{
		case New:	return "new";
		case Static_if: return "__static_if";
		case Mixin:	return "__mixin";
		case Case:	return "case";
		case Default:	return "default";
		case Operator:	return "operator";
		case Version:	return "version";
		case Sizeof:	return "sizeof";
		case This:	return "this";
		case Static_cast: return "static_cast";
		case Dynamic_cast: return "dynamic_cast";
		case Reinterpret_cast: return "reinterpret_cast";
		case Const_cast: return "const_cast";
		case Empty:	return "";
		case Newline:	return "\n";
		case Interface: return "interface";
		case Template: return "template";

}
version(Java)
{
		case Instanceof: return "instanceof";
}
		case Identifier: return "<identifier>";
		case Number: return "<number>";
		case String: return "<string>";
		case EOF: return "EOF";
			
		// other types supposed to fail because no representation available
		case Macro:
		case PPinsert:
		case Comment:
		case PPother:
		case Other:
		default:
			assert(type == EOF); // always fails
			return "<unexpected>";
		}
	}

	int type;
	int lineno;
	string text;
	string pretext;
}

///////////////////////////////////////////////////////////////////////

bool contains(T)(ref T[] arr, T val)
{
	foreach(T t; arr)
		if (t == val)
			return true;
	return false;
}

void addunique(T)(ref T[] arr, T val)
{
	if (!contains(arr, val))
		arr ~= val;
}

///////////////////////////////////////////////////////////////////////

class Tokenizer
{
	this(string txt)
	{
		text = txt;
		reinit();
	}

	void reinit()
	{
		lastIndent = "";
		countTokens = 0;
		pos = 0;
		if(text.length >= 3 && text[0] == 0xef && text[1] == 0xbb && text[2] == 0xbf)
			pos += 3; // skip utf8 header
		lineno = 1;
		lastCharWasNewline = true;
		skipNewline = true;
		keepBackSlashAtEOL = false;
		enableASMComment = false;
	}

	void pushText(string txt)
	{
		if(txt.length > 0)
		{
			if (pos < text.length)
			{
				txtstack ~= text;
				posstack ~= pos;
			}
			text = txt;
			pos = 0;
		}
	}
	bool popText()
	{
		if(txtstack.length <= 0)
			return false;
		text = txtstack[$-1];
		pos  = posstack[$-1];

		txtstack.length = txtstack.length - 1;
		posstack.length = posstack.length - 1;
		return true;
	}

	bool eof()
	{
		return pos >= text.length && txtstack.length <= 0;
	}
	bool eof(int n)
	{
		// this call is used to check for a close newline, so it does not need to check the text stack
		return pos + n >= text.length;
	}

	bool isNewline()
	{
		if (text[pos] == '\n' || text[pos] == '\r')
			return true;
		return false;
	}

	void incPos()
	{
		pos++;
		if (pos >= text.length)
			popText();
	}

	bool handleBackSlash()
	{
		if (eof(1) || text[pos] != '\\')
			return false;

		while (!eof(1) && text[pos] == '\\')
		{
			if (text[pos+1] == '\r' && !eof(2) && text[pos+2] == '\n')
			{
				lineno++;
				incPos();
				incPos();
				incPos();
			}
			else if (text[pos+1] == '\n')
			{
				lineno++;
				incPos();
				incPos();
			}
			else
				return false;
			if(keepBackSlashAtEOL)
				curText ~= "\\\n";
		}
		return true;
	}

	bool nextChar()
	{
		if (eof())
			return false;

		handleBackSlash();
		if (text[pos] == '\r' && !eof(1) && text[pos+1] == '\n')
		{
			lineno++;
			incPos();
			lastCharWasNewline = true;
		}
		else if (text[pos] == '\n')
		{
			lineno++;
			lastCharWasNewline = true;
		}
		else
			lastCharWasNewline = false;
		curText ~= text[pos];
		incPos();
		if (eof())
			return false;

		return true;
	}

	int skipSpace()
	{
		bool collectIndent = lastCharWasNewline;
		if(collectIndent)
			lastIndent = "";

		int lines = lineno;
		handleBackSlash();
	cont_spaces:
		while(!eof() && isWhite(text[pos]))
		{
			if (isNewline())
			{
				if (!skipNewline)
					break;
				else
				{
					collectIndent = true;
					lastIndent = "";
				}
			}
			else if(collectIndent)
				lastIndent ~= text[pos];

			nextChar();
		}
		if (!keepBackSlashAtEOL)
		{
			if(!eof(2) && text[pos] == '\\' && (text[pos+1] == '\n' || text[pos+1] == '\r'))
			{
				nextChar();
				nextChar();
				goto cont_spaces;
			}
		}
		else if (handleBackSlash())
			goto cont_spaces;

		return lineno - lines;
	}

	void skipLine()
	{
		while(!eof() && !isNewline())
			nextChar();
		if(!eof() && skipNewline)
			nextChar();
	}

	bool skipString()
	{
		int sep = text[pos];
		nextChar();
		while(!eof() && text[pos] != sep)
		{
version(IDL) {} else {
			if(isNewline())
				throw new Exception("newline in string constant");
}
			if(!handleBackSlash())
			{
				if(text[pos] == '\\')
					nextChar();
				nextChar();
			}
		}
		if (eof())
			return false;
		nextChar();
		return true;
	}

	bool skipIdent()
	{
		if (eof())
			return false;
		if(!isAlpha(text[pos]) && text[pos] != '_')
			return false;
		nextChar();
		return skipAlnum();
	}

	bool skipAlnum()
	{
		version(dollar_in_ident)
			while(!eof() && (isAlphaNum(text[pos]) || text[pos] == '_' || text[pos] == '$'))
				nextChar();
		else
			while(!eof() && (isAlphaNum(text[pos]) || text[pos] == '_'))
				nextChar();
		return true;
	}

	bool skipNumber()
	{
		nextChar();
		skipAlnum();
		if(eof() || text[pos] != '.')
			return true;
		// float
		nextChar();
		skipAlnum();
		if(text[pos-1] == 'E' || text[pos-1] == 'e' || text[pos-1] == 'P' || text[pos-1] == 'p')
			if(text[pos] == '+' || text[pos] == '-')
			{
				nextChar();
				skipAlnum();
			}
		return true;
	}

	void skipComment()
	{
		while(nextChar())
		{
			if (text[pos] == '*' && pos + 1 < text.length && text[pos+1] == '/')
			{
				nextChar();
				nextChar();
				break;
			}
		}
	}

	int checkChar(int def, charTypes...)()
	{
		int ch = text[pos];
		int isChar = true;
		bool found = false;
		foreach(int ct; charTypes)
		{
			if(isChar)
				found = (ct == ch);
			else if(found)
			{
				nextChar();
				return ct;
			}
			isChar = !isChar;
		}
		return def;		
	}

	int checkNextChar(int def, charTypes...)()
	{
		// we were always sitting on a valid character, and we don't want appending "\\\n",
		//  so we do the relevant parts of nextChar() here
		lastCharWasNewline = false;
		curText ~= text[pos];
		incPos();
		if(!eof())
		{
			return checkChar!(def, charTypes);
		}
		return def;		
	}
	int contNextChar(int iftype, charTypes...)(Token tok)
	{
		if(tok.type == iftype && !eof())
		{
			tok.type = checkChar!(iftype, charTypes);
		}
		return tok.type;
	}

	static int identifierToKeyword(string ident)
	{
		switch(ident)
		{
		case "namespace": return Token.Namespace;
		case "struct":    return Token.Struct;
		case "class":     return Token.Class;
		case "union":     return Token.Union;
		case "enum":      return Token.Enum;
		case "typedef":   return Token.Typedef;
		case "extern":    return Token.Extern;
		case "static":    return Token.Static;
		case "const":     return Token.Const;
		case "__in":      return Token.__In;
		case "__out":     return Token.__Out;
		case "__body":    return Token.__Body;
		case "_asm":      return Token.__Asm;
		case "__asm":     return Token.__Asm;
		case "__declspec":  return Token.__Declspec;
		case "if":        return Token.If;
		case "else":      return Token.Else;
		case "while":     return Token.While;
		case "do":        return Token.Do;
		case "for":       return Token.For;
		case "switch":    return Token.Switch;
		case "goto":      return Token.Goto;
		case "return":    return Token.Return;
		case "continue":  return Token.Continue;
		case "break":     return Token.Break;
		case "delete":    return Token.Delete;
version(V2)
{
		case "case":      return Token.Case;
		case "default":   return Token.Default;
		case "__static_if": return Token.Static_if;
		case "__mixin":   return Token.Mixin;
		case "__version": return Token.Version;
		case "sizeof":    return Token.Sizeof;
		case "operator":  return Token.Operator;
		case "new":       return Token.New;
		case "this":      return Token.This;
		case "static_cast": return Token.Static_cast;
		case "dynamic_cast": return Token.Dynamic_cast;
		case "reinterpret_cast": return Token.Reinterpret_cast;
		case "const_cast": return Token.Const_cast;
		case "interface": return Token.Interface;
		case "template":  return Token.Template;
}
version(Java)
{
		case "instanceof": return Token.Instanceof;
}
		default:          return Token.Identifier;
		}
	}
	
	bool next(Token tok)
	{
		curText = "";
		bool startOfLine = pos <= 0 || text[pos-1] == '\n' || text[pos-1] == '\r';
		if(skipSpace() > 0)
			startOfLine = true;

		tok.pretext = curText;
		tok.lineno = lineno;

		if(eof())
		{
			tok.text = "";
			tok.type = Token.EOF;
			return false;
		}

		curText = "";
		tok.type = Token.Other;

		switch(text[pos])
		{
		case '{':  tok.type = Token.BraceL;      nextChar(); break;
		case '}':  tok.type = Token.BraceR;      nextChar(); break;
		case '[':  tok.type = Token.BracketL;    nextChar(); break;
		case ']':  tok.type = Token.BracketR;    nextChar(); break;
		case '(':  tok.type = Token.ParenL;      nextChar(); break;
		case ')':  tok.type = Token.ParenR;      nextChar(); break;
		case ',':  tok.type = Token.Comma;       nextChar(); break;
		case '~':  tok.type = Token.Tilde;       nextChar(); break;
		case '?':  tok.type = Token.Question;    nextChar(); break;
		case '\r':
		case '\n': tok.type = Token.Newline;     nextChar(); break;

		case '=':  tok.type = checkNextChar!(Token.Assign,      '=', Token.Equal); break;
		case '*':  tok.type = checkNextChar!(Token.Asterisk,    '=', Token.MulAsgn); break;
		case '%':  tok.type = checkNextChar!(Token.Mod,         '=', Token.ModAsgn); break;
		case '^':  tok.type = checkNextChar!(Token.Xor,         '=', Token.XorAsgn); break;
		case '&':  tok.type = checkNextChar!(Token.Ampersand,   '=', Token.AndAsgn, '&', Token.AmpAmpersand); break;
		case '|':  tok.type = checkNextChar!(Token.Or,          '=', Token.OrAsgn, '|', Token.OrOr); break;
		case ':':  tok.type = checkNextChar!(Token.Colon,       ':', Token.DoubleColon); break;
		case '-':  tok.type = checkNextChar!(Token.Minus,       '=', Token.SubAsgn, '>', Token.Deref, '-', Token.MinusMinus); break;
		case '+':  tok.type = checkNextChar!(Token.Plus,        '=', Token.AddAsgn, '+', Token.PlusPlus); break;

		case '<':  
			tok.type = checkNextChar!(Token.LessThan,    '=', Token.LessEq, '<', Token.Shl, '>', Token.LessGreater); 
			contNextChar!(Token.Shl, '=', Token.ShlAsgn)(tok);
			contNextChar!(Token.LessGreater, '=', Token.LessEqGreater)(tok);
			break;
		case '>':  
			tok.type = checkNextChar!(Token.GreaterThan, '=', Token.GreaterEq, '>', Token.Shr); 
			contNextChar!(Token.Shr, '=', Token.ShrAsgn)(tok);
			break;

		case '!':  
			// !  -> != !< !>
			tok.type = checkNextChar!(Token.Exclamation, '=', Token.Unequal, '<', Token.UnordGreaterEq, '>', Token.UnordLessEq); 
			// !< -> !<= !<>
			contNextChar!(Token.UnordGreaterEq, '=', Token.UnordGreater, '>', Token.UnordEq)(tok);
			// !<> -> !<>=
			contNextChar!(Token.UnordEq, '=', Token.Unordered)(tok);
			// !> -> !>=
			contNextChar!(Token.UnordLessEq, '=', Token.UnordLess)(tok);
			break;

		case '.':
			tok.type = checkNextChar!(Token.Dot,         '.', Token.Elipsis);
			if(tok.type == Token.Elipsis)
			{
				if(text[pos] != '.')
					throw new Exception("missing third '.' for '...'");
				nextChar();
			}
			break;
			
		case '#':
			nextChar();
			if(!startOfLine)
			{
				if(text[pos] == '#')
				{
					tok.type = Token.FisFis;
					nextChar();
				}
				else
					tok.type = Token.Fis;
			}
			else if(skipSpace() == 0)
			{
				int identpos = pos;
				if (skipIdent())
				{
					string ident = text[identpos..pos];
					switch(ident)
					{
					case "include": tok.type = Token.PPinclude; break;
					case "define":  tok.type = Token.PPdefine;  break;
					case "undef":   tok.type = Token.PPundef;   break;
					case "ifdef":   tok.type = Token.PPifdef;   break;
					case "ifndef":  tok.type = Token.PPifndef;  break;
					case "if":      tok.type = Token.PPif;      break;
					case "elif":    tok.type = Token.PPelif;    break;
					case "else":    tok.type = Token.PPelse;    break;
					case "endif":   tok.type = Token.PPendif;   break;
					default:        tok.type = Token.PPother;   break;
					}
				}
			}
			break;
		
		case '0','1','2','3','4','5','6','7','8','9':
			skipNumber();
			tok.type = Token.Number;
			break;

		case 'L':
			if(nextChar() && (text[pos] == '\"' || text[pos] == '\''))
				goto case '\"';
			skipAlnum();
			tok.type = Token.Identifier;
			break;

		case 'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z':
			goto case;
		case 'A','B','C','D','E','F','G','H','I','J','K',    'M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z':
			goto case;
		case '_':
			skipIdent();
			string ident = curText;
			if(ppOnly)
				tok.type = Token.Identifier;
			else
				tok.type = identifierToKeyword(ident);
			break;
		
		case '$':
			nextChar();
			skipAlnum();
			tok.type = Token.Macro;
			break;
		case ';':
			if (enableASMComment)
			{
				skipLine();
				tok.type = Token.Comment;
			}
			else
			{
				tok.type = Token.Semicolon;
				nextChar();
			}
			break;
		case '/':
			nextChar();
			tok.type = Token.Div;
			if(!eof())
			{
				if(text[pos] == '/')
				{
					skipLine();
					tok.type = Token.Comment;
				}
				else if(text[pos] == '*')
				{
					skipComment();
					tok.type = Token.Comment;
				}
				else if(text[pos] == '=')
				{
					nextChar();
					tok.type = Token.DivAsgn;
				}
			}
			break;
		
		case '\'':
		case '\"':
			skipString();
			tok.type = Token.String;
			break;

		default:   
			tok.type = Token.Other; 
			nextChar();
			break;
		}

		countTokens++;
		tok.text = curText;
		return true;
	}

	string lastIndent;
	string text;
	string curText;

	int[] posstack;
	string[] txtstack;

	uint pos;
	int lineno;
	int countTokens;
	bool lastCharWasNewline;
	bool skipNewline;
	bool keepBackSlashAtEOL;
	bool enableASMComment;
	
	static bool ppOnly;
}

