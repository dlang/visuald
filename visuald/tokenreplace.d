// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details
///////////////////////////////////////////////////////////////////////
//
// replace a series of tokens
//
// special items in search string (NAME can be any alpha numeric identifier):
//   $_numNAME        - any integer literal
//   $_identNAME      - any identifier (no keywords)
//   $_dotidentNAME   - any identifier.identifier pair
//   $_exprNAME       - any sequence of brace matched tokens terminated by closing bracket or ";"
//   $_notNAME        - any token not matching the following token 
//   $_optNAME        - the following token or nothing
//   $NAME            - any sequence of tokens greedily stopped by the following token
//   token$NAME       - any token starting with "token"
//
// special items in the replacement string
//   any $-names used in the replacement string
//   $*               - the full matched string
//
///////////////////////////////////////////////////////////////////////

module visuald.tokenreplace;

import vdc.lexer;

import c2d.dlist;

import std.string;
import std.ctype;
import std.conv;

alias wstring _string;

///////////////////////////////////////////////////////////////////////
private void throwException(int line, _string msg)
{
	if(line > 0)
		throw new Exception(format("(%d):", line) ~ to!string(msg));
	throw new Exception(to!string(msg));
}

///////////////////////////////////////////////////////////////////////
class Token
{
	enum Comment = TOK_Comment;
	enum Newline = TOK_Comment;
	enum Identifier = TOK_Identifier;
	enum Number = TOK_IntegerLiteral;
	enum Dot = TOK_dot;
	enum EOF = TOK_EOF;
	enum ParenL = TOK_lparen;
	enum ParenR = TOK_rparen;
	enum BraceL = TOK_lcurly;
	enum BraceR = TOK_rcurly;
	enum BracketL = TOK_lbracket;
	enum BracketR = TOK_rbracket;
	
	static bool isPPToken(int) { return false; }

	bool isOpeningBracket() { return type == ParenL || type == BraceL || type == BracketL; }
	bool isClosingBracket() { return type == ParenR || type == BraceR || type == BracketR; }
	
	int type;
	bool replaced;
	int lineno, column; // token pos and end can be calculated from pretext/text
	_string text;
	_string pretext;
}

alias DList!(Token) TokenList;
alias DListIterator!(Token) TokenIterator;

struct TokenRange
{
	TokenIterator start;
	TokenIterator end;
}

struct SubMatch
{
	_string ident;
	TokenIterator start;
	TokenIterator end;
}

struct ReplaceRange
{
	// offsets into old and new _string
	int startlineno;
	int startcolumn;
	int endlineno;
	int endcolumn;
	_string replacementText;
}

struct ReplaceOptions
{
	bool matchCase      = true;
	bool matchBrackets  = true;
	bool keepCase       = true;
	bool includePretext = false;
	bool findOnly       = false;
	bool findMultiple   = false;
}

//////////////////////////////////////////////////////////////////////////////
__gshared Lexer trLex;

shared static this()
{
	trLex.mAllowDollarInIdentifiers = true;
}

//////////////////////////////////////////////////////////////////////////////
void advanceTextPos(_string text, ref int lineno, ref int column)
{
	for( ; ; )
	{
		int pos = indexOf(text, '\n');
		if(pos < 0)
			break;
		lineno++;
		column = 0;
		text = text[pos+1 .. $];
	}
	column += text.length;
}

//////////////////////////////////////////////////////////////////////////////
Token createToken(_string pretext, _string text, int type, int lineno, int column)
{
	Token tok = new Token();
	tok.pretext = pretext;
	tok.text = text;
	tok.type = type;
	tok.lineno = lineno;
	tok.column = column;
	return tok;
}

Token createToken(Token tok)
{
	Token ntok = new Token();
	ntok.pretext = tok.pretext;
	ntok.text = tok.text;
	ntok.type = tok.type;
	ntok.lineno = tok.lineno;
	ntok.column = tok.column;
	return ntok;
}

bool isCommentToken(Token tok, bool checkPP = true)
{
	return tok.type == Token.Comment || tok.type == Token.Newline || (checkPP && Token.isPPToken(tok.type));
}

void skipComments(ref TokenIterator tokIt, bool skipPP = true)
{
	while (!tokIt.atEnd() && isCommentToken(*tokIt, skipPP))
		tokIt.advance();
}

void nextToken(ref TokenIterator tokIt, bool skipPP = true)
{
	tokIt.advance();
	skipComments(tokIt, skipPP);
}

_string tokensToIdentifier(TokenIterator start, TokenIterator end)
{
	_string ident;
	while(!start.atEnd() && start != end)
	{
		if(ident.length > 0 && start.text.length > 0)
			if(isalnum(ident[$-1]) && isalnum(start.text[0]))
				ident ~= " ";
		ident ~= start.text;
		++start;
	}
	return ident;
}

//////////////////////////////////////////////////////////////////////////////
TokenList copyTokenList(TokenIterator start, TokenIterator end, bool cloneTokens = true)
{
	TokenList tokenList = new TokenList;
	for(TokenIterator it = start; it != end; ++it)
	{
		Token tok = cloneTokens ? createToken(*it) : *it;
		tokenList.append(tok);
	}
	return tokenList;
}

TokenList copyTokenList(TokenRange range, bool cloneTokens = true)
{
	return copyTokenList(range.start, range.end, cloneTokens);
}

TokenList copyTokenList(TokenList tokenList, bool cloneTokens = true)
{
	return copyTokenList(tokenList.begin(), tokenList.end(), cloneTokens);
}

TokenIterator insertTokenList(TokenIterator insBefore, TokenList tokenList)
{
	if(tokenList.empty())
		return insBefore;
	TokenIterator endit = tokenList.end() - 1;
	if(endit.type == Token.EOF && !insBefore.atEnd())
	{
		insBefore.pretext = endit.pretext ~ insBefore.pretext;
		endit.erase;
	}
	return insBefore.insertListBefore(tokenList);
}

_string tokenListToString(TokenIterator start, TokenIterator end, bool checkSpaceBetweenIdentifiers = false,
			 bool normalizePreText = false)
{
	_string text;
	_string prevtext;
	for(TokenIterator tokIt = start; tokIt != end; ++tokIt)
	{
		Token tok = *tokIt;
		_string txt = normalizePreText ? tok.text : tok.pretext ~ tok.text;
		if(checkSpaceBetweenIdentifiers || normalizePreText)
		{
			if (prevtext == "__")
				txt = tok.text;
			else if (tok.text == "__")
				txt = "";
			else if (txt.length && prevtext.length)
			{
				dchar prevch = prevtext[$-1];
				dchar ch = txt[0];
				if((isalnum(ch) || ch == '_') && (isalnum(prevch) || prevch == '_'))
					txt = " " ~ txt;
			}
			prevtext = tok.text;
		}
		text ~= txt;
	}
	return text;
}

void markReplaceTokenList(TokenIterator start, TokenIterator end, bool replaced = true)
{
	for(TokenIterator it = start; it != end; ++it)
		it.replaced = replaced;
}

void markReplaceTokenList(TokenList tokenList, bool replaced = true)
{
	markReplaceTokenList(tokenList.begin(), tokenList.end(), replaced);
}

_string tokenListToString(TokenList tokenList, bool checkSpaceBetweenIdentifiers = false)
{
	return tokenListToString(tokenList.begin(), tokenList.end(), checkSpaceBetweenIdentifiers);
}

bool compareTokenList(TokenIterator start1, TokenIterator end1, TokenIterator start2, TokenIterator end2)
{
	TokenIterator it1 = start1;
	TokenIterator it2 = start2;
	for( ; it1 != end1 && it2 != end2; ++it1, ++it2)
		if(it1.text != it2.text)
			return false;

	return it1 == end1 && it2 == end2;
}

//////////////////////////////////////////////////////////////////////////////
// iterator on token after closing bracket
bool advanceToClosingBracket(ref TokenIterator it, TokenIterator stopIt)
{
	TokenIterator prevIt = it; // for debugging
	int lineno = it.lineno;
	int open = it.type;
	int close;
	switch(open)
	{
	case Token.ParenL:
		close = Token.ParenR;
		break;
	case Token.BraceL:
		close = Token.BraceR;
		break;
	case Token.BracketL:
		close = Token.BracketR;
		break;
	default:
		throwException(lineno, "opening bracket expected instead of " ~ it.text);
	}

	int level = 1;
	++it;
	while (level > 0)
	{
		if(it == stopIt)
			return false;
		if(it.atEnd())
			throwException(lineno, "end of file while looking for closing bracket");
		if(it.type == open)
			level++;
		else if(it.type == close)
			level--;
		++it;
	}
	return true;
}

bool advanceToClosingBracket(ref TokenIterator it)
{
	TokenIterator noStop;
	return advanceToClosingBracket(it, noStop);
}

// iterator on token with opening bracket
bool retreatToOpeningBracket(ref TokenIterator it, TokenIterator stopIt)
{
	int lineno = it.lineno;
	int open;
	int close = it.type;
	switch(close)
	{
	case Token.ParenR:
		open = Token.ParenL;
		break;
	case Token.BraceR:
		open = Token.BraceL;
		break;
	case Token.BracketR:
		open = Token.BracketL;
		break;
	default:
		throwException(lineno, "closing bracket expected instead of " ~ it.text);
	}

	int level = 1;
	while (level > 0)
	{
		--it;
		if(it == stopIt)
			return false;
		if(it.atEnd())
			throwException(lineno, "beginnig of file while looking for opening bracket");
		if(it.type == close)
			level++;
		else if(it.type == open)
			level--;
	}
	return true;
}

bool retreatToOpeningBracket(ref TokenIterator it)
{
	TokenIterator noStop;
	return retreatToOpeningBracket(it, noStop);
}

//////////////////////////////////////////////////////////////////////////////
static void scanAny(TL)(ref TL tokenList, _string text, int lineno = 1, int column = 0, bool combinePP = true)
{
	uint lastTokEnd = 0;
	int state = 0;
	int prelineno = lineno;
	int precolumn = column;
	
	void appendToken(Token tok)
	{
		static if(is(TL == Token[]))
			tokenList ~= tok;
		else static if(is(TL == _string[]))
			tokenList ~= tok.text;
		else
			tokenList.append(tok);
	}
	
	for(uint pos = 0; pos < text.length; )
	{
		int tokid;
		uint prevpos = pos;
		trLex.scan(state, text, pos, tokid);

		_string txt = text[prevpos .. pos];
		advanceTextPos(txt, lineno, column); 

		if(tokid != TOK_Space && tokid != TOK_Comment)
		{
			_string pretext = text[lastTokEnd .. prevpos];
			lastTokEnd = pos;
			Token tok = createToken(pretext, txt, tokid, prelineno, precolumn);
			appendToken(tok);

			prelineno = lineno;
			precolumn = column;
		}
	}
	if(lastTokEnd < text.length)
	{
		_string pretext = text[lastTokEnd .. $];
		Token tok = createToken(pretext, text[$ .. $], TOK_EOF, prelineno, precolumn);
		appendToken(tok);
	}
}

TokenList scanText(_string text, int lineno = 1, int column = 0, bool combinePP = true)
{
	TokenList tokenList = new TokenList;
	scanAny(tokenList, text, lineno, column, combinePP);
	return tokenList;
}

void scanTextArray(TYPE)(ref TYPE[] tokens, _string text, int lineno = 1, int column = 0, bool combinePP = true)
{
	scanAny(tokens, text, lineno, column, combinePP);

	static if(is(TYPE == _string))
	{
		while(tokens.length > 0 && tokens[$-1].length == 0)
			tokens = tokens[0..$-1];
	}
	else
	{
		while(tokens.length > 0 && tokens[$-1].text.length == 0)
			tokens = tokens[0..$-1];
	}
}

///////////////////////////////////////////////////////////////////////
int findSubmatch(ref SubMatch[] submatch, _string ident)
{
	for(int i = 0; i < submatch.length; i++)
		if(submatch[i].ident == ident)
			return i;
	return -1;
}

///////////////////////////////////////////////////////////////////////
bool findTokenSequence(TokenIterator it, _string[] search, 
					   bool checkBracketsSearch, bool checkBracketsMatch, bool caseSensitive,
                       _string stopText, ref TokenRange match, ref SubMatch[] submatch)
{
	if(search.length == 0)
	{
		match.start = it;
		match.end = it;
		return true;
	}

	void addSubmatch(_string search, TokenIterator start, TokenIterator end)
	{
		SubMatch smatch;
		smatch.ident = search;
		smatch.start = start;
		smatch.end = end;
		submatch ~= smatch;
	}

	bool strEqual(_string s1, _string s2)
	{
		if(caseSensitive)
			return s1 == s2;
		return icmp(s1, s2) == 0;
	}
	
	bool compareTokens(TokenIterator start, TokenIterator end, ref TokenIterator it)
	{
		for(TokenIterator sit = start; !sit.atEnd() && sit != end; ++sit)
		{
			_string sittext = strip(sit.text);
			if(sittext.length == 0)
				continue;
			while(!it.atEnd() && strip(it.text).length == 0)
				++it;
			if(it.atEnd())
				return false;
			if(!strEqual(strip(it.text), sittext))
				return false;
			++it;
		}
		return true;
	}
	bool compareSubmatch(ref SubMatch sm, _string txt)
	{
		_string s = tokenListToString(sm.start, sm.end);
		return strEqual(strip(s), strip(txt));
	}

	int p = 0;
	while(p < search.length && search[p].length == 0)
		p++;
	if(p >= search.length)
		return false;

	int prevsubmatchLength = submatch.length;

	while(!it.atEnd() && (stopText.length == 0 || !strEqual(it.text, stopText) 
	                                           || strEqual(search[p], stopText)))
	{
		bool dollar = indexOf(search[p], '$') >= 0;
		if(strEqual(strip(it.text), search[p]) || dollar)
		{
			TokenIterator mit = it + (dollar ? 0 : 1);
			int i = p + (dollar ? 0 : 1);
			while(i < search.length && search[i].length == 0)
				i++;
			while(!mit.atEnd() && i < search.length)
			{
				_string mittext = strip(mit.text);
				if(mittext.length == 0)
				{
					++mit;
					continue;
				}
				if(startsWith(search[i], "$"))
				{
					int idx = findSubmatch(submatch, search[i]);
					if(idx >= 0)
					{
						if(!compareTokens(submatch[idx].start, submatch[idx].end, mit))
							goto Lnomatch;
						goto LnoAdvance;
					}
					else if(startsWith(search[i], "$_num"))
					{
						if(mit.type != Token.Number)
							break;
						addSubmatch(search[i], mit, mit + 1);
					}
					else if(startsWith(search[i], "$_ident"))
					{
						if(mit.type != Token.Identifier)
							break;
						addSubmatch(search[i], mit, mit + 1);
					}
					else if(startsWith(search[i], "$_dotident"))
					{
						if(mit.type != Token.Identifier)
							break;

						TokenIterator start = mit;
						while(!(mit + 1).atEnd() && !(mit + 2).atEnd() && 
						      mit[1].type == Token.Dot && mit[2].type == Token.Identifier)
						{
							mit.advance();
							mit.advance();
						}
						addSubmatch(search[i], start, mit + 1);
					}
					else if(startsWith(search[i], "$_expr"))
					{
						// ok to allow empty expression?
						TokenRange tailmatch;
						if (!findTokenSequence(mit, search[i+1 .. $], true, true, caseSensitive,
						                       ";", tailmatch, submatch))
							break;
						addSubmatch(search[i], mit, tailmatch.start);
						mit = tailmatch.end;
						i = search.length;
						break;
					}
					else if(startsWith(search[i], "$_not") && i + 1 < search.length)
					{
						if(startsWith(search[i + 1], "$_ident"))
						{
							if(mit.type == Token.Identifier)
								break;
						}
						else if(startsWith(search[i + 1], "$_num"))
						{
							if(mit.type == Token.Number)
								break;
						}
						else if(strEqual(mittext, search[i + 1]))
							break;
						addSubmatch(search[i], mit, mit + 1);
						i++;
					}
					else if(startsWith(search[i], "$_opt"))
					{
						i++;
						if(i < search.length && strEqual(mittext, search[i]))
							addSubmatch(search[i-1], mit, mit + 1);
						else
						{
							addSubmatch(search[i-1], mit, mit);
							goto LnoAdvance; // nothing matched
						}
					}
					else
					{
						TokenRange tailmatch;
						if (!findTokenSequence(mit, search[i+1 .. $], 
						                       checkBracketsMatch, checkBracketsMatch, caseSensitive,
						                       stopText, tailmatch, submatch))
							break;
						addSubmatch(search[i], mit, tailmatch.start);
						mit = tailmatch.end;
						i = search.length;
						break;
					}
				}
				else
				{
					int idx = indexOf(search[i], '$');
					if(idx < 0)
					{
						if (!strEqual(mittext, search[i]))
							break;
					}
					else if(mittext.length < idx)
						break;
					else if(!strEqual(mittext[0 .. idx], search[i][0 .. idx]))
						break;
					else
					{
						int sidx = findSubmatch(submatch, search[i][idx .. $]);
						if(sidx < 0)
						{
							// create dummy token and list to add a submatch
							Token subtok = createToken("", mittext[idx .. $], Token.Identifier, mit.lineno, mit.column);
							TokenList sublist = new TokenList;
							sublist.append(subtok);
							addSubmatch(search[i][idx .. $], sublist.begin(), sublist.end());
						}
						else if(!compareSubmatch(submatch[sidx], mittext[idx .. $]))
							break;
					}
				}
				++mit;
			LnoAdvance:
				i++;
				while(i < search.length && search[i].length == 0)
					i++;
			}
			if(i >= search.length)
			{
				match.start = it;
				match.end = mit;
				return true;
			}
		Lnomatch:
			submatch.length = prevsubmatchLength;
		}
		if(checkBracketsSearch && it.isOpeningBracket())
			advanceToClosingBracket(it);
		else if(checkBracketsSearch && it.isClosingBracket())
			break;
		else 
			it.advance();
	}
	return false;
}

TokenList createReplacementTokenList(RTYPE) (RTYPE[] replace, TokenRange match, ref SubMatch[] submatch)
{
	TokenList tokenList = new TokenList;
	for(int i = 0; i < replace.length; i++)
	{
		_string reptext;
		_string pretext;
		int type = Token.Comment;
		static if (is(RTYPE == Token))
		{
			reptext = replace[i].text;
			pretext = replace[i].pretext;
			type = replace[i].type;
			if(reptext == "$" && i + 1 < replace.length && replace[i+1].pretext == "")
			{
				reptext ~= replace[i + 1].text;
				i++;
			}
		}
		else
		{
			reptext = replace[i];
		}

		if(reptext == "$*")
			tokenList.appendList(copyTokenList(match));

		else if(startsWith(reptext, "$"))
		{
			int idx = findSubmatch(submatch, reptext);
			if(idx < 0)
				throwException(0, "no submatch for " ~ reptext);

			TokenList list = copyTokenList(submatch[idx].start, submatch[idx].end);
			if(!list.empty && pretext.length)
				list.begin().pretext = pretext ~ list.begin().pretext;
			tokenList.appendList(list);
		}
		else
		{
			Token tok = createToken(pretext, reptext, type, 0, 0);
			tokenList.append(tok);
		}
	}
	return tokenList;
}


int _replaceTokenSequence(RTYPE)(TokenList srctoken, _string[] search, RTYPE[] replace, 
								 ref const ReplaceOptions opt, ReplaceRange[]* ranges)
{
	for(int i = 0; i < search.length; i++)
		search[i] = strip(search[i]);

	int cntReplacements = 0;
	TokenIterator it = srctoken.begin();
	for( ; ; )
	{
		TokenRange match;
		SubMatch[] submatch;
		if(!findTokenSequence(it, search, false, opt.matchBrackets, opt.matchCase, "", match, submatch))
			break;

		ReplaceRange rng;
		if(ranges)
		{
			if(match.end.atEnd())
			{
				TokenIterator mit = match.end - 1;
				rng.endlineno   = mit.lineno;
				rng.endcolumn   = mit.column;
				advanceTextPos(mit.pretext, rng.endlineno, rng.endcolumn);
				advanceTextPos(mit.text, rng.endlineno, rng.endcolumn);
			}
			else
			{
				rng.endlineno   = match.end.lineno;
				rng.endcolumn   = match.end.column;
			}
		}
		if(!opt.findOnly)
		{
			_string pretext;
			if(!opt.includePretext)
			{
				pretext = match.start.pretext;
				match.start.pretext = "";
				advanceTextPos(pretext, match.start.lineno, match.start.column);
			}

			TokenList tokenList = createReplacementTokenList(replace, match, submatch);
			markReplaceTokenList(tokenList);
			
			if(ranges)
			{
				rng.startlineno = match.start.lineno;
				rng.startcolumn = match.start.column;
				rng.replacementText = tokenListToString(tokenList);
				
				*ranges ~= rng;
			}

			if(!tokenList.empty())
				tokenList.begin().pretext = pretext ~ tokenList.begin().pretext;

			srctoken.remove(match.start, match.end);
			srctoken.insertListBefore(match.end, tokenList);
		}
		else
		{
			if(ranges)
			{
				rng.startlineno = match.start.lineno;
				rng.startcolumn = match.start.column;
				if(!opt.includePretext)
					advanceTextPos(match.start.pretext, rng.startlineno, rng.startcolumn);
				*ranges ~= rng;
			}
			if(!opt.findMultiple)
				return 1;
		}
		it = match.end; // should we recurse into the replacement?
		cntReplacements++;
	}
	return cntReplacements;
}

int replaceTokenSequence(TokenList srctoken, _string[] search, _string[] replace, 
						 ref const ReplaceOptions opt, ReplaceRange[]* ranges)
{
	return _replaceTokenSequence(srctoken, search, replace, opt, ranges);
}

int replaceTokenSequence(TokenList srctoken, _string search, _string replace,
						 ref const ReplaceOptions opt, ReplaceRange[]* ranges)
{
	_string[] searchTokens;
	scanTextArray!(_string)(searchTokens, search);
	Token[] replaceTokens;
	scanTextArray!(Token)(replaceTokens, replace);

	return _replaceTokenSequence(srctoken, searchTokens, replaceTokens, opt, ranges);
}

_string replaceTokenSequence(_string srctext, int srclineno, int srccolumn, _string search, _string replace, 
							 ref const ReplaceOptions opt, ReplaceRange[]* ranges)
{
	TokenList tokens = scanText(srctext, srclineno, srccolumn);
	
	int cnt = replaceTokenSequence(tokens, search, replace, opt, ranges);
	if(cnt == 0)
		return srctext;
	_string newtext = tokenListToString(tokens);
	return newtext;
}

unittest
{
	_string txt = 
		"unittest {\n"
		"  if (list_freelist) {\n"
		"    list--;\n"
		"  }\n"
		"}\n"
		;
	
	ReplaceOptions opt;
	ReplaceRange rng1[];
	_string res1 = replaceTokenSequence(txt, 1, 0, "if($1) { $2 }", "$2", opt, &rng1);

	_string exp1 = 
		"unittest {\n"
		"  \n"
		"    list--;\n"
		"}\n"
		;
	assert(res1 == exp1);
	assert(rng1.length == 1);
	assert(rng1[0].startlineno == 2 && rng1[0].startcolumn == 2);
	assert(rng1[0].endlineno   == 4 && rng1[0].endcolumn   == 3);
	
	opt.includePretext = true;
	ReplaceRange rng2[];
	_string res2 = replaceTokenSequence(txt, 1, 0, "if($1) { $2 }", "$2", opt, &rng2);

	_string exp2 = 
		"unittest {\n"
		"    list--;\n"
		"}\n"
		;
	assert(res2 == exp2);
	assert(rng2.length == 1);
	assert(rng2[0].startlineno == 1 && rng2[0].startcolumn == 10);
	assert(rng2[0].endlineno   == 4 && rng2[0].endcolumn   == 3);
}
