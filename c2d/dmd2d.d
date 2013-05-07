module dmd2d;

import tokenizer;

import std.file;
import std.path;
import std.getopt;
import std.ctype;
import std.stdio;
import std.string;
import std.conv;
import std.array;
import std.algorithm : min, max;
import std.regexp : sub;

version = noLOG;

///////////////////////////////////////////////////////////////////////

string[string] defines;
string[string] structTypes;
string[] undefines;
string[] expands;
PatchData[] srcpatches;
PatchData[] dstpatches;
string outputName;
bool verbose;
bool simple = true;
bool dump = true;
bool addStringPtr = true;  // append ".ptr" to strings

///////////////////////////////////////////////////////////////////////

enum 
{
	kPassCollectClasses,
	kPassDefineFunctions,
	kPassRewrite,
	kPassClassPtrToRef,
	kNumPasses
}

enum EnumState 
{
	kNone,
	kIdentifier,
	kInit
}

///////////////////////////////////////////////////////////////////////

enum EvalState
{
	kEvalUnknown,
	kEvalAlive,             // unconditional alive section
	kEvalDead,              // unconditional dead section
	kEvalDeadAfterAlive,    // multiple #elif after unconditional alive section
	kEvalDeadAfterUnknown,  // dead section after conditional alive section
	kEvalAliveAfterUnknown, // alive section after conditional alive section
};

struct PPEnabler
{
	this(Source src) { _src = src; _src.setPPprocessing(true); }
	~this() { _src.setPPprocessing(false); }

	Source _src;
}

class PPDefine
{
	string ident;
	string[] args;
	string text;
}

bool validStartChar(bool replSharp, char ch)
{
	if(replSharp)
		return ch != '#';
	return !isalnum(ch) && ch != '_';
}
bool validEndChar(char ch)
{
	return !isalnum(ch) && ch != '_';
}

bool inQuotedString(string txt, int pos)
{
	int p = pos;
	while(p > 0 && txt[p] != '\n')
		p--;
	char sep = 0;
	while(p < pos)
	{
		if(sep == 0)
		{
			if(txt[p] == '\"' || txt[p] == '\'')
				sep = txt[p];
		}
		else if (txt[p] == '\\')
		{
			p++;
		}
		else if (txt[p] == sep)
		{
			sep = 0;
		}
		p++;
	}
	return sep != 0;
}

// if txt[pos] starts a string with a quote, jump to terminating quote
int skipString(string txt, int pos)
{
	if (txt[pos] == '\'' || txt[pos] == '\"')
	{
		int sep = txt[pos++];
		while(pos < txt.length && txt[pos] != sep)
		{
			if(txt[pos] == '\\' && pos < txt.length - 1)
				pos++;
			pos++;
		}
	}
	return pos;
}

bool inComment(string txt, int pos)
{
	bool checkLineComment = true;
retry_prevline:
	int p = pos;
	while(p > 0 && txt[p-1] != '\n')
		p--;

	int linepos = p;
	while(p < pos && isspace(txt[p]))
		p++;
	int q = p;
	while(q < pos)
	{
		if(checkLineComment && txt[q] == '/' && txt[q+1] == '/')
			return true;
		if(txt[q] == '/' && txt[q+1] == '*')
		{
		    int r = find(txt[q+2 .. pos], "*/");
			if(r < 0)
				return true;
			q += 1 + r;
		}
		q++;
	}
	// check comment continuation from last line
	if(find(txt[p .. pos], "*/") >= 0)
		return false;
	if(txt[p] != '*')
		return false;
	if(linepos <= 0)
		return false;
	pos = linepos-1;
	checkLineComment = false;
	goto retry_prevline;
}

unittest
{
	assert(!inComment("12345 // 6789", 5));
	assert( inComment("12345 // 6789", 10));
	assert( inComment("12345 /* 6789 */", 10));
	assert(!inComment("/*345 */ 6789", 10));
	assert( inComment("/*\n *   6789\n */", 10));
	assert(!inComment("// co\n *   6789\n", 10));
}

string replaceToken(string txt, string token, string replacement)
{
	bool replSharp = token[0] == '#';
	bool checkStart = !validStartChar(replSharp, token[0]);
	bool checkEnd = !validEndChar(token[$-1]);
	string newtxt;
	for(int findpos = 0; ; )
	{
		int pos = find(txt[findpos..$], token);
		if (pos < 0)
			return newtxt ~ txt[findpos..$];
		pos += findpos;
		if(!inQuotedString(txt, pos) && !inComment(txt, pos) &&
		   (pos == 0 || !checkStart || validStartChar(replSharp, txt[pos - 1])) &&
		   (pos + token.length >= txt.length || !checkEnd || validEndChar(txt[pos + token.length])))
		{
			newtxt ~= txt[findpos..pos] ~ replacement;
			// txt = txt[0..pos] ~ replacement ~ txt[pos + token.length..$];
			//findpos = pos + replacement.length;
			findpos = pos + token.length;
		}
		else
		{
			newtxt ~= txt[findpos..pos+1];
			findpos = pos + 1;
		}
	}
}

string removeComments(string txt)
{
	int pos = 0;
	while(pos < txt.length - 1)
	{
		if(txt[pos] == '/')
		{
			int cpos = pos;
			if (txt[pos+1] == '/')
			{
				while(pos < txt.length && txt[pos] != '\n')
					pos++;
				txt = txt[0..cpos] ~ txt[pos..$];
				pos = cpos;
				continue;
			} 
			else if (txt[pos+1] == '*')
			{
				pos += 2;
				while(pos < txt.length - 2)
				{
					if (txt[pos] == '*' && txt[pos+1] == '/')
					{
						txt = txt[0..cpos] ~ txt[pos+2..$];
						pos = cpos;
						break;
					}
					pos++;
				}
				continue;
			}
		}
		else 
			pos = skipString(txt, pos);

		pos++;
	}
	return txt;
}

int posOpeningParenthesis(string txt, int pos, char open, char close)
{
	// assume closing ')' already detected, on position pos or later
	int parens = 1;
	while (pos > 0 && parens > 0)
	{
		pos--;
		if (txt[pos] == close)
			parens++;
		else if (txt[pos] == open)
			parens--;
	}
	return pos;
}
int posClosingParenthesis(string txt, int pos, char open, char close)
{
	// assume opening '(' already detected, before position pos
	int parens = 1;
	while (pos < txt.length)
	{
		if (txt[pos] == close)
			parens--;
		else if (txt[pos] == open)
			parens++;
		if(parens == 0)
			return pos;
		pos++;
	}
	return pos;
}

int findOutsideParenthesis(string txt, char ch, int start)
{
	int pos = start;
	while (pos < txt.length)
	{
		if(txt[pos] == ch)
			return pos;

		if (txt[pos] == '(')
			pos = posClosingParenthesis(txt, pos + 1, '(', ')');
		else if (txt[pos] == '{')
			pos = posClosingParenthesis(txt, pos + 1, '{', '}');
		else if (txt[pos] == '[')
			pos = posClosingParenthesis(txt, pos + 1, '[', ']');

		pos++;
	}
	return -1;
}

int posBeginDeclIdent(string txt, int pos)
{
	int npos = pos;
	while(npos > 0)
	{
		while(npos > 0 && isspace(txt[npos - 1]))
			npos--;

		if (txt[npos - 1] == ')')
			npos = posOpeningParenthesis(txt, npos - 1, '(', ')');
		else if (txt[npos - 1] == '}')
			npos = posOpeningParenthesis(txt, npos - 1, '{', '}');
		else if (txt[npos - 1] == ']')
			npos = posOpeningParenthesis(txt, npos - 1, '[', ']');
		else
		{
			while(npos > 0 && (isalnum(txt[npos - 1]) || txt[npos - 1] == '_' || txt[npos - 1] == '.'))
				npos--;

			if(npos > 1 && txt[npos - 2] == '-' && txt[npos - 1] == '>')
				npos -= 2;
			else
				return npos;
		}
	}
	return 0;
}

string replaceOutsideParenthesis(string txt, char ch, string repl)
{
	int pos = findOutsideParenthesis(txt, ch, 0);
	while(pos >= 0)
	{
		txt = txt[0..pos] ~ repl ~ txt[pos+1..$];
	    pos = findOutsideParenthesis(txt, ch, pos + repl.length);
	}
	return txt;
}


///////////////////////////////////////////////////////////////////////

class Source
{
	this(DMD2D dmd2d, string file)
	{
		this(dmd2d, file, cast(string) read(file));
	}
	this(DMD2D dmd2d, string file, string text)
	{
		_dmd2d = dmd2d;
		_file = file;
		_text = patchFileText(file, text, srcpatches);

//	std.file.write(_file ~ ".patched", _text);

		_tokenizer = new Tokenizer(_text);
		tok = new Token;
	}

	void reinit()
	{
		_ppprocessing = false;
		_braces = 0;
		_parenthesis = 0;
		_prevDeclEndPos = 0;
		_funcBraceLevel = 0;
		_funcProtoStart = -1;
		_funcDeclStart = -1;
		_funcNameStart = -1;
		_statementStart = -1;
		_funcBodyStart = -1;
		_inContract = false;
		_inRHS = -1;
		_levelRHS = 0;
		_isnaked = false;
		_checkEmptyStatement = false;
		_toPtrLevel.length = 0;

		_enumState = EnumState.kNone;

		_curFunc = "";
		_curProto = "";
		_curText = "";
		_newText = "";
		_typedefLevels.length = 0;
		_typedefPositions.length = 0;
		_checkCastNext = false;

		_namespaces.length = 0;
		_namespaceLevels.length = 0;

		_structs.length = 0;
		_structStart.length = 0;
		_structLevels.length = 0;
		_externLevels.length = 0;

		_versions.length = 0;
		_evalVersions.length = 0;
		PPDefine[string] empty;
		_ppdefines = empty;

		_tokenizer.reinit();
	}

	void appendText(string text)
	{
		text = replace(text, "\\\n", ""); // remove line splicing
		text = replace(text, "\\\r\n", "");
		_curText ~= text;
	}

	void appendToken(Token tok)
	{
		string txt = tok.pretext ~ tok.text;
		appendText(txt);
	}

	void undoText(string text)
	{
		text = replace(text, "\\\n", ""); // remove line splicing
		text = replace(text, "\\\r\n", "");
		if (text.length <= _curText.length)
		{
			assert(endsWith(_curText, text));
			_curText = _curText[0..$-text.length];
		}
		else
		{
			assert(endsWith(text, _curText));
			assert(endsWith(_newText, text[0..$-_curText.length]));
			
			_newText = _newText[0..$-(text.length - _curText.length)];
			_curText = "";
		}
	}
	void undoTextLen(int len)
	{
		if (len <= _curText.length)
		{
			_curText = _curText[0..$-len];
		}
		else
		{
			_newText = _newText[0..$-(len - _curText.length)];
			_curText = "";
		}
	}
	void undoTextPos(int pos)
	{
		int len = textPos() - pos;
		undoTextLen(len);
	}

	int textPos()
	{
		return _newText.length + _curText.length;
	}

	string getTextTail(int len)
	{
		if (len <= _curText.length)
			return _curText[$-len .. $].idup;  // why is .dup necessary???
		return _newText[$-(len - _curText.length) .. $] ~ _curText;
	}
	char getChar(int pos)
	{
		if (pos < _newText.length)
			return _newText[pos];
		if (pos < _newText.length + _curText.length)
			return _curText[pos - _newText.length];
		return 0;
	}
	string getText(int pos, int len)
	{
		int end = pos + len;
		if (end < _newText.length)
			return _newText[pos .. end];
		if (pos < _newText.length)
			return _newText[pos .. $] ~ _curText[0 .. end - _newText.length];
		return _curText[pos - _newText.length .. end - _newText.length];
	}

	string indentFunc(string func)
	{
		string txt = replace(func,"\n", "\n" ~ _tokenizer.lastIndent);
		return _tokenizer.lastIndent ~ txt;
	}

	void setPPprocessing(bool on)
	{
		if(on)
			undoText(tok.text);
		_ppprocessing = on;
		_tokenizer.skipNewline = !on;
	}

	bool nextToken(Token tok)
	{
		while(_tokenizer.next(tok))
		{
			if(!_ppprocessing)
				appendToken(tok);
			if (tok.type != Token.Comment)
				return true;
		}
		return false;
	}

	void checkNextToken(int type)
	{
		if(!nextToken(tok))
			throw new Exception("unexpected EOF");
		if(tok.type != type)
			throw new Exception("unexpected " ~ tok.text);
	}

	bool evalVersion()
	{
		foreach(int eval; _evalVersions)
			if (eval == EvalState.kEvalDead || eval == EvalState.kEvalDeadAfterAlive || eval == EvalState.kEvalDeadAfterUnknown)
				return false;
		return true;
	}

	void flushText()
	{
		//if(evalVersion())
			_newText ~= _curText;
		_curText = "";
	}

	void replaceText(string oldtxt, string newtxt)
	{
		undoText(oldtxt);
		appendText(newtxt);
	}

	void replaceTextAt(int pos, string oldtxt, string newtxt)
	{
		string txt = getTextTail(textPos() - pos);
		assert(startsWith(txt, oldtxt));
		undoTextPos(pos);
		appendText(newtxt ~ txt[oldtxt.length .. $]);
	}

	void insertTextAt(int pos, string newtxt)
	{
		string txt = getTextTail(textPos() - pos);
		undoTextPos(pos);
		appendText(newtxt ~ txt);
	}

	void removeTextAt(int pos, string oldtxt)
	{
		string txt = getTextTail(textPos() - pos);
		assert(startsWith(txt, oldtxt));
		undoTextPos(pos);
		appendText(txt[oldtxt.length .. $]);
	}

	void removeTextAt(int pos, int len)
	{
		string txt = getTextTail(textPos() - pos);
		undoTextPos(pos);
		appendText(txt[len .. $]);
	}

	//////////////////////////////////////////////////////////////
	// Preprocessor
	bool isUndefined(string ident)
	{
		foreach(string id; undefines)
			if (ident == id)
				return true;
		return false;
	}

	int evalExpression(string ident)
	{
		ident = strip(ident);
		int eval = EvalState.kEvalUnknown;
		if(isNumeric(ident))
		{
			if (to!(int)(ident) == 0)
				eval = EvalState.kEvalDead;
			else
				eval = EvalState.kEvalAlive;
		}
		else if(ident in defines)
		{
			eval = evalExpression(defines[ident]);
		}
		else if(isUndefined(ident))
		{
			// undefined is evaluated to 0
			eval = EvalState.kEvalDead;
		}
		else if(ident.length > 1 && ident[0] == '!')
		{
			eval = evalExpression(ident[1..$]);
			if(eval == EvalState.kEvalDead)
				eval = EvalState.kEvalAlive;
			else if(eval == EvalState.kEvalAlive)
				eval = EvalState.kEvalDead;
		}
		else
		{
			// simple expressions with || and &&, == and !=, but not ()
			int pos = find(ident, "&&");
			if (pos < 0)
				pos = find(ident, "||");
			if (pos < 0)
				pos = find(ident, "==");
			if (pos < 0)
				pos = find(ident, "!=");
			if (pos >= 0)
			{
				int evalL = evalExpression(ident[0..pos]);
				int evalR = evalExpression(ident[pos+2 .. $]);
				if (ident[pos] == '&')
					eval = (evalL == EvalState.kEvalDead  || evalR == EvalState.kEvalDead)  ? EvalState.kEvalDead
					     : (evalL == EvalState.kEvalAlive && evalR == EvalState.kEvalAlive) ? EvalState.kEvalAlive
					     : EvalState.kEvalUnknown;
				else if (ident[pos] == '|')
					eval = (evalL == EvalState.kEvalDead  && evalR == EvalState.kEvalDead)  ? EvalState.kEvalDead
					     : (evalL == EvalState.kEvalAlive || evalR == EvalState.kEvalAlive) ? EvalState.kEvalAlive
					     : EvalState.kEvalUnknown;
				else if (ident[pos] == '=')
					eval = (evalL == EvalState.kEvalUnknown || evalR == EvalState.kEvalUnknown) ? EvalState.kEvalUnknown
					     : (evalL == evalR) ? EvalState.kEvalAlive : EvalState.kEvalDead;
				else if (ident[pos] == '!')
					eval = (evalL == EvalState.kEvalUnknown || evalR == EvalState.kEvalUnknown) ? EvalState.kEvalUnknown
					     : (evalL != evalR) ? EvalState.kEvalAlive : EvalState.kEvalDead;
			}
		}
		return eval;
	}

	int beginIfdef(bool ifdef, bool evaldef, bool elseif, string ident)
	{
		ident = strip(ident);
		int eval = EvalState.kEvalUnknown;
		if(evaldef)
			eval = evalExpression(ident);
		else if((ident in defines) || endsWith(ident, "_H")) // ifndef FILE_H
			eval = EvalState.kEvalAlive;
		else if(isUndefined(ident))
			eval = EvalState.kEvalDead;

		_versions ~= ident;
		_evalVersions ~= eval;

		if (eval == EvalState.kEvalUnknown)
		{
			if(elseif)
				_curText ~= "} else ";
			if(evaldef)
				_curText ~= "static if(" ~ ident ~ ") {\n";
			else if(ifdef)
				_curText ~= "version(" ~ ident ~ ") {\n";
			else // ifndef
				_curText ~= "version(" ~ ident ~ ") {} else {\n";
		}
		else if (eval == EvalState.kEvalAlive)
		{
			if (elseif)
				_curText ~= "} else {";
		}
		else if (elseif)
		{
			switch(_evalVersions[$-1])
			{
			case EvalState.kEvalUnknown:
			case EvalState.kEvalDeadAfterUnknown:
			case EvalState.kEvalAliveAfterUnknown:
				_curText ~= "}";
				break;
			case EvalState.kEvalDeadAfterAlive:
			case EvalState.kEvalAlive:
			case EvalState.kEvalDead:
				break;
			}
		}
		return eval;
	}

	void parseIfdef(bool ifdef)
	{
		PPEnabler disable = PPEnabler(this);
	
		if(!nextToken(tok) || tok.type != Token.Identifier)
			throw new Exception("identifier expected after #ifdef and #ifndef");

		string ident = tok.text;
		beginIfdef(ifdef, false, false, ident);
	}

	void parseIf()
	{
		PPEnabler disable = PPEnabler(this);

		string txt;
		while(nextToken(tok) && tok.type != Token.Newline)
			txt ~= tok.pretext ~ tok.text;

		beginIfdef(false, true, false, txt);
	}

	void parseElse()
	{
		PPEnabler disable = PPEnabler(this);

		assert(_evalVersions.length > 0);
		switch(_evalVersions[$-1])
		{
		case EvalState.kEvalUnknown:
			_curText ~= "} else {";
			_evalVersions[$-1] = EvalState.kEvalUnknown;
			break;
		case EvalState.kEvalDeadAfterAlive:
		case EvalState.kEvalAlive:
			_evalVersions[$-1] = EvalState.kEvalDeadAfterAlive;
			break;
		case EvalState.kEvalAliveAfterUnknown: 
			_curText ~= "}\n";
			_evalVersions[$-1] = EvalState.kEvalDeadAfterUnknown; 
			break;
		case EvalState.kEvalDead:
			_evalVersions[$-1] = EvalState.kEvalAlive; 
			break;
		case EvalState.kEvalDeadAfterUnknown:
			_curText ~= "} else {";
			_evalVersions[$-1] = EvalState.kEvalAliveAfterUnknown; 
			break;
		}
	}

	bool parseElif()
	{
		PPEnabler disable = PPEnabler(this);

		assert(_evalVersions.length > 0);
		if (_evalVersions[$-1] == EvalState.kEvalAlive || 
			_evalVersions[$-1] == EvalState.kEvalDeadAfterAlive)
			_evalVersions[$-1] = EvalState.kEvalDeadAfterAlive;
		else
		{
			int oldeval = _evalVersions[$-1];
			_versions = _versions[0..$-1];
			_evalVersions = _evalVersions[0..$-1];

			int curlen = _curText.length;
			string txt;
			while(nextToken(tok) && tok.type != Token.Newline)
				txt ~= tok.pretext ~ tok.text;

			int neweval = beginIfdef(false, true, true, txt);

			if (neweval == EvalState.kEvalUnknown)
			{
				if(oldeval == EvalState.kEvalDeadAfterUnknown)
				{
					_curText = "} else " ~ _curText;
					return true;
				}
				if(oldeval == EvalState.kEvalDead)
				{
					assert(_curText[curlen..curlen + 7] == "} else ");
					_curText = _curText[0..curlen] ~ _curText[curlen+7 .. $];
					return true;
				}
			}
		}
		return false;
	}

	void parseEndif()
	{
		PPEnabler disable = PPEnabler(this);

		switch(_evalVersions[$-1])
		{
		case EvalState.kEvalUnknown:
		case EvalState.kEvalDeadAfterUnknown:
		case EvalState.kEvalAliveAfterUnknown:
			_curText ~= "}";
			break;
		case EvalState.kEvalDeadAfterAlive:
		case EvalState.kEvalAlive:
		case EvalState.kEvalDead:
			break;
		}

		assert(_versions.length > 0);
		_versions = _versions[0..$-1];
		_evalVersions = _evalVersions[0..$-1];
	}

	string parseMacro(string ident)
	{
		// '(' already parsed

		string txt = "// #define " ~ ident ~ "(";
		string[] args;
		if(!nextToken(tok))
			throw new Exception("missing ) for macro " ~ ident);

		while(tok.type != Token.ParenR)
		{
			if(tok.type != Token.Identifier)
				throw new Exception("identifier expected as argument to macro " ~ ident);
			args ~= tok.text;
			txt ~= tok.pretext ~ tok.text;
			if (nextToken(tok) && tok.type == Token.Comma)
			{
				txt ~= tok.pretext ~ tok.text;
				nextToken(tok);
			}
		}
		txt ~= tok.pretext ~ tok.text;

		string text;
		while(nextToken(tok) && tok.type != Token.Newline)
			text ~= tok.pretext ~ tok.text;
		txt ~= text ~ "\n";

		PPDefine def = new PPDefine;
		def.ident = ident;
		def.args = args;
		def.text = text;
		_ppdefines[ident] = def;

		return txt;
	}

	void parseDefine()
	{
		PPEnabler disable = PPEnabler(this);

		if(!nextToken(tok) || tok.type != Token.Identifier)
		{
			if(tok.type != Token.Newline)
				throw new Exception("identifier expected after #define");
			return; // silently ignore empty lines, we have probably created them ourselfs
		}
		bool isEnum = false;
		string ident = tok.text;
		string txt = tok.pretext ~ tok.text;
		bool predef = isUndefined(ident) || (ident in defines);

		if(nextToken(tok) && tok.type == Token.ParenL && tok.pretext == "")
		{
			// macro with args, output comment only
			txt = parseMacro(ident);
		}
		else if (tok.type == Token.Newline)
		{
			// #define without text, assume version, but throw away header defines with trailing _H
			if (!predef && !endsWith(txt, "_H"))
				appendText("version = " ~ txt ~ tok.pretext ~ ";\n");
			return;
		}
		else
		{
			txt = "enum " ~ txt ~ " = ";
			txt ~= tok.pretext ~ tok.text;

			while(nextToken(tok) && tok.type != Token.Newline)
				txt ~= tok.pretext ~ tok.text;

			txt = replace(txt, "->", ".");
			txt ~= ";\n";
			if(predef)
				txt = "// " ~ txt;
		}
		appendText(txt);
	}

	bool tryExpandMacro(string ident)
	{
		if(!(ident in _ppdefines))
			return false;
		
		bool found = false;
		foreach(id; expands)
			if(id == ident)
				found = true;
		if(!found)
			return false;

		string txt = ident;
		string[] args;
		if(!nextToken(tok) || tok.type != Token.ParenL)
			throw new Exception("missing ( for macro " ~ ident);

		txt ~= tok.pretext ~ tok.text;
		string arg = "";
		int parenLevel = 0;
		while(nextToken(tok))
		{
			txt ~= tok.pretext ~ tok.text;
			if(parenLevel == 0 && (tok.type == Token.ParenR || tok.type == Token.Comma))
			{
				arg ~= tok.pretext;
				arg = strip(arg);
				if(arg != "")
					args ~= arg;
				if(tok.type == Token.ParenR)
					break;
				arg = "";
			}
			else
				arg ~= tok.pretext ~ tok.text;
			
			if(tok.type == Token.ParenL)
				parenLevel++;
			if(tok.type == Token.ParenR)
				parenLevel--;
		}
		if(tok.type != Token.ParenR)
			throw new Exception("missing ) for macro " ~ ident);

		PPDefine def = _ppdefines[ident];
		if(def.args.length != args.length)
			throw new Exception("wrong number of arguments for macro " ~ ident);

		string deftext = def.text;
		for(int i = 0; i < args.length; i++)
		{
			deftext = replaceToken(deftext, "#" ~ def.args[i], "\"" ~ args[i] ~ "\"");
			deftext = replaceToken(deftext, def.args[i], args[i]);
		}
		deftext = replace(deftext, "##", "");

		undoText(txt);
		_tokenizer.pushText(deftext);
		return true;
	}

	void parseOther()
	{
		PPEnabler disable = PPEnabler(this);

		string txt;
		while(nextToken(tok) && tok.type != Token.Newline)
			txt ~= tok.pretext ~ tok.text;
	}

	//////////////////////////////////////////////////////////////
	// end of Preprocessor

	string getScope()
	{
		string curscope;
		int nlevel = 0;
		int slevel = 0;
		while(nlevel < _namespaceLevels.length && slevel < _structLevels.length)
		{
			if(_namespaceLevels[nlevel] < _structLevels[slevel])
				curscope ~= _namespaces[nlevel++] ~ "::";
			else
				curscope ~= _structs[slevel++] ~ "::";
		}
		while(nlevel < _namespaceLevels.length)
			curscope ~= _namespaces[nlevel++] ~ "::";
		while(slevel < _structLevels.length)
			curscope ~= _structs[slevel++] ~ "::";

		return curscope;
	}

	bool isConstructor(string func)
	{
		int pos = rfind(func, "::");
		if(pos < 0)
			return false;
		string fn = func[pos + 2 .. $];
		string clss = func[0..pos];
		int pos2 = rfind(clss, "::");
		if(pos2 >= 0)
			clss = clss[pos2 + 2 .. $];
		return fn == clss;
	}
	bool isDestructor(string func)
	{
		return find(func, "~") >= 0;
	}

	void parseNamespace()
	{
		if(!nextToken(tok) || tok.type != Token.Identifier)
			throw new Exception("identifier expected after namespace");
		string ident = tok.text;
		if(!nextToken(tok) || tok.type != Token.BraceL)
			throw new Exception("{ expected after namespace");
		_namespaces ~= ident;
		_namespaceLevels ~= _braces;
		_braces++;
	}

	void parseInclude()
	{
		PPEnabler disable = PPEnabler(this);
		if(!nextToken(tok))
			throw new Exception("file name expected after include");
		
		string fname;
		if (tok.type == Token.String)
			fname = tok.text;
		else if (tok.type == Token.LessThan)
		{
			fname = tok.text;
			while(nextToken(tok) && tok.type != Token.GreaterThan && tok.type != Token.Newline)
				fname ~= tok.pretext ~ tok.text;
			if (tok.type != Token.GreaterThan)
				throw new Exception("missing terminating '>' for include file name");
			fname ~= tok.pretext ~ tok.text;
		}
		else
			throw new Exception("file name as string or inside <> expected after include");

		addunique(_imports, fname);
	}

	string skipStructKeyword(string txt)
	{
		if(startsWith(txt,"class"))
			return txt[5..$];
		else if(startsWith(txt,"struct"))
			return txt[6..$];
		else if(startsWith(txt,"union"))
			return txt[5..$];
		else if(startsWith(txt,"enum"))
			return txt[4..$];
		throw new Exception("struct, class or union expected instead of " ~ txt);
	}

	// return true if an opening brace was found, returning false causes a reparsing of the last token
	bool parseStruct(string* pident = null)
	{
		int pos = textPos() - tok.text.length;
		string structype = tok.text;

		if(!nextToken(tok) || (tok.type != Token.Identifier && tok.type != Token.BraceL))
			throw new Exception("identifier or { expected after struct or class keyword");

		string ident;
		if (tok.type != Token.Identifier)
		{
			string txt = tok.pretext ~ tok.text;
			undoText(txt);
			// figure out a unique name
			ident = structype ~ "_" ~ replace(baseName(_file), ".", "_") ~ "_" ~ format("%d", _tokenizer.lineno);
			appendText(" " ~ ident ~ " " ~ txt);
		}
		else
		{
			ident = tok.text;
			if(!nextToken(tok))
				return false;
		}
		if(pident)
			*pident = ident;

		string scp = getScope();
		if(structype == "struct" || structype == "class")
		{
			// figure out what structs or classes are POD
			string newtype;
			if(tok.type == Token.Colon || isClassName(scp ~ ident))
				newtype = "class";
			else
				newtype = "struct";
			if(newtype != structype)
				replaceTextAt(pos, structype, newtype);
		}

		if (tok.type == Token.Colon || tok.type == Token.BraceL)
			addunique(_structDecls, ident);
		else if (tok.type == Token.Semicolon)
		{
			// throw away forward declarations, but remember for imports
			addunique(_structImports, ident);
			undoTextPos(pos);
			popTypedefLevel(false);
		}
		else
		{
			// this is not a declaration of the class, but some var with unnecessary struct/class
			// so remove it
			string tail = getTextTail(textPos() - pos);
			undoTextPos(pos);
			tail = skipStructKeyword(tail);
			appendText(tail);
		}

		if (tok.type == Token.BraceL || tok.type == Token.Colon)
		{
			_structs ~= ident;
			_structStart ~= pos;
			_structLevels ~= _braces;
		}
		if (tok.type == Token.Colon)
		{
			if (nextToken(tok))
			{
				if (tok.type != Token.Identifier)
					throw new Exception("base class identifier expected after ':'");
				if (tok.text == "public" || tok.text == "private" || tok.text == "protected")
				{
					nextToken(tok);
					if (tok.type != Token.Identifier)
						throw new Exception("base class identifier expected after ':'");
				}
				if(_dmd2d)
				{
					_dmd2d.baseClasses[scp ~ ident] = scp ~ tok.text;
					_dmd2d.derivedClasses[scp ~ tok.text] ~= scp ~ ident;
				}
			}
		}

		if(tok.type != Token.BraceL)
			return false;

		_braces++;
		return true;
	}

	// returning false causes a reparsing of the last token
	bool parseEnum()
	{
		int pos = textPos();
		if(!nextToken(tok) || (tok.type != Token.Identifier && tok.type != Token.BraceL))
			throw new Exception("identifier or { expected after enum keyword");
		if(tok.type != Token.Identifier)
			return false;
		if(!nextToken(tok) || tok.type == Token.BraceL)
			return false;

		// remove enum
		string txt = getTextTail(textPos() - pos);
		undoTextPos(pos);
		undoText("enum");
		if(tok.type != tok.Semicolon) // no forward declarations!
			appendText(txt);
		return false;
	}

	string getBaseClass(string type)
	{
		if (!_dmd2d)
			return "";
		return _dmd2d.getBaseClass(type);
	}

	string moveBaseConstructor(string fnbody)
	{
		// translate ": baseclass(arg) {" -> "{ super(arg);"
		int pos = 0;
		while(pos < fnbody.length && isspace(fnbody[pos]))
			pos++;
		if(pos >= fnbody.length || fnbody[pos] != ':')
			return fnbody;
		
		int namepos = pos + 1;
		while(namepos < fnbody.length && isspace(fnbody[namepos]))
			namepos++;
		int nameend = namepos;
		while(nameend < fnbody.length && (isalnum(fnbody[nameend]) || fnbody[nameend] == '_'))
			nameend++;
		if(namepos >= nameend)
			return fnbody;

		int bodypos = nameend;
		while(bodypos < fnbody.length && fnbody[bodypos] != '{')
			bodypos++;

		if(bodypos >= fnbody.length)
			return fnbody;

		string name = fnbody[namepos .. nameend];
		string baseClass = getBaseClass(getScope());
		if(_dmd2d && name == baseClass)
			name = "super";

		string fn = strip(fnbody[nameend .. bodypos]);
		fn = removeComments(fn);
		string txt = "{ " ~ name ~ fn ~ ";" ~ fnbody[bodypos + 1 .. $];
		return txt;
	}

	static string mergePrototypes(string defProto, string dclProto)
	{
		if(defProto == dclProto)
			return defProto;

		// merge default initializer
		int defPos = 1;
		int dclPos = 1;

		while(defPos < defProto.length - 1 && dclPos < dclProto.length - 1)
		{
			int defArgLen = getArgumentLength(defProto, defPos);
			if(defArgLen < 0)
				defArgLen = defProto.length - defPos - 1;
        		
			int dclArgLen = getArgumentLength(dclProto, dclPos);
			if(dclArgLen < 0)
				dclArgLen = dclProto.length - dclPos - 1;

			string defArg = defProto[defPos .. defPos + defArgLen];
			string dclArg = dclProto[dclPos .. dclPos + dclArgLen];

			int defArgAsgn = find(defArg, '=');
			int dclArgAsgn = find(dclArg, '=');

			if(defArgAsgn < 0 && dclArgAsgn >= 0)
			{
				string definit = dclArg[dclArgAsgn .. $];
				string newdef  = defProto[0..defPos + defArgLen] ~ " " ~ definit;
				defProto = newdef ~ defProto[defPos + defArgLen .. $];
				defPos += definit.length + 1;
			}
			defPos += defArgLen + 1;
			dclPos += dclArgLen + 1;
		}
		return defProto;
	}

	unittest 
	{
		string def  = "(Identifier **pident, TemplateParameters **tpl)";
		string decl = "(Identifier **pident = null, TemplateParameters **tpl = null)";
		string p = Source.mergePrototypes(def, decl);
		assert(p == decl);
	}

	bool startFunction()
	{
		// not allowed to be intercepted by pp commands
		int startpos = textPos() - tok.text.length;
		string ident = tok.text;
		if(tok.type == Token.Tilde)
			goto dtor_entry;
		if(tok.text == "operator")
			goto operator_entry;

		while(nextToken(tok) && tok.type == Token.DoubleColon)
		{
			ident ~= tok.pretext ~ tok.text;
			if(nextToken(tok) && tok.type == Token.Tilde)
			{
				ident ~= tok.pretext ~ tok.text;
			dtor_entry:
				if(!nextToken(tok) || tok.type != Token.Identifier)
					throw new Exception("identifier expected after ~");
			}
			if(tok.type != Token.Identifier)
				throw new Exception("identifier expected after ::");
			ident ~= tok.pretext ~ tok.text;
			if(tok.text == "operator")
			{
			operator_entry:
				// only new and delete allowed
				if(nextToken(tok) && tok.type != Token.Identifier)
					throw new Exception("identifier expected after operator");
				ident ~= tok.pretext ~ tok.text;
			}
		}
		if(tok.type != Token.ParenL)
		{
			if(find(ident, "::") >= 0)
			{
				bool hasInit = false;
				string init;
				// throw away empty static initializers
				while(tok.type != Token.Semicolon)
				{
					if(tok.type == Token.Assign)
						hasInit = true;
					else if (hasInit)
						init ~= tok.pretext ~ tok.text;
					if(!nextToken(tok))
						break;
				}
				if(hasInit && strip(init) != "0")
				{
					if (_dmd2d)
						_dmd2d.initializer[ident] = init;
				}
				undoTextPos(_statementStart);
				return true;
			}
			else if (tok.type == Token.Semicolon && _pass == kPassRewrite && _dmd2d)
			{
				string id = getScope() ~ ident;
				if(id in _dmd2d.initializer)
				{
					undoText(tok.text);
					appendText(" = " ~ _dmd2d.initializer[id] ~ ";");
				}
			}
			return false;
		}

		// function begin
		string curScope = getScope();

		_curFunc = curScope ~ ident;
		_funcBodyStart = -1;
		_funcBraceLevel = _braces;
		_funcProtoStart = textPos() - 1;
		_funcDeclStart = _statementStart;
		_funcNameStart = startpos;
		_inContract = false;
		_parenthesis++;

		if(_pass == kPassDefineFunctions && _dmd2d)
			_dmd2d.memberFunctions[curScope]++;

		// appendText("/* StartFunction " ~ _curFunc ~ " */");
		return true;
	}

	void endFunction()
	{
		if(_pass == kPassCollectClasses)
		{
			if(_dmd2d)
				_dmd2d.addPrototype(_curFunc, _curProto);
		}
		else if(_pass == kPassDefineFunctions)
		{
			string fn = _curFunc ~ _curProto;
			if(_dmd2d && (fn in _dmd2d.functions))
				throw new Exception("duplicate definition of " ~ fn);

			// end of function definition
			int pos = textPos();
			int funclen = pos - _funcBodyStart;
			string fnbody = getTextTail(funclen);

			if(_dmd2d)
				_dmd2d.functions[fn] = fnbody;
		}
		else if(_pass == kPassRewrite)
		{
			if(_structLevels.length == 0 && find(_curFunc, "::") >= 0)
			{
				// remove member definitions outside of class
				assert(_funcDeclStart >= 0);
				undoTextPos(_funcDeclStart);
			}
			else if(_structLevels.length > 0)
			{
				bool isCtor = isConstructor(_curFunc);
				bool isDtor = isDestructor(_curFunc);
				if (isCtor || isDtor)
				{
					// replace class name with "this"
					int pos = textPos();
					int bodylen = pos - _funcBodyStart;
					int protolen = _funcBodyStart - _funcProtoStart;
					int namelen = _funcProtoStart - _funcNameStart;
					if(isDtor)
						namelen--; // keep '~'

					string fnbody = getTextTail(bodylen);
					undoTextPos(_funcBodyStart);
					string proto = getTextTail(protolen);
					undoTextPos(_funcProtoStart);
					string name = getTextTail(namelen);
					undoText(name);
					assert(name == _structs[$-1]);

					if(isCtor)
						fnbody = moveBaseConstructor(fnbody);
					if(isCtor && !isClassName(getScope()) && strip(proto) == "()")
						appendText("void ctor_this");
					else
						appendText("this");
					appendText(proto);
					appendText(fnbody);
				}
			}
		}
		_funcDeclStart = -1;
		_funcNameStart = -1;
		_curFunc = "";
		_funcBodyStart = -1;
		_isnaked = false;
	}

	void endFunctionDeclaration()
	{
		// function declaration
		if(_structLevels.length == 0) // _braces == 0)
		{
			// we don't need forward declarations
			assert(find(_curFunc, "::") < 0);
			undoTextPos(_funcDeclStart);
		}
		else if(_dmd2d)
		{
			string fn = findFunction(_curFunc, _curProto);
			if(fn in _dmd2d.functions)
			{
				undoText(";");
				string declfn = _curFunc ~ _curProto;

				int lppos = find(fn, "(");
				assert(lppos >= 0);
				string fnproto = fn[lppos..$];
				string fnbody = _dmd2d.functions[fn];

				fnproto = mergePrototypes(fnproto, _curProto);

				undoText(_curProto);
				assert(_funcNameStart >= 0);
				if(isConstructor(_curFunc))
				{
					undoTextPos(_funcNameStart);
					if(strip(fnproto) == "()" && !isClassName(getScope()))
						appendText("void ctor_this");
					else
						appendText("this");
					fnbody = moveBaseConstructor(fnbody);
				}
				else if(isDestructor(_curFunc))
				{
					undoTextPos(_funcNameStart);
					appendText("~this");
				}
				appendText(fnproto);
				if(fn != declfn)
					appendText(" /* replaces " ~ declfn ~ " */");

				string fnindented = indentFunc(fnbody);
				appendText(fnindented);
			}
			else if(_pass == kPassRewrite)
			{
				string decl = getAbstractDecl();
				if (decl.length > 0)
				{
					undoText(decl);
					appendText(" { assert(false); } /* abstract */");
				}
				else
				{
					//throw new Exception("no implementation for " ~ _curFunc);
					string msg = _file ~ "(" ~ format(_tokenizer.lineno) ~ "): no implementation for " ~ _curFunc ~ _curProto;
					writefln(msg);
					appendText(" /*!!! NO IMPLEMENTATION !!!*/");
				}
			}
		}
		_curFunc = "";
		_funcDeclStart = -1;
		_funcNameStart = -1;
		_funcBodyStart = -1;
		_isnaked = false;
	}

	int identicalChars(string s1, string s2)
	{
		int len = min(s1.length, s2.length);
		for (int i = 0; i < len; i++)
			if (s1[i] != s2[i])
				return i;
		return len;
	}

	static int getArgumentLength(string proto, int pos)
	{
		int startpos = pos;
		while(pos < proto.length)
		{
			switch(proto[pos])
			{
				case ',':
					return pos - startpos;
				case '(':
					pos = posClosingParenthesis(proto, pos + 1, '(', ')');
					if(pos < 0)
						return -1;
					break;
				default:
					break;
			}
			pos++;
		}
		return -1;
	}

	static int countArguments(string proto)
	{
		int pos = find(proto, "(");
		if(pos < 0)
			return -1;
		pos++;
		int cnt = 0;
		while(pos < proto.length)
		{
			int len = getArgumentLength(proto, pos);
			if(len < 0)
				break;
			pos += len + 1;
		}
		return cnt;
	}

	string findFunction(string func, string proto)
	{
		string fn = func ~ proto;
		if(fn in _dmd2d.functions)
			return fn;
		fn = func ~ "(";
		string[] found;
		// only one implementation?
		// only take candidates with same number of args
		int args = countArguments(proto);
		foreach(string f, fnbody; _dmd2d.functions)
			if(startsWith(f, fn) && countArguments(f) == args)
				found ~= f;
		if(found.length == 1)
			return found[0];
		if(found.length == 0)
			return "";

		// search longest start match 
		fn = func ~ proto;
		string[] longest;
		int longestlen = 0;
		foreach(string f; found)
		{
			int len = identicalChars(fn, f);
			if(len > longestlen)
			{
				longest.length = 0;
				longest ~= f;
				longestlen = len;
			}
			else if(len == longestlen)
			{
				longest ~= f;
			}
		}
		if(longest.length == 1)
			return longest[0];
		return "";
	}

	string getAbstractDecl()
	{
		int len = _newText.length + _curText.length;
		int pos = len - 1;
		if (pos < 0 || getChar(pos) != ';')
			return "";
		pos--;
		while(pos >= 0 && isspace(getChar(pos)))
			pos--;
		if (pos < 0 || getChar(pos) != '0')
			return "";
		pos--;
		while(pos >= 0 && isspace(getChar(pos)))
			pos--;
		if (pos < 0 || getChar(pos) != '=')
			return "";
		pos--;
		while(pos >= 0 && isspace(getChar(pos)))
			pos--;

		return getTextTail(len - pos - 1);
	}

	string getTokenBefore(int pos)
	{
		pos--;
		while(pos >= 0 && isspace(getChar(pos)))
			pos--;
		if(pos < 0)
			return "";
		char ch = getChar(pos);
		string txt = [ch];
		if(!isalnum(ch) && ch != '_')
			return txt;

		while(--pos >= 0)
		{
			ch = getChar(pos);
			if (!isalnum(ch) && ch != '_')
				break;
			txt = ch ~ txt;
		}
		return txt;
	}

	bool isClassType(string type)
	{
		foreach(name; _structImports)
			if(name == type)
				return true;
		foreach(name; _structDecls)
			if(name == type)
				return true;
		return false;
	}

	bool isGlobalClassType(string type)
	{
		if(!_dmd2d)
			return isClassType(type);

		foreach(src; _dmd2d.sources)
			if (src.isClassType(type))
				return true;

		return false;
	}

	bool isClassName(string s)
	{
		if(!_dmd2d)
			return false;
		return _dmd2d.isClassName(s);
	}

	int checkStackVarConstructor(ref string ident)
	{
		switch(tok.text)
		{
		case "static":
		case "inline":
		case "return":
		case "else":
		case "enum":
		case "case":
		case "goto":
			return 0;
		default:
			break;
		}
		string type = tok.text;
		if(!isGlobalClassType(type))
			return 0;

		if(!nextToken(tok) || tok.type != Token.Identifier)
			return -1;
		if(!nextToken(tok) || tok.type != Token.ParenL)
			return -2;

		undoText(tok.text);
		appendText(" = new " ~ type ~ tok.text);

		ident = type;
		_parenthesis++;
		return 1;
	}

	bool isUnaryOp(string txt)
	{
		switch(txt)
		{
		case "&":
		case "!":
		case "~":
		case "-":
		case "+":
		case "*":
			return true;
		default:
			return false;
		}
	}

	void checkCast()
	{
		_checkCastNext = false;
		if(onTypedefLevel() || _funcBodyStart < 0)
			return;

		// _checkCastNext set on ')', if '*' before it, it's probably also a cast
		int rpos = textPos() - tok.text.length - tok.pretext.length - 1;
		// a comment in between makes this test fail, but that is considered ok
		bool isCast = isUnaryOp(tok.text) && (getChar(rpos) == ')' && getChar(rpos - 1) == '*');

		if (isCast || tok.type == Token.Identifier || tok.type == Token.Number || 
		    tok.type == Token.ParenL || tok.type == Token.String || tok.type == Token.DoubleColon)
		{
			// insert cast before previous '('
			int pos = textPos() - tok.text.length;
			int level = 0;
			while(pos > 0)
			{
				pos--;
				char ch = getChar(pos);
				if(ch == '\n')
					return; // assume no cast across line-break (avoid parsing comments backwards)
				if(ch == ')')
					level++;
				else if(ch == '(')
				{
					assert(level > 0);
					level--;
					if(level == 0)
					{
						int npos = pos+1;
						while(npos < rpos && isspace(getChar(npos)))
							npos++;
						if(getChar(npos) == '*') // it's probably a call to function supplied by a pointer (*fn)()
							return;

						string token = getTokenBefore(pos);
						if (token != "if" && token != "for" && token != "while")
						{
							string txt = getTextTail(textPos() - pos);
							undoTextPos(pos);
							appendText("cast" ~ txt);
						}
						return;
					}
				}
			}
			assert(false);
		}
	}

	bool onTypedefLevel()
	{
		return _typedefLevels.length > 0 && _typedefLevels[$-1] == _braces;
	}

	void popTypedefLevel(bool checkIdentical)
	{
		if (onTypedefLevel())
		{
			if (checkIdentical)
			{
				string txt = getTextTail(textPos() - _typedefPositions[$-1]);
				int pos = txt.length;
				if(pos > 0 && txt[pos - 1] == ';')
					pos--;

				int idpos = posBeginDeclIdent(txt, pos);
				string ident = txt[idpos .. pos];
				string type = strip(txt[0..idpos]);
				if(_dmd2d)
				{
					if (!(ident in _dmd2d.typedefs))
					{
						_dmd2d.typedefs[ident] = type;
						_dmd2d.typedefLines[ident] = _tokenizer.lineno;
					}
					else if (_dmd2d.typedefs[ident] != type)
						throw new Exception("different typedefs for " ~ ident);
					else if (_dmd2d.typedefLines[ident] != _tokenizer.lineno)
					{
						undoTextPos(_typedefPositions[$-1]);
						undoText("typedef");
					}
				}
			}
			_typedefLevels.length = _typedefLevels.length - 1;
			_typedefPositions.length = _typedefPositions.length - 1;
		}
	}

	// return true if reparsing of current token wanted
	bool parseTypedef()
	{
		int nextpos = textPos();
		_typedefLevels ~= _braces;
		_typedefPositions ~= nextpos;

		if(!nextToken(tok))
			return false;
		if (tok.type != Token.Struct && tok.type != Token.Class && tok.type != Token.Union && tok.type != Token.Enum)
			return true;

		// remove typedef
		string structype = tok.text;
		string structtxt = getTextTail(textPos() - nextpos);
		undoTextPos(nextpos);
		undoText("typedef");
		int typedefpos = textPos();
		appendText(structtxt);
		int structpos = typedefpos + tok.pretext.length;

		string ident;
		if (!parseStruct(&ident))
		{
			if(tok.type == Token.Identifier && tok.text == ident)
			{
				// throw it all away
				if (nextToken(tok) && tok.type == Token.Semicolon)
				{
					undoTextPos(typedefpos);
					popTypedefLevel(false);
					return false;
				}
			}

			// reinsert typedef, but struct/class already removed by parseStruct
			string txt = getTextTail(textPos() - structpos);
			undoTextPos(structpos);
			appendText("typedef");
			_typedefPositions[$-1] = textPos();

			//txt = skipStructKeyword(txt);
			appendText(txt);
		}
		else if (structype == "enum")
			_enumState = EnumState.kIdentifier;

		return false;
	}

	bool onFunctionLevel()
	{
		if(onTypedefLevel())
			return false;
		if(_parenthesis > 0)
			return false;
		if(_curFunc != "" || _funcBodyStart >= 0) // otherwise it's not top- or class-level
			return false;
		int level = 0;
		if(_structLevels.length > 0)
			level = _structLevels[$-1] + 1;
		if(_namespaceLevels.length > 0)
			level = max(_namespaceLevels[$-1] + 1, level);
		if(_externLevels.length > 0)
			level = max(_externLevels[$-1] + 1, level);
		if(_braces > level)
			return false;
		return true;
	}

	bool splitDeclaration()
	{
		bool isFuncList = (_curFunc != "" && _funcBodyStart < 0);
		if(!nextToken(tok) || (!isFuncList && tok.type != Token.Asterisk))
			return false;

		return doSplitDeclaration(false);
	}

	bool doSplitDeclaration(bool log)
	{
		// we have just read ",*"
		// if this is not in paranthesis, it is a declaration of the form "type x,*y;" 
		// that must be split into "type x; type *y;"
		// "type x,*y,z;" must be replaced by "type x; type *y; type z;"
		// the following code will not work for "type *x,y;" !!!

		// find the beginning of the declaration, e.g. a '{', '}' or ';'
		int rpos = textPos() - tok.pretext.length - tok.text.length; // on ','

		int spos = rpos;
		while(spos > 0)
		{
			char ch = getChar(spos - 1);
			if(ch == '{' || ch == '}' || ch == ';')
				break;
			spos--;
		}
		// skip following white spaces
		while(spos < rpos)
		{
			char ch = getChar(spos);
			if(!isspace(ch))
				break;
			spos++;
		}

		string txt = getTextTail(textPos() - spos);
		txt = removeComments(txt);
		txt = strip(txt);

		if(log)
		{
			string msg = _file ~ "(" ~ format(_tokenizer.lineno) ~ "): doSplitdeclaration for " ~ txt;
			writefln(msg);
		}

		int idpos = findOutsideParenthesis(txt, ',', 0);
		assert(idpos >= 0);

		// read identifier backwards
		idpos = posBeginDeclIdent(txt, idpos);

		// check for an assignment
		int npos = idpos;
		while(npos > 0 && isspace(txt[npos - 1]))
			npos--;
		if(npos > 0 && txt[npos - 1] == '=')
		{
			idpos = posBeginDeclIdent(txt, npos - 1);
		}

		// skip arbitrary number of '*'
		while(idpos > 0 && txt[idpos - 1] == '*')
			idpos--;

		string type = txt[0..idpos];

		// slurp in everything until the next ';'
		while(nextToken(tok) && tok.type != Token.Semicolon) {}

		string decltxt = getTextTail(textPos() - spos);
		undoTextPos(spos);
		decltxt = replace(decltxt, "->", ".");
		decltxt = replaceOutsideParenthesis(decltxt, ',', "; " ~ type);
		appendText(decltxt);

		// last token is ';'
		return true;
	}

	void insertRefToFuncArgument()
	{
		int pos = textPos();
		while(pos > 0)
		{
			char ch = getChar(pos - 1);
			if(ch == ',' || ch == '(')
				break;
			pos--;
		}

		string txt = getTextTail(textPos() - pos);
		undoTextPos(pos);
		appendText("ref ");
		appendText(txt);
	}

	bool parseAsm()
	{
		undoText(tok.text);
		appendText("asm");

		if(!nextToken(tok))
			return true;

		bool reparse = false;
		_tokenizer.skipNewline = false;
		if(tok.type == Token.BraceL)
		{
			if (_isnaked)
				appendText(" naked;");

			int prevtype = Token.Newline;
			int prevtype_nonl = Token.Newline;
			while(nextToken(tok) && tok.type != Token.BraceR)
			{
				if (tok.type == Token.Newline && prevtype != Token.Newline && prevtype != Token.Colon)
				{
					undoText("\n");
					appendText(";\n");
				}
				else if(tok.type == Token.Semicolon)
				{
					appendText(" //");
					while(nextToken(tok) && tok.type != Token.Newline) {}
				}
				// check for misguided empty instructions replaced by {}
				else if(tok.type == Token.BraceL)
					if(nextToken(tok) && tok.type == Token.BraceR)
					{
						undoText("{}");
						appendText("// ");
					}
				prevtype = tok.type;
				if(tok.type != Token.Newline)
					prevtype_nonl = tok.type;
			}
			if(prevtype_nonl == Token.Colon)
			{
				// need an ';' to terminate asm block
				string txt = tok.pretext ~ tok.text;
				undoText(txt);
				appendText("; " ~ txt);
			}
		}
		else
		{
			bool justInsertedSemicolon = false;
			string txt = tok.pretext ~ tok.text;
			undoText(txt);
			appendText(" {" ~ txt);
			while(nextToken(tok) && tok.type != Token.BraceR && tok.type != Token.Newline)
			{
				justInsertedSemicolon = false;
				if (tok.type == Token.__Asm)
				{
					undoText(tok.text);
					appendText(";");
					justInsertedSemicolon = true;
				}
				else if(tok.type == Token.Semicolon)
				{
					appendText(" //");
					while(nextToken(tok) && tok.type != Token.Newline) {}
				}
			}
			if(tok.type == Token.BraceR)
				reparse = true;

			txt = tok.pretext ~ tok.text;
			undoText(txt);
			appendText("; }" ~ txt);
		}
		_tokenizer.skipNewline = true;

		return !reparse;
	}

	bool parseBraceL()
	{
		if(_curFunc != "" && _braces == _funcBraceLevel)
		{
			// start of function definition
			if(_funcBodyStart < 0)
				_funcBodyStart = textPos() - tok.text.length - tok.pretext.length;
		}
		else if(_inRHS == _parenthesis)
		{
			_levelRHS--;
			if(_levelRHS >= 0)
			{
				// array initializer
				undoText("{");
				appendText("[");
			}
		}
		_braces++;
		return true;
	}

	bool parseBraceR()
	{
		if(_braces <= 0)
			throw new Exception("too many closing braces");
		_braces--;

		if(_inRHS == _parenthesis)
		{
			if(_levelRHS >= 0)
			{
				// array initializer
				undoText("}");
				appendText("]");
			}
			_levelRHS++;
		}
		bool reparse = false;
		if(_namespaceLevels.length > 0 && _braces == _namespaceLevels[$-1])
		{
			_namespaces = _namespaces[0..$-1];
			_namespaceLevels = _namespaceLevels[0..$-1];
		}
		if(_externLevels.length > 0 && _braces == _externLevels[$-1])
		{
			undoText(tok.text);
			_externLevels = _externLevels[0..$-1];
		}
		if(_structLevels.length > 0 && _braces == _structLevels[$-1])
		{
			if(nextToken(tok))
			{
				reparse = true;
				if (tok.type != Token.Semicolon)
				{
					reparse = false;
					undoText(tok.text);
					if (onTypedefLevel())
					{
						// translate "typedef struct X { } X;" -> "struct X { };"
						// translate "typedef struct X { } Y;" -> "struct X { } typedef X Y;"
						if (tok.type != Token.Identifier || tok.text != _structs[$-1])
						{
							_typedefPositions[$-1] = textPos() + 8; // after "typedef"
							appendText("\ntypedef " ~ _structs[$-1] ~ " " ~ tok.text);
						}
						popTypedefLevel(true);
					}
					else
					{
						// translate "[static] struct X { } Y;" -> "struct X { } [static] X Y;"
						string beforeStruct = getText(_structStart[$-1] - 7, 7);
						if(beforeStruct == "static ")
							removeTextAt(_structStart[$-1] - 7, beforeStruct);
						else
							beforeStruct = "";
						appendText("\n" ~ beforeStruct ~ _structs[$-1] ~ " " ~ tok.text);
					}
				}
				else
				{
					// remove name inserted for unnamed union/struct 
					if(startsWith(_structs[$-1], "struct_"))
						removeTextAt(_structStart[$-1] + 7, _structs[$-1].length);
					if(startsWith(_structs[$-1], "union_"))
						removeTextAt(_structStart[$-1] + 6, _structs[$-1].length);
				}
			}
			_structs = _structs[0..$-1];
			_structStart = _structStart[0..$-1];
			_structLevels = _structLevels[0..$-1];
		}
		if(_curFunc != "" && _braces == _funcBraceLevel)
		{
			if(_inContract)
				_inContract = false;
			else
				endFunction();
		}
		_statementStart = -1;
		_enumState = EnumState.kNone;

		return !reparse;
	}

	bool parseIdentifier()
	{
		if(tryExpandMacro(tok.text))
		{
		}
		else if(tok.text == "virtual")
		{
			undoText(tok.text);
		}
		else if(tok.text == "new")
		{
			int pos = textPos() - tok.text.length;
			if(nextToken(tok) && tok.type == Token.Identifier)
			{
				if (isClassName(tok.text))
				{
					insertTextAt(pos, "toPtr(");
					_toPtrLevel ~= _parenthesis;
				}
			}
			return false;
		}
		else if(tok.text == "this")
		{
			int pos = textPos() - tok.text.length;
			if(nextToken(tok))
			{
				if(tok.type != Token.Deref)
					insertTextAt(pos, "&");
				return false;
			}
		}
		else if(_enumState == EnumState.kIdentifier)
		{
			if(_dmd2d)
				_dmd2d.enumIdent[tok.text] = getScope();
		}
		else if(_dmd2d && (tok.text in _dmd2d.enumIdent))
		{
			string scp = getScope();
			string enumscp = _dmd2d.enumIdent[tok.text];
			undoText(tok.text);
			if(startsWith(enumscp, scp))
				enumscp = enumscp[scp.length .. $];
			enumscp = replace(enumscp, "::", ".");
			appendText(enumscp ~ tok.text);
		}
		else if(onFunctionLevel())
		{
			if (!startFunction())
				return false;
		}
		else if (_funcBodyStart >= 0)
		{
			string ident = tok.text;
			int res = checkStackVarConstructor(ident);
			if (res == 1 && _dmd2d)
				goto parenRead;
			if (res == -1 && _dmd2d)
				goto tokenRead;
			if (res < 0)
				return false;
			if (res == 0 && _dmd2d)
			{
				// nothing read by checkStackVarConstructor()
				// check special function call arguments
				if(nextToken(tok))
				{
				tokenRead:
					if(tok.type == Token.ParenL)
					{
						_parenthesis++;
					parenRead:
						if(string* proto = ident in _dmd2d.prototypes)
						{
							if(startsWith(*proto, "(Loc "))
							{
								if(nextToken(tok) && tok.text == "0")
								{
									undoText("0");
									appendText("Loc.zero");
									return true;
								}
								return false;
							}
						}
						return true;
					}
					return false;
				}
			}
		}
		return true;
	}

	bool parseAsterisk()
	{
		return true;

		if(!_dmd2d || !_dmd2d.classPtrToReference)
			return true;
		// remove '*' if previous token is a classname, converting pointers to references
		string ident = getTokenBefore(textPos() - tok.text.length - tok.pretext.length);
		if(!isClassName(ident))
			return true;
		undoText("*");
		while(nextToken(tok) && tok.type == Token.Asterisk) {} // do not remove multiple '*'
		return false;
	}

	bool parseString()
	{
		if(tok.text[0] == 'L')
		{
			undoText(tok.text);
			appendText(tok.text[1..$]);
		}
		if(addStringPtr && tok.text[0] == '"')
		{
			int startpos = textPos();
			int pos = startpos;
			while(nextToken(tok) && tok.type == Token.String)
			{
				int stringpos = textPos() - tok.text.length;
				removeTextAt(pos - 1, stringpos + 1 - (pos - 1));
				pos = textPos();
			}
			insertTextAt(pos, ".ptr");
			if(pos - startpos > 80)
			{
				string txt = getTextTail(textPos() - startpos);
				undoTextPos(startpos);
				txt = replace(txt, "\\n", "\n");
				appendText(txt);
			}
			return false;
		}
		return true;
	}

	void parseLiveCode()
	{
	reparseToken:
		if(_statementStart < 0)
			if(!Token.isPPToken(tok.type))
				_statementStart = textPos() - tok.text.length;

		if(_checkCastNext)
			checkCast();

		switch(tok.type)
		{
		case Token.BraceL:
			if (!parseBraceL())
				goto reparseToken;
			break;

		case Token.BraceR:
			if (!parseBraceR())
				goto reparseToken;
			break;

		case Token.Namespace:
			parseNamespace();
			break;

		case Token.Struct:
		case Token.Class:
		case Token.Union:
			if (!parseStruct())
				goto reparseToken;
			break;

		case Token.Enum:
			if (!parseStruct())
				goto reparseToken;

			_enumState = EnumState.kIdentifier;
			/*if (onFunctionLevel())
			{
				if (!startFunction())
					goto reparseToken;
			}*/
			break;

		case Token.Const:
			if (nextToken(tok))
			{
				if(tok.type != Token.Identifier)
					throw new Exception("type identifier expected after const");
				undoText(tok.text);
				appendText("(" ~ tok.text ~ ")");
			}
			break;

		case Token.Extern:
			int pos = textPos() - tok.text.length;
			if (nextToken(tok))
			{
				if (tok.type == Token.ParenL)
				{
					checkNextToken(Token.Identifier);
					checkNextToken(Token.ParenR);
					break;
				}
				if (tok.type == Token.String)
				{
					undoText(tok.text);
					nextToken(tok);
				}
				if (tok.type == Token.BraceL)
				{
					undoTextPos(pos);
					_externLevels ~= _braces;
					goto reparseToken;
				}
				// throw away extern declarations
				while(tok.type != Token.Semicolon && tok.type != Token.BraceL)
					if (!nextToken(tok))
						break;

				if (tok.type == Token.BraceL)
				{
					// function body after extern ? remove extern and reparse
					string txt = getTextTail(textPos() - pos);
					undoTextPos(pos);
					assert(startsWith(txt, "extern"));
					txt = txt[6..$];
					_tokenizer.pushText(txt);
				} 
				else if (tok.type == Token.Semicolon)
				{
					undoTextPos(pos);
					goto reparseToken;
				}
			}
			break;
		case Token.PPinclude:
			parseInclude();
			_prevDeclEndPos = textPos();
			break;

		case Token.PPdefine:
			parseDefine();
			break;

		case Token.PPifdef:
			parseIfdef(true);
			break;
		case Token.PPifndef:
			parseIfdef(false);
			break;
		case Token.PPif:
			parseIf();
			break;
		case Token.PPelse:
			parseElse();
			break;
		case Token.PPelif:
			parseElif();
			break;
		case Token.PPendif:
			parseEndif();
			break;
		case Token.PPother:
		case Token.PPundef:
			parseOther();
			break;

		case Token.ParenL:
			_parenthesis++;
			break;
		case Token.ParenR:
			if(_parenthesis <= 0)
				throw new Exception("too many closing paranthesis");
			_parenthesis--;

			if(_inRHS > _parenthesis)
				_inRHS = -1;

			if(_parenthesis == 0 && _curFunc != "" && _braces == _funcBraceLevel && _funcBodyStart < 0)
			{
				int pos = textPos();
				_curProto = getTextTail(pos - _funcProtoStart);
				if(_curProto == "(void)")
				{
					undoText(_curProto);
					_curProto = "()";
					appendText(_curProto);
				}
			}
			else if(_parenthesis == 0 && _checkEmptyStatement && nextToken(tok))
			{
				if (tok.type == Token.Semicolon)
				{
					undoText(tok.text);
					appendText("{}");
				}
				_checkEmptyStatement = false;
				goto reparseToken;
			}
			else
				_checkCastNext = true;
			
			if(_toPtrLevel.length > 0 && _parenthesis == _toPtrLevel[$-1])
			{
				appendText(")");
				_toPtrLevel.length = _toPtrLevel.length-1;
			}
			break;

		case Token.Tilde:
			if(_parenthesis == 0 && _curFunc == "")
			{
				// must be destructor declaration
				if (!startFunction())
					goto reparseToken;
			}
			break;

		case Token.Typedef:
			if (parseTypedef())
				goto reparseToken;
			break;

		case Token.Do:
		case Token.Return:
		case Token.Static:
		case Token.Switch:
		case Token.Goto:
		case Token.Break:
		case Token.Continue:
		case Token.Identifier:
			if (!parseIdentifier())
				goto reparseToken;
			break;

		case Token.DoubleColon:
		case Token.Deref:
			undoText(tok.text);
			_curText ~= ".";
			break;

		case Token.Semicolon:
			if(_parenthesis == 0 && _curFunc != "" && _braces == _funcBraceLevel)
				endFunctionDeclaration();
			else if(_braces == _funcBraceLevel)
				_isnaked = false;
			
			foreach(int level; _toPtrLevel)
				insertTextAt(textPos() - 1, ")");
			
			_toPtrLevel.length = 0;
			_prevDeclEndPos = textPos();
			_statementStart = -1;
			_inRHS = -1;
			popTypedefLevel(true);
			break;

		case Token.If:
		case Token.While:
		case Token.For:
			_checkEmptyStatement = true;
			break;
		case Token.Else:
			if(nextToken(tok))
			{
				if (tok.type == Token.Semicolon)
				{
					undoText(tok.text);
					appendText("{}");
				}
				goto reparseToken;
			}
			break;

		case Token.Delete:
			int pos = textPos() - tok.text.length;
			if(nextToken(tok))
			{
				if (tok.type == Token.BracketL)
					if(nextToken(tok) && tok.type == Token.BracketR)
					{
						string txt = getTextTail(textPos() - pos);
						undoTextPos(pos);
						appendText("// ");
						appendText(txt);
						break;
					}
				goto reparseToken;
			}
			break;
			
		case Token.__Asm:
			if (!parseAsm())
				goto reparseToken;
			break;

		case Token.__Declspec:
			int pos = textPos() - tok.text.length;
			if(!nextToken(tok) || tok.type != Token.ParenL || 
			   !nextToken(tok) || tok.type != Token.Identifier || tok.text != "naked" ||
			   !nextToken(tok) || tok.type != Token.ParenR)
			   throw new Exception("__declspec mus not be followed by anything but (neked)");
			_isnaked = true;
			undoTextPos(pos);
			break;

		case Token.__In:
		case Token.__Out:
			if(_parenthesis == 0)
				_inContract = true;
		case Token.__Body:
		case Token.Colon:
			if(_parenthesis == 0 && _curFunc != "" && _braces == _funcBraceLevel)
			{
				if(_funcBodyStart < 0)
					_funcBodyStart = textPos() - tok.text.length - tok.pretext.length;
			}
			break;
		case Token.Comma:
			if(_enumState == EnumState.kInit)
				_enumState = EnumState.kIdentifier;
			if(_parenthesis == 0)
				if (!splitDeclaration())
					goto reparseToken;
			break;

		case Token.BracketL:
			break;
		case Token.BracketR:
			if(_parenthesis == 0)
			{
				if(nextToken(tok) && tok.type != Token.Comma)
					goto reparseToken;
				doSplitDeclaration(false);
				goto reparseToken; // reparse ';'
			}
			break;

		case Token.String:
			if(!parseString())
				goto reparseToken;
			break;
		case Token.Ampersand:
			if(_curFunc != "" && _funcBodyStart < 0)
			{
				// in function prototype
				undoText(tok.text);
				insertRefToFuncArgument();
			}
			break;
		case Token.Assign:
			if(_enumState == EnumState.kIdentifier)
				_enumState = EnumState.kInit;
			else
			{
				_inRHS = _parenthesis;
				string txt = getTextTail(textPos() - _statementStart);
				_levelRHS = count(txt,"["); // number of array dimensions
			}
			break;
		case Token.Asterisk:
			if(!parseAsterisk())
				goto reparseToken;
			break;
		case Token.LessThan:
		case Token.GreaterThan:
		case Token.Number:
		case Token.Other:
		default:
			break;
		}
	}

	void parseDeadCode()
	{
		switch(tok.type)
		{
		case Token.PPifdef:
			parseIfdef(true);
			break;
		case Token.PPifndef:
			parseIfdef(false);
			break;
		case Token.PPif:
			parseIf();
			break;
		case Token.PPelse:
			parseElse();
			break;
		case Token.PPelif:
			if (parseElif())
				return; // do not clear _curText
			break;
		case Token.PPendif:
			parseEndif();
			break;
		default:
			break;
		}
		// @todo this can be a problem if #elif opens a conditional version
		_curText = "";
	}

	void parse(int pass)
	{
		_pass = pass;
		if(_pass == kPassClassPtrToRef)
			return parseClassPtrToRef();

		reinit();

		while(nextToken(tok))
		{
			if (evalVersion())
			{
				parseLiveCode();
				flushText();
			}
			else
				parseDeadCode();
		}
		if(evalVersion())
			flushText();
	}

	void parseClassPtrToRef()
	{
	    return;

		_tokenizer = new Tokenizer(_newText);
		reinit();

		while(nextToken(tok))
		{
			if(tok.type == Token.Identifier)
			{
				if(isClassName(tok.text))
					if(nextToken(tok) && tok.type == Token.Asterisk)
						undoText(tok.text);
			}
		}
		flushText();
	}

	string moduleName(string file)
	{
		string mod = getName(file);
		mod = replace(mod, "/", ".");
		mod = replace(mod, "\\", ".");
		return mod;
	}
	static string[string] std_replace;
	static string[string] dmd_replace;
	static this()
	{
		std_replace["std.assert"] = "";
		std_replace["std.stdlib"] = "std.c.stdlib";
		std_replace["std.stddef"] = "std.c.stddef";
		std_replace["std.limits"] = "";
		std_replace["std.errno"] = "";
		std_replace["std.windows"] = "std.c.windows.windows";
		
		dmd_replace["async"] = "dmd.root.async_c";
	}
	string importName(string mod)
	{
		if(startsWith(mod, "std."))
		{
			if(mod in std_replace)
				mod = std_replace[mod];
		}
		else if(_dmd2d)
		{
			if(mod in dmd_replace)
				mod = dmd_replace[mod];

			foreach(src; _dmd2d.hdrfiles)
			{
				if(baseName(src, ".h") == mod)
				{
					mod = moduleName(src) ~ "_h";
					break;
				}
			}
		}
		return mod;
	}

	void write()
	{
		string oname;
		if(outputName.length == 0)
		{
			string ext = (extension(_file) == ".h" ? "_h.d" : "_c.d");
			oname = getName(_file) ~ ext;
		}
		else if (find(outputName, "=") >= 0)
		{
			int pos = find(outputName, "=");
			string search = outputName[0..pos];
			string replace = outputName[pos+1..$];
			oname = sub(_file, search, replace);
		}
		else
			oname = outputName;

		string hdr = "module " ~ moduleName(oname) ~";\n\n";
		hdr ~= "import dmd2dport;\n";

		foreach(imp; _imports)
		{
			string mod = imp[1..$-1];
			mod = getName(mod); // strip extension
			replace(mod, "/", ".");
			if(startsWith(imp,"<"))
				mod = "std." ~ mod;
			mod = importName(mod);
			if (mod != "")
				hdr ~= "import " ~ mod ~ ";\n";
		}
		hdr ~= "\n";

		string text = patchFileText(oname, _newText, dstpatches);
		std.file.write(oname, hdr ~ text);
	}

	string _file;
	string _text;
	Tokenizer _tokenizer;
	Token tok;

	int _pass;
	bool _ppprocessing;
	int _braces;
	int _parenthesis;
	int _prevDeclEndPos;
	int _statementStart;
	int _funcDeclStart;
	int _funcNameStart;
	int _funcBraceLevel;
	int _funcProtoStart;
	int _funcBodyStart = -1;
	bool _checkCastNext;
	bool _inContract;
	int _inRHS;
	int _levelRHS;
	bool _isnaked;
	bool _checkEmptyStatement;
	int[] _toPtrLevel;

	EnumState _enumState;

	string _curFunc;
	string _curProto;
	string _curText;
	string _newText;
	int[] _typedefLevels;
	int[] _typedefPositions;

	string[] _namespaces;
	int[] _namespaceLevels;

	string[] _structs;
	int[] _structStart;
	int[] _structLevels;

	string[] _versions;
	int[] _evalVersions;

	int[] _externLevels;

	PPDefine[string] _ppdefines;
	string[] _imports;
	string[] _structImports;
	string[] _structDecls;

	DMD2D _dmd2d;
}

///////////////////////////////////////////////////////////////////////

struct PatchData
{
	string file;
	string match;
	string replace;
	bool regexp = true;
};

string patchFileText(string file, string text, ref PatchData[] patches)
{
	string fname = baseName(file);
	for(int i = 0; i < patches.length; i++)
		if (globMatch(fname, patches[i].file))
			if (patches[i].regexp)
				text = sub(text, patches[i].match, patches[i].replace, "g");
			else
				text = replaceToken(text, patches[i].match, patches[i].replace);
	return text;
}

///////////////////////////////////////////////////////////////////////

class DMD2D
{
	string[] hdrfiles;
	string[] srcfiles;
	string[] excludefiles;
	string[string] functions;
	string[string] initializer;
	string[string] enumIdent;
	string[string] typedefs;
	int[string] typedefLines;
	int[string] memberFunctions;
	string[string] prototypes;
	string[string] baseClasses;
	string[][string] derivedClasses;
	bool classPtrToReference;
	Source[] sources;

	bool isClassName(string s)
	{
		if (endsWith(s, "::"))
			s = s[0..$-2];

		if(s == "Scope")
			return true;
		if(s == "Loc")
			return false;

	retry_type:
		//string scp = s ~ "::";
		//if (scp in _dmd2d.memberFunctions)
		//	return true;
		if(s in baseClasses)
			return true;
		if(s in derivedClasses)
			return true;

		if(string* ps = s in typedefs)
		{
			s = *ps;
			goto retry_type;
		}
		return false;
	}

	string getBaseClass(string type)
	{
		if (endsWith(type, "::"))
			type = type[0..$-2];

		if(string* b = type in baseClasses)
			return *b;
		return "";
	}

	void addPrototype(string func, string proto)
	{
		int pos = rfind(func, "::");
		if(pos >= 0)
			func = func[pos + 2 .. $];

		// if there are multiple declarations, prefer the one starting with Loc
		if(string *p = func in prototypes)
			if(startsWith(*p,"(Loc "))
				return;

		prototypes[func] = proto;
	}

	void convertClassPtrToReference()
	{
		string[string] changed;
		foreach(def, type; typedefs)
			if(endsWith(type, "*"))
				changed[def] = type[0..$-1];
		
		foreach(def, type; changed)
			typedefs[def] = strip(type);

		classPtrToReference = true;
	}

	void parseSource(Source src, int pass)
	{
		if (dump && pass == 0)
			std.file.write(src._file ~ ".pass0", src._text);

		if (verbose)
			writefln("pass %d: %s...", pass + 1, src._file);

		try
		{
			src.parse(pass);
			if(dump)
				std.file.write(src._file ~ ".pass" ~ format(pass + 1), src._newText ~ src._curText);
		}
		catch(Exception e)
		{
			string msg = src._file ~ "(" ~ format(src._tokenizer.lineno) ~ "):" ~ e.toString();
			std.file.write(src._file ~ ".dmp", src._newText ~ src._curText);
			throw new Exception(msg);
		}
	}

	void createSource(string file)
	{
		Source src = new Source(this, file);
		sources ~= src;
	}

	void addSource(string file)
	{
		string base = baseName(file);
		foreach(excl; excludefiles)
			if(excl == base)
				return;

		if(extension(file) == ".h")
			hdrfiles ~= file;
		else
			srcfiles ~= file;
	}

	void addSourceByPattern(string file)
	{
		SpanMode mode = SpanMode.shallow;
		if (file[0] == '+')
		{
			mode = SpanMode.depth;
			file = file[1..$];
		}
		string path = dirName(file);
		string pattern = baseName(file);
		foreach (string name; dirEntries(path, mode))
			if (globMatch(baseName(name), pattern))
				addSource(name);
	}

	static void initPatches()
	{
		if (srcpatches.length > 0)
			return;

		if(!simple)
		{
			srcpatches ~= PatchData("cgobj.c",  "#if MARS\r*\nstruct Loc[^#]*#endif", "");
			srcpatches ~= PatchData("list.*",   "static list_t list_alloc", "");
			srcpatches ~= PatchData("list.*",   "\n[ \t]*\\(\\)", "\nstatic list_t list_alloc()");
			srcpatches ~= PatchData("list.*",   "\n[ \t]*\\(char \\*file,int line\\)", "\nstatic list_t list_alloc(char *file,int line)");
			srcpatches ~= PatchData("root.h",   "#define TYPEDEFS", "", false);
			srcpatches ~= PatchData("cc.h",     "#define INITIALIZED_STATIC[^\n]*\n", "");
			srcpatches ~= PatchData("cc.h",     "Symbol *\\*Sl,\\*Sr", "Symbol* Sl,Sr");

			// always declared, but only implemented conditionally
			srcpatches ~= PatchData("cc.h",     " *void print\\(\\)", "#ifdef DEBUG\n$&");
			srcpatches ~= PatchData("cc.h",     " *void print_list\\(\\);", "$&\n#endif");
			srcpatches ~= PatchData("lexer.h",  " *void print\\(\\);", "#ifdef DEBUG\n$&\n#endif");
			srcpatches ~= PatchData("lexer.h",  "unsigned wchar\\(unsigned u\\);", "#if 0\n$&\n#endif");
			srcpatches ~= PatchData("module.h", " *void toCBuffer[^;]*;", "#ifdef _DH\n$&\n#endif");
			srcpatches ~= PatchData("code.h",   " *void print\\(\\);", "#ifdef DEBUG\n$&\n#endif");
			
			// declarations cannot be matched against implementation
			srcpatches ~= PatchData("declaration.h", "AliasDeclaration\\(Loc loc, Identifier \\*ident", "AliasDeclaration(Loc loc, Identifier *id");
			srcpatches ~= PatchData("expression.h", "StringExp\\(Loc loc, void \\*s,", "StringExp(Loc loc, void *string,");

			// declared, but never implemented
			//srcpatches ~= PatchData("async.*",  "void dispose\\(AsyncRead \\*\\)", "void dispose(AsyncRead *aw)");
			srcpatches ~= PatchData("cc.h",     "int needThis", "// $&");
			srcpatches ~= PatchData("html.h",   "static int namedEntity", "// $&");
			srcpatches ~= PatchData("token.h",  "void setSymbol", "// $&");
			srcpatches ~= PatchData("token.h",  "void print", "// $&");
			srcpatches ~= PatchData("parser.h", "void print", "// $&");
			srcpatches ~= PatchData("cond.h",   "static void addPredefinedGlobalIdent[^;]*;[ \n]*Debug", "// $&");
			srcpatches ~= PatchData("declaration.h", "void varArgs", "// $&");
			srcpatches ~= PatchData("mtype.h",  "int isbit", "// $&");
			srcpatches ~= PatchData("expression.h", "struct BinAssignExp[^\\}]*\\};", "/* $& */");
			srcpatches ~= PatchData("lstring.h", "Lstring \\*clone", "// $&");
			srcpatches ~= PatchData("root.h",   "char \\*extractString", "// $&");
			srcpatches ~= PatchData("scope.h",  "Scope\\(Module", "// $&");
		}
		else
		{
			// declarations cannot be matched against implementation
			srcpatches ~= PatchData("*.*", "AliasDeclaration\\(Loc loc, Identifier \\*ident", "AliasDeclaration(Loc loc, Identifier *id");
			srcpatches ~= PatchData("*.*", "StringExp\\(Loc loc, void \\*s,", "StringExp(Loc loc, void *string,");
			srcpatches ~= PatchData("*.*", "void varArgs", "// $&");
		}

		// keywords
		srcpatches ~= PatchData("*.*",      "version",            "d2d_version", false);
		srcpatches ~= PatchData("*.*",      "ref",                "d2d_ref",     false);
		srcpatches ~= PatchData("*.*",      "align",              "d2d_align",   false);
		srcpatches ~= PatchData("*.*",      "dchar",              "d2d_dchar",   false);
		srcpatches ~= PatchData("*.*",      "body",               "d2d_body",    false);
		srcpatches ~= PatchData("*.*",      "module",             "d2d_module",  false);
		srcpatches ~= PatchData("*.*",      "scope",              "d2d_scope",   false);
		srcpatches ~= PatchData("*.*",      "pragma",             "d2d_pragma",  false);
		srcpatches ~= PatchData("*.*",      "wchar",              "d2d_wchar",   false);
		srcpatches ~= PatchData("*.*",      "real",               "d2d_real",    false);
		srcpatches ~= PatchData("*.*",      "byte",               "d2d_byte",    false);
		srcpatches ~= PatchData("*.*",      "cast",               "d2d_cast",    false);
		srcpatches ~= PatchData("*.*",      "delegate",           "d2d_delegate", false);
		srcpatches ~= PatchData("*.*",      "alias",              "d2d_alias",   false);
		srcpatches ~= PatchData("*.*",      "is",                 "d2d_is",      false);
		srcpatches ~= PatchData("*.*",      "in",                 "d2d_in",      false);
		srcpatches ~= PatchData("*.*",      "out",                "d2d_out",     false);
		srcpatches ~= PatchData("*.*",      "invariant",          "d2d_invariant", false);
		srcpatches ~= PatchData("*.*",      "final",              "d2d_final",   false);
		srcpatches ~= PatchData("*.*",      "inout",              "d2d_inout",   false);
		srcpatches ~= PatchData("*.*",      "override",           "d2d_override", false);
		srcpatches ~= PatchData("*.*",      "alignof",            "d2d_alignof", false);
		srcpatches ~= PatchData("*.*",      "mangleof",           "d2d_mangleof", false);
		srcpatches ~= PatchData("*.*",      "init",               "d2d_init",    false);

		// almost keywords
		srcpatches ~= PatchData("*.*",      "Object",             "d2d_Object",   false);
		srcpatches ~= PatchData("*.*",      "TypeInfo",           "d2d_TypeInfo", false);
		srcpatches ~= PatchData("*.*",      "toString",           "d2d_toString", false);
		srcpatches ~= PatchData("*.*",      "main",               "d2d_main",     false);
		srcpatches ~= PatchData("*.*",      "string",             "d2d_string",   false);

		srcpatches ~= PatchData("*.*",      "param_t",            "PARAM",       false);
		srcpatches ~= PatchData("*.*",      "hash_t",             "d2d_hash_t",  false);
		srcpatches ~= PatchData("*.*",      "File",               "d2d_File",    false);
		srcpatches ~= PatchData("*.*",      "STATIC",             "private",     false);
		srcpatches ~= PatchData("*.*",      "CEXTERN",            "extern",      false);
		srcpatches ~= PatchData("*.*",      "__cdecl",            "",            false);
		srcpatches ~= PatchData("*.*",      "__stdcall",          "",            false);
		srcpatches ~= PatchData("*.*",      "__pascal",           "",            false);
		srcpatches ~= PatchData("*.*",      "__try",              "try",         false);
		srcpatches ~= PatchData("*.*",      "__except",           "catch(Exception e) //", false);
		srcpatches ~= PatchData("*.*",      "__inline",           "",            false);
		srcpatches ~= PatchData("*.*",      "inline",             "",            false);
		srcpatches ~= PatchData("*.*",      "register",           "",            false);
		srcpatches ~= PatchData("*.*",      "volatile",           "/*volatile*/", false);
		srcpatches ~= PatchData("*.*",      "NULL",               "null",        false);
		srcpatches ~= PatchData("*.*",      "(((( 0 ))))",        "null",        false);

		// std types
		srcpatches ~= PatchData("*.*",      "unsigned long long", "ulong",  false);
		srcpatches ~= PatchData("*.*",      "unsigned long int",  "ulong",  false);
		srcpatches ~= PatchData("*.*",      "unsigned long",      "uint",   false);
		srcpatches ~= PatchData("*.*",      "unsigned int",       "uint",   false);
		srcpatches ~= PatchData("*.*",      "unsigned short",     "ushort", false);
		srcpatches ~= PatchData("*.*",      "unsigned char",      "ubyte",  false);
		srcpatches ~= PatchData("*.*",      "unsigned",           "uint",   false);
		srcpatches ~= PatchData("*.*",      "signed long",        "int",    false);
		srcpatches ~= PatchData("*.*",      "signed int",         "int",    false);
		srcpatches ~= PatchData("*.*",      "signed char",        "char",   false);
		srcpatches ~= PatchData("*.*",      "_Complex float",     "cfloat",  false);
		srcpatches ~= PatchData("*.*",      "_Complex double",    "cdouble",  false);
		srcpatches ~= PatchData("*.*",      "_Complex long double", "creal",  false);
		srcpatches ~= PatchData("*.*",      "long double",        "real",   false);
		srcpatches ~= PatchData("*.*",      "long long",          "long_long", false);
		srcpatches ~= PatchData("*.*",      "long",               "int",    false);
		srcpatches ~= PatchData("*.*",      "long_long",          "long",   false);

		srcpatches ~= PatchData("*.*",      "((const float _Imaginary)__imaginary)", "1.0i",   false);

		if (!simple)
		{
			srcpatches ~= PatchData("*.*",      "TARGET_structBLOCK",  "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structFUNC_S", "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structSTRUCT", "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structPARAM",  "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structBLKLST", "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structELEM",   "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_structSYMBOL", "", false);
			srcpatches ~= PatchData("*.*",      "TARGET_INLINEFUNC_NAMES", "", false);

			srcpatches ~= PatchData("cc.h",     "#ifndef private",    "#if 0",       false);
			srcpatches ~= PatchData("cc.h",     "#ifndef extern",     "#if 0",       false);
		}

		//srcpatches ~= PatchData("*.*",      "\"written by Walter Bright\"", "\"written by Walter Bright\";", false);
		//srcpatches ~= PatchData("*.*",      "\n([ \t]*);",                  "\n$1{}"); // empty statements after if/for/while
		srcpatches ~= PatchData("*.*",      "sizeof *(\\([^\\)]*\\))",      "$1.sizeof"); // sizeof(data) -> (data).sizeof
		srcpatches ~= PatchData("*.*",      "\\(([0-9A-Za-z_]*)\\[0\\]\\).sizeof", "(*$1).sizeof"); // (data[0]).sizeof -> (*data).sizeof
		srcpatches ~= PatchData("*.*",      "static_cast *\\<([^\\>]*)\\>", "($1)"); // "cast" added later
		// number postfix LL -> L
		srcpatches ~= PatchData("*.*",      "([0-9][xb]?[0-9A-Fa-f]*)[uU][lL][lL]", "$1UL");
		srcpatches ~= PatchData("*.*",      "([0-9][xb]?[0-9A-Fa-f]*)[lL][lL]", "$1L");
		srcpatches ~= PatchData("*.*",      "\\(([0-9A-Za-z_][0-9A-Za-z_]*)\\)([\\+-][\\+-])", "$1$2"); // (i)++ -> i++
		srcpatches ~= PatchData("*.*",      "\\(([0-9A-Za-z_][0-9A-Za-z_]*)\\)\\.", "$1."); // (i). -> i.
		srcpatches ~= PatchData("*.*",      "'([A-Z_])([A-Z_])'", "(('$1' << 8)|'$2')"); // 'S_'
		
		//srcpatches ~= PatchData("*.*",      "\n([{ \t][ t]*)([^\\*,;\\(]*)(\\*[^,;\\(]), *\\*", "\n$1$2$3;$2*");

		srcpatches ~= PatchData("*.*",  "operator new[]",    "opNewArray", false);
		srcpatches ~= PatchData("*.*",  "operator new",      "opNew", false);
		srcpatches ~= PatchData("*.*",  "operator delete[]", "opDeleteArray", false);
		srcpatches ~= PatchData("*.*",  "operator delete",   "opDelete", false);

		// cd_t function forward declarations that look like vars
		srcpatches ~= PatchData("*.*",  "cd_t[\t ]+[A-Za-z_][0-9A-Za-z_]*;", "", true);
		// Tident used as enum value and struct member
		srcpatches ~= PatchData("*.*",  "([\\>\\*])Tident", "$1Tidentifier", true);

		///////////////////////////////////////////////////////
		// output patches
		dstpatches ~= PatchData("*.*",      "(PPTRNTAB0)",        "cast(PPTRNTAB0)", false);
		// const char* -> string
		if (addStringPtr)
		{
			dstpatches ~= PatchData("*.*",      "const char ([A-Za-z_][0-9A-Za-z_]*)\\[\\]",  "const char* $1", true);
			dstpatches ~= PatchData("*.*",      "([^0-9A-Za-z_])char ([A-Za-z_][0-9A-Za-z_]*)\\[\\]",  "$1const char* $2", true);

			dstpatches ~= PatchData("*.*",      "const char* tysize =",  "const(byte) tysize[] =", false);
		}
		else
		{
			dstpatches ~= PatchData("*.*",      "const char ([A-Za-z_][0-9A-Za-z_]*)\\[\\]",  "string $1", true);
			dstpatches ~= PatchData("*.*",      "([^0-9A-Za-z_])char ([A-Za-z_][0-9A-Za-z_]*)\\[\\]",  "$1string $2", true);

			dstpatches ~= PatchData("*.*",      "string tysize =",    "const(byte) tysize[] =", false);
		}
		//dstpatches ~= PatchData("*.*",      "const ([A-Za-z_][0-9A-Za-z_]*)",  "const($1)", true);
		//dstpatches ~= PatchData("*.*",      "const char",         "const(char)",   false);
		dstpatches ~= PatchData("*.*",      "\\(uint\\) *-1",     "cast(uint)-1", true);
		dstpatches ~= PatchData("*.*",      "\\(ubyte\\)\\*q",    "cast(ubyte)*q", true);
		dstpatches ~= PatchData("*.*",      "assnod = (elem **)", "assnod = cast(elem **)", false);

		dstpatches ~= PatchData("*.*",      "const \\(char\\)(.*\\[FL\\.FLMAX\\])", "const(byte) $1", true);
		dstpatches ~= PatchData("*.*",      "const (char) regtorm32", "const(byte) regtorm32", false);
		dstpatches ~= PatchData("*.*",      "char regtorm",           "const(byte) regtorm", false);
		dstpatches ~= PatchData("*.*",      "const (char) oprev", "const(byte) oprev", false);

		// fixup LString
		dstpatches ~= PatchData("*.*",      "d2d_dchar d2d_string[]", "d2d_dchar d2d_string[0]", false);
		dstpatches ~= PatchData("*.*",      "Lstring zero =  { 0, \"\" }", "Lstring zero", false); // ;static this() { zero = alloc(0); }
		dstpatches ~= PatchData("*.*",      "d2d_string + length", "d2d_string.ptr + length", false);
		dstpatches ~= PatchData("*.*",      "d2d_string + start", "d2d_string.ptr + start", false);

		// add zero to Loc
		dstpatches ~= PatchData("*.*",      "this(Module *mod, uint linnum)", "static Loc zero;\n\n    this(Module *mod, uint linnum)", false);
		dstpatches ~= PatchData("*.*",      "loc = 0", "loc = Loc.zero", false);

		// add Scope.this(Scope sc)
		dstpatches ~= PatchData("*.*",      "this(Module *d2d_module)", "this(Scope sc) { memcpy(&this, &sc, sizeof(this)); }\n    this(Module *d2d_module)", false);

		// pointer comparison to this
		dstpatches ~= PatchData("*.*",      "&this ==", "&this is", false);
		dstpatches ~= PatchData("*.*",      "&this !=", "&this !is", false);
		dstpatches ~= PatchData("*.*",      "== &this", "is &this", false);
		dstpatches ~= PatchData("*.*",      "!= &this", "!is &this", false);
		

		dstpatches ~= PatchData("*.*",      "__in",               "in", false);
		dstpatches ~= PatchData("*.*",      "__out",              "out", false);
		dstpatches ~= PatchData("*.*",      "__body",             "body", false);
		dstpatches ~= PatchData("*.*",      "typedef",            "alias", false);

		structTypes["Keyword"] = "struct";
		structTypes["NameId"] = "struct";
	}

	void initDefines()
	{
		if(!simple)
		{
			excludefiles ~= "idgen.c";
			excludefiles ~= "impcnvgen.c";
			excludefiles ~= "dwarf.c";
			excludefiles ~= "dwarf.h";
			excludefiles ~= "libelf.c";
			excludefiles ~= "libmach.c";
			excludefiles ~= "mem.c";
			excludefiles ~= "mem.h";
			excludefiles ~= "toelfdebug.c";
			excludefiles ~= "complex_t.h";
			excludefiles ~= "md5.c";
			excludefiles ~= "objfile.h";
			excludefiles ~= "async.h"; // duplicates definition in async.c
		}

		if(!simple)
		{
			defines["DMDV1"]  = "0";
			defines["DMDV2"]  = "1";

			defines["TARGET_WINDOS"]  = "1";
			defines["TARGET_LINUX"]   = "0";
			defines["TARGET_OSX"]     = "0";
			defines["TARGET_MAC"]     = "0";
			defines["TARGET_FREEBSD"] = "0";
			defines["TARGET_NET"]     = "0";
			defines["TARGET_68K"]     = "0";
			defines["DOS386"]         = "0";
			defines["ASM86"]          = "0";
			defines["_WIN32"]         = "1";
			defines["TX86"]           = "1";
			defines["MARS"]           = "1";
			defines["OMFOBJ"]         = "1";
			defines["ELFOBJ"]         = "0";
			defines["MACHOBJ"]        = "0";
			defines["NEWMANGLE"]      = "1";
			defines["NTEXCEPTIONS"]   = "2";
			defines["MEM_DEBUG"]      = "0";
			defines["WINDOWS_SEH"]    = "0";
			defines["__INTSIZE"]      = "4";
			defines["__I86__"]        = "1";

			defines["SPP"]           = "0";
			defines["CPP"]           = "0";
			defines["HTOD"]          = "0";

			defines["M_UNICODE"]     = "0";
			defines["MCBS"]          = "0";
			defines["UTF8"]          = "1";

			defines["ARG_TRUE"]      = "";
			defines["ARG_FALSE"]     = "";

			//defines["TX86 && __INTSIZE == 4 && __SC__"] = "0"; // skip asm in cgen.c
			//defines["!DEBUG && TX86 && __INTSIZE == 4 && !defined(_MSC_VER)"] = "0"; // skip asm in cgobj.c
			defines["defined (__SVR4) && defined (__sun)"] = "0";

			undefines ~= "linux";
			undefines ~= "__APPLE__";
			undefines ~= "__POWERPC";
			undefines ~= "__FreeBSD__";
			undefines ~= "__SC__";
			undefines ~= "__DMC__";
			undefines ~= "__GNUC__";
			undefines ~= "_MSC_VER";
			undefines ~= "DEBUG";
			undefines ~= "SCPP";
			undefines ~= "SPP";
			undefines ~= "_DH";
			undefines ~= "__cplusplus"; // avoid extern "C"
			undefines ~= "IN_GCC";

			undefines ~= "UNKNOWN";

			expands ~= "X";
			expands ~= "BIN_ASSIGN_INTERPRET";
			expands ~= "BIN_INTERPRET2";
			expands ~= "BIN_INTERPRET";
			expands ~= "UNA_INTERPRET";
		}
	}

	int main(string[] argv)
	{
		getopt(argv, 
			"verbose|v", &verbose,
			"simple|s", &simple,
			"define|D", &defines,
			"output|o", &outputName,
			"undefine|U", &undefines);

		// addSource("dmd/root/rmem.h");
		initPatches();
		initDefines();

		foreach(string file; argv[1..$])
		{
			if (find(file, '*') >= 0 || find(file, '?') >= 0)
 				addSourceByPattern(file);
			else
				addSource(file);
		}

		foreach(string file; srcfiles)
			createSource(file);

		foreach(string file; hdrfiles)
			createSource(file);

		for(int pass = 0; pass < kNumPasses; pass++)
		{
			foreach(src; sources)
				parseSource(src, pass);
		}

		foreach(src; sources)
			src.write();

		return 0;
	}
}

///////////////////////////////////////////////////////////////////////

int main(string[] argv)
{
	DMD2D d2d = new DMD2D;
	return d2d.main(argv);
}

///////////////////////////////////////////////////////////////////////

unittest
{
	string txt = 
		"// comment\n" ~
		"#ifdef IN_GCC\n" ~
		"#include \"d-dmd-gcc.h\"\n" ~
		"#endif\n" ~
		"/* multi line\n" ~
		" comment */\n" ~
		"v_arguments = NULL;\n" ~
		"#if IN_GCC\n" ~
		"#endif\n";

	Tokenizer tokenizer = new Tokenizer(txt);
	Token tok = new Token;
	assert(tokenizer.next(tok) && tok.type == Token.Comment);
	assert(tokenizer.next(tok) && tok.type == Token.PPifdef);
	assert(tokenizer.next(tok) && tok.type == Token.Identifier);
	assert(tokenizer.next(tok) && tok.type == Token.PPinclude);
	assert(tokenizer.next(tok) && tok.type == Token.String);
	assert(tokenizer.next(tok) && tok.type == Token.PPendif);
	assert(tokenizer.next(tok) && tok.type == Token.Comment);
	assert(tokenizer.next(tok) && tok.type == Token.Identifier);
	assert(tokenizer.next(tok) && tok.type == Token.Assign);
	assert(tokenizer.next(tok) && tok.type == Token.Identifier);
	assert(tokenizer.next(tok) && tok.type == Token.Semicolon);
	assert(tokenizer.next(tok) && tok.type == Token.PPif);
	assert(tokenizer.next(tok) && tok.type == Token.Identifier);
	assert(tokenizer.next(tok) && tok.type == Token.PPendif);
}

unittest
{
	string txt = 
		"#include \"d-dmd-gcc.h\"\n" ~
		"#include <stdio.h>\n" ~
		"namespace dmd {\n" ~
		"int classname::function()\n"
		"{\n" ~
		"   if(1) {\n" ~
		"      return 3;\n" ~
		"   }\n" ~
		"}\n" ~
		"}\n";

	DMD2D dmd2d = new DMD2D;
	Source src = new Source(dmd2d, "", txt);
	src.parse(0);
	assert(src._imports.length == 2);
	assert(src._imports[0] == "\"d-dmd-gcc.h\"");
	assert(src._imports[1] == "<stdio.h>");
}

void testconversion(string txt, string res)
{
	DMD2D.initPatches();

	DMD2D dmd2d = new DMD2D;
	Source src = new Source(dmd2d, "test.cc", txt);
	src.parse(0);
	src.parse(1);
	src.parse(2);
	string ntxt = patchFileText(src._file, src._newText, dstpatches);
	string stxt = strip(ntxt);
	assert(stxt == res);
}

unittest
{
	string txt = 
		"#if 1\n" ~
		"  a\n" ~
		"#else\n" ~
		"  b\n" ~
		"#endif\n" ;
	testconversion(txt, "a");
}

unittest
{
	string txt = 
		"int foo() {\n" ~
		"  if(0) print();\n" ~
		"}\n";
	testconversion(txt, strip(txt));
}

unittest
{
	string txt = "int u,v,**x,*y,*z; // comment\n"
	           ~ "int *t1 = 0, // comment 1\n"
	           ~ " *t2 = 0; // comment 2\n";
	string res = "int u; int v; int **x; int *y; int *z; // comment\n"
	           ~ "int *t1 = 0; int  // comment 1\n"
	           ~ " *t2 = 0; // comment 2";
	testconversion(txt, res);
}

unittest
{
	string txt = "int foo(int,int), bar(int);";
	string res = "int foo(int,int); int  bar(int);";
	testconversion(txt, res);
}

unittest
{
	string txt = "int foo[],bar[MAX], car;";
	string res = "int foo[]; int bar[MAX]; int  car;";
	//testconversion(txt, res);
}

unittest
{
	string txt = "real_t toImaginary() { return (real_t) 0; }";
	string res = "real_t toImaginary() { return cast(real_t) 0; }";
	testconversion(txt, res);
}

unittest
{
	string txt = "int foo();\n"
	             "cd_t cfn;\n";
	string res = "";
	testconversion(txt, res);
}

unittest
{
	string txt = "extern {\n"
				 "code *code_calloc(void);\n"
				 "}\n";
	string res = "";
	testconversion(txt, res);
}

unittest
{
	string txt = "const int foo(const char ch) { return 0; }\n";
	string res = "const (int) foo(const (char) ch) { return 0; }";
	testconversion(txt, res);
}

unittest
{
	string txt = "enum Enum { kEnum = 4 };\n"
	             "int arr[kEnum];\n";
	string res = "enum Enum { kEnum = 4 };\n"
	             "int arr[Enum.kEnum];";
	testconversion(txt, res);
}

unittest
{
	string txt = "/**/ char s[] = \"s\";\n"
				 "int foo(xchar ch[]) {}";
	string res = "/**/ string s = \"s\";\n"
				 "int foo(xchar ch[]) {}";
	string resptr = "/**/ const char* s = \"s\".ptr;\n"
				 "int foo(xchar ch[]) {}";
	
	testconversion(txt, addStringPtr ? resptr : res);
}
