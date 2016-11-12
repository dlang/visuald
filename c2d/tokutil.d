// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module c2d.tokutil;

import c2d.tokenizer;
import c2d.dlist;
import c2d.dgutil;

import std.string;
import std.ascii;
import std.array;
//static import std.regexp;
static import std.regex;
static import std.conv;

//////////////////////////////////////////////////////////////////////////////
alias DList!(c2d.tokenizer.Token) TokenList;
alias DListIterator!(c2d.tokenizer.Token) TokenIterator;

alias object.AssociativeArray!(string, const(TokenList)) _wa2; // fully instantiate type info for TokenList[string]

struct TokenRange
{
	TokenIterator start;
	TokenIterator end;
}

struct SubMatch
{
	string ident;
	TokenIterator start;
	TokenIterator end;
}

//////////////////////////////////////////////////////////////////////////////
Token createToken(string pretext, string text, int type, int lineno)
{
	Token tok = new Token();
	tok.pretext = pretext;
	tok.text = text;
	tok.type = type;
	tok.lineno = lineno;
	return tok;
}

Token createToken(Token tok)
{
	Token ntok = new Token();
	ntok.pretext = tok.pretext;
	ntok.text = tok.text;
	ntok.type = tok.type;
	ntok.lineno = tok.lineno;
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

void comment_line(ref TokenIterator tokIt)
{
	TokenIterator it = tokIt + 1;
	string txt = tokIt.pretext ~ "// " ~ tokIt.text;
	while(!it.atEnd() && it.pretext.indexOf('\n') < 0 && it.type != Token.EOF)
	{
		txt ~= it.pretext ~ it.text;
		it.advance();
	}
	if(!it.atEnd())
	{
		tokIt.eraseUntil(it);
		tokIt.pretext = txt ~ tokIt.pretext;
	}
	else
		tokIt.text = "// " ~ tokIt.text;
}

void nextToken(ref TokenIterator tokIt, bool skipPP = true)
{
	tokIt.advance();
	skipComments(tokIt, skipPP);
}

void checkToken(ref TokenIterator tokIt, int type, bool skipPP = true)
{
	skipComments(tokIt, skipPP);
	
	if(tokIt.atEnd() ||tokIt.type != type)
	{
		string txt = tokIt.atEnd() ? "EOF" : tokIt.text;
		int lineno = tokIt.atEnd() ? (tokIt-1).atEnd() ? -1 : tokIt[-1].lineno : tokIt.lineno;
		throwException(lineno, "expected " ~ Token.toString(type) ~ " instead of " ~ txt);
	}
	nextToken(tokIt, skipPP);
}

void checkOperator(ref TokenIterator tokIt)
{
	// TODO: allows any token 
	if(tokIt.type == Token.BracketL)
	{
		nextToken(tokIt);
		checkToken(tokIt, Token.BracketR);
	}
	else
		nextToken(tokIt);
}

string tokensToIdentifier(TokenIterator start, TokenIterator end)
{
	string ident;
	while(!start.atEnd() && start != end)
	{
		if(ident.length > 0 && start.text.length > 0)
			if(isAlphaNum(ident[$-1]) && isAlphaNum(start.text[0]))
				ident ~= " ";
		ident ~= start.text;
		++start;
	}
	return ident;
}

void identifierToKeywords(TokenIterator start, TokenIterator end)
{
	while(!start.atEnd() && start != end)
	{
		if(start.type == Token.Identifier)
			start.type = Tokenizer.identifierToKeyword(start.text);
		++start;
	}
}

void identifierToKeywords(TokenList list)
{
	return identifierToKeywords(list.begin(), list.end());
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

string tokenListToString(TokenIterator start, TokenIterator end, bool checkSpaceBetweenIdentifiers = false,
			 bool normalizePreText = false)
{
	string text;
	string prevtext;
	for(TokenIterator tokIt = start; tokIt != end; ++tokIt)
	{
		Token tok = *tokIt;
		string txt = normalizePreText ? tok.text : tok.pretext ~ tok.text;
		if(checkSpaceBetweenIdentifiers || normalizePreText)
		{
			if (prevtext == "__")
				txt = tok.text;
			else if (tok.text == "__")
				txt = "";
			else if (txt.length && prevtext.length)
			{
				char prevch = prevtext[$-1];
				char ch = txt[0];
				if((isAlphaNum(ch) || ch == '_') && (isAlphaNum(prevch) || prevch == '_'))
					txt = " " ~ txt;
			}
			prevtext = tok.text;
		}
		text ~= txt;
	}
	return text;
}

string tokenListToString(TokenList tokenList, bool checkSpaceBetweenIdentifiers = false)
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
void reindentList(TokenIterator start, TokenIterator end, int indent, int tabsize)
{
	for(TokenIterator tokIt = start; tokIt != end; ++tokIt)
		tokIt.pretext = reindent(tokIt.pretext, indent, tabsize);
}

void reindentList(TokenList tokenList, int indent, int tabsize)
{
	return reindentList(tokenList.begin(), tokenList.end(), indent, tabsize);
}

//////////////////////////////////////////////////////////////////////////////
bool isClosingBracket(int type)
{
	return (type == Token.BraceR || type == Token.BracketR || type == Token.ParenR);
}

bool isOpeningBracket(int type)
{
	return (type == Token.BraceL || type == Token.BracketL || type == Token.ParenL);
}

bool isBracketPair(dchar ch1, dchar ch2)
{
	switch(ch1)
	{
		case '{': return ch2 == '}';
		case '}': return ch2 == '{';
		case '(': return ch2 == ')';
		case ')': return ch2 == ')';
		case '[': return ch2 == ']';
		case ']': return ch2 == '[';
		default:  return false;
	}
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
static void scanAny(TL)(ref TL tokenList, string text, int lineno = 1, bool combinePP = true)
{
	Tokenizer tokenizer = new Tokenizer(text);
	tokenizer.keepBackSlashAtEOL = true;
	tokenizer.lineno = lineno;

	try
	{
		string pretext;
		Token pptok = new Token;
		Token tok;
		do
		{
			tok = new Token;
			tokenizer.next(tok);

			if(combinePP && Token.isPPToken(tok.type))
			{
				tokenizer.skipNewline = false;
				while(tokenizer.next(pptok) && pptok.type != Token.Newline)
					tok.text ~= pptok.pretext ~ pptok.text;
				tokenizer.skipNewline = true;
				tok.text ~= pptok.pretext;
				if(pptok.type == Token.Newline)
					tok.text ~= "\n";
			}
			switch(tok.type)
			{
			case Token.Comment:
				if(startsWith(tok.text, ";")) // aasm comment?
					pretext ~= tok.pretext ~ "//" ~ tok.text;
				else
					pretext ~= tok.pretext ~ tok.text;
				break;

			case Token.__Asm:
				tokenizer.enableASMComment = true;
				tokenizer.skipNewline = false;
				goto default;

			case Token.BraceR:
				if(tokenizer.enableASMComment)
				{
					tokenizer.enableASMComment = false;
					tokenizer.skipNewline = true;
				}
				goto default;

			default:
				tok.pretext = pretext ~ tok.pretext;
				static if(is(TL == Token[]))
					tokenList ~= tok;
				else static if(is(TL == string[]))
					tokenList ~= tok.text;
				else
					tokenList.append(tok);
				pretext = "";
				break;
			}
		} 
		while (tok.type != Token.EOF);

	}
	catch(Exception e)
	{
		string msg = "(" ~ std.conv.text(tokenizer.lineno) ~ "):" ~ e.toString();
		throw new Exception(msg);
	}
}

TokenList scanText(string text, int lineno = 1, bool combinePP = true)
{
	TokenList tokenList = new TokenList;
	scanAny(tokenList, text, lineno, combinePP);
	return tokenList;
}

void scanTextArray(TYPE)(ref TYPE[] tokens, string text, int lineno = 1, bool combinePP = true)
{
	scanAny(tokens, text, lineno, combinePP);

	static if(is(TYPE == string))
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
int findSubmatch(ref SubMatch[] submatch, string ident)
{
	for(int i = 0; i < submatch.length; i++)
		if(submatch[i].ident == ident)
			return i;
	return -1;
}

///////////////////////////////////////////////////////////////////////
bool findTokenSequence(TokenIterator it, string[] search, bool checkBracketsSearch, bool checkBracketsMatch,
                       string stopText, ref TokenRange match, ref SubMatch[] submatch)
{
	if(search.length == 0)
	{
		match.start = it;
		match.end = it;
		return true;
	}

	void addSubmatch(string search, TokenIterator start, TokenIterator end)
	{
		SubMatch smatch;
		smatch.ident = search;
		smatch.start = start;
		smatch.end = end;
		submatch ~= smatch;
	}

	bool compareTokens(TokenIterator start, TokenIterator end, ref TokenIterator it)
	{
		for(TokenIterator sit = start; !sit.atEnd() && sit != end; ++sit)
		{
			string sittext = strip(sit.text);
			if(sittext.length == 0)
				continue;
			while(!it.atEnd() && strip(it.text).length == 0)
				++it;
			if(it.atEnd())
				return false;
			if(strip(it.text) != sittext)
				return false;
			++it;
		}
		return true;
	}
	bool compareSubmatch(ref SubMatch sm, string txt)
	{
		string s = tokenListToString(sm.start, sm.end);
		return strip(s) == strip(txt);
	}

	size_t p = 0;
	while(p < search.length && search[p].length == 0)
		p++;
	if(p >= search.length)
		return false;

	size_t prevsubmatchLength = submatch.length;

	while(!it.atEnd() && (stopText.length == 0 || it.text != stopText || search[p] == stopText))
	{
		bool dollar = indexOf(search[p], '$') >= 0;
		if(strip(it.text) == search[p] || dollar)
		{
			TokenIterator mit = it + (dollar ? 0 : 1);
			size_t i = p + (dollar ? 0 : 1);
			while(i < search.length && search[i].length == 0)
				i++;
			while(!mit.atEnd() && i < search.length)
			{
				string mittext = strip(mit.text);
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
					else if(startsWith(search[i], "$_string"))
					{
						if(mit.type != Token.String)
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
						if (!findTokenSequence(mit, search[i+1 .. $], true, true, ";",
								       tailmatch, submatch))
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
						else if(startsWith(search[i], "$_string"))
						{
							if(mit.type != Token.String)
								break;
						}
						else if(mittext == search[i + 1])
							break;
						addSubmatch(search[i], mit, mit + 1);
						i++;
					}
					else if(startsWith(search[i], "$_opt"))
					{
						i++;
						if(i < search.length && mittext == search[i])
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
						if (!findTokenSequence(mit, search[i+1 .. $], checkBracketsMatch, checkBracketsMatch, 
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
					ptrdiff_t idx = indexOf(search[i], '$');
					if(idx < 0)
					{
						if (mittext != search[i])
							break;
					}
					else if(mittext.length < idx)
						break;
					else if(mittext[0 .. idx] != search[i][0 .. idx])
						break;
					else
					{
						int sidx = findSubmatch(submatch, search[i][idx .. $]);
						if(sidx < 0)
						{
							// create dummy token and list to add a submatch
							Token subtok = createToken("", mittext[idx .. $], Token.Identifier, mit.lineno);
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
		if(checkBracketsSearch && isOpeningBracket(it.type))
			advanceToClosingBracket(it);
		else if(checkBracketsSearch && isClosingBracket(it.type))
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
		string reptext;
		string pretext;
		int type = Token.PPinsert;
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
				throwException("no submatch for " ~ reptext);

			TokenList list = copyTokenList(submatch[idx].start, submatch[idx].end);
			if(!list.empty && !list.begin().pretext.length) //&& pretext.length)
				list.begin().pretext = pretext; // ~ list.begin().pretext;
			tokenList.appendList(list);
		}
		else
		{
			Token tok = createToken(pretext, reptext, type, 0);
			tokenList.append(tok);
		}
	}
	return tokenList;
}


int _replaceTokenSequence(RTYPE)(TokenList srctoken, string[] search, RTYPE[] replace, bool checkBrackets)
{
	if(search.length == 0)
		return 0;

	for(int i = 0; i < search.length; i++)
		search[i] = strip(search[i]);

	int cntReplacements = 0;
	TokenIterator it = srctoken.begin();
	for( ; ; )
	{
		TokenRange match;
		SubMatch[] submatch;
		if(!findTokenSequence(it, search, false, checkBrackets, "", match, submatch))
			break;

		string pretext = match.start.pretext;
		match.start.pretext = "";
		TokenList tokenList = createReplacementTokenList(replace, match, submatch);

		if(!tokenList.empty())
			tokenList.begin().pretext = pretext ~ tokenList.begin().pretext;

		srctoken.remove(match.start, match.end);
		srctoken.insertListBefore(match.end, tokenList);
		
		it = match.end;
		// avoid recursing into the replacement?
		cntReplacements++;
	}
	return cntReplacements;
}

int replaceTokenSequence(TokenList srctoken, string[] search, string[] replace, bool checkBrackets)
{
	return _replaceTokenSequence(srctoken, search, replace, checkBrackets);
}

int replaceTokenSequence(TokenList srctoken, string search, string replace, bool checkBrackets)
{
	string[] searchTokens;
	scanTextArray!(string)(searchTokens, search);
	Token[] replaceTokens;
	scanTextArray!(Token)(replaceTokens, replace);

	return _replaceTokenSequence(srctoken, searchTokens, replaceTokens, checkBrackets);
}

///////////////////////////////////////////////////////////////////////

TokenList scanArgument(ref TokenIterator it)
{
	TokenIterator start = it;
	
	while(!it.atEnd() && it.type != Token.Comma && it.type != Token.ParenR)
	{
		if(it.type == Token.ParenL)
			advanceToClosingBracket(it);
		else
			it.advance();

		if(it.atEnd())
			throwException(start.lineno, "unterminated macro invocation");
	}

	TokenList tokenList = new TokenList;
	for( ; start != it; ++start)
		tokenList.append(*start);

	return tokenList;
}

void replaceArgument(ref TokenIterator defIt, TokenList list, void delegate(bool, TokenList) expandList)
{
	// defIt on identifer to replace
	string pretext = defIt.pretext;
	int lineno = 0;
	if(!list.empty())
		lineno = list.begin().lineno;

	if(pretext.length > 0)
	{
		defIt.insertBefore(createToken(pretext, "", Token.Comment, defIt.lineno));
	}
	defIt.erase();
	if(!defIt.atBegin() && defIt[-1].type == Token.Fis)
	{
		if(expandList)
		{
			list = copyTokenList(list);
			expandList(true, list);
		}
		// TODO: should create escape sequences?
		string insText = "\"" ~ strip(tokenListToString(list)) ~ "\"";
		Token tok = createToken("", insText, Token.String, defIt[-1].lineno);
		defIt.retreat();
		defIt.insertAfter(tok);
		defIt.erase(); // remove '#'
	}
	else
	{
		bool org = ((!defIt.atBegin() && defIt[-1].type == Token.FisFis) || (!defIt.atEnd() && defIt.type == Token.FisFis));
		TokenList insList = copyTokenList(list);
		if(!org && expandList)
			expandList(true, insList);

		TokenIterator ins = defIt;
		insertTokenList(ins, insList);
	}
}

TokenList removeFisFis(TokenList tokens)
{
	int cntFisFis = 0;
	TokenIterator it = tokens.begin();
	while(!it.atEnd())
	{
		if(it.type == Token.FisFis)
		{
			it.erase();
			if(!it.atEnd())
				it.pretext = "";
			cntFisFis++;
		}
		it.advance();
	}
	if(cntFisFis == 0)
		return tokens;
	
	string text = strip(tokenListToString(tokens));
	TokenList newList = scanText(text, tokens.begin().lineno);
	return newList;
}

// returns iterator after insertion, it is set to iterator at beginning of insertion
TokenIterator expandDefine(ref TokenIterator it, TokenList define, void delegate(bool, TokenList) expandList)
{
	define = copyTokenList(define, true);
	TokenIterator srcIt = it;
	TokenIterator defIt = define.begin() + 2;
	string pretext = srcIt.pretext;
	
	TokenList[string] args;
	checkToken(it, Token.Identifier, false);
	if(!defIt.atEnd() && defIt.type == Token.ParenL && defIt.pretext.length == 0)
	{
		nextToken(defIt, false);
		checkToken(it, Token.ParenL, false);
		if(defIt.type != Token.ParenR)
		{
			for( ; ; )
			{
				string ident = defIt.text;
				checkToken(defIt, Token.Identifier, false);
				args[ident] = scanArgument(it);
				if(defIt.type == Token.ParenR)
					break;
				checkToken(defIt, Token.Comma, false);
				checkToken(it, Token.Comma, false);
			}
		}
		checkToken(defIt, Token.ParenR, false);
		checkToken(it, Token.ParenR, false);
	}

	if(!defIt.atEnd())
		defIt.pretext = stripLeft(defIt.pretext);

	define.begin().eraseUntil(defIt);
	while(!defIt.atEnd())
	{
		defIt.pretext = replace(defIt.pretext, "\\\n", "\n");
		if(defIt.type == Token.Identifier)
			if(TokenList* list = defIt.text in args)
			{
				replaceArgument(defIt, *list, expandList);
				continue;
			}
		defIt.advance();
	}

	if(!define.empty())
	{
		define = removeFisFis(define);
		srcIt.eraseUntil(it);  // makes srcIt invalid, but it stays valid
		srcIt = it;
		if(expandList)
		{
			expandList(false, define);
			it = insertTokenList(srcIt, define); // it is after insertion now
		}
		else
			it = insertTokenList(srcIt, define);
	}
	else
	{
		srcIt.eraseUntil(it);  // makes srcIt invalid, but it stays valid
		srcIt = it;
	}
	if(!it.atEnd())
		it.pretext = pretext ~ it.pretext;
	return srcIt;
}

enum MixinMode
{
	ExpandDefine,
	ExpressionMixin,
	StatementMixin,
	LabelMixin
}

// if createMixins === 0: 
void expandPPdefines(TokenList srctokens, TokenList[string] defines, MixinMode mixinMode)
{
	for(TokenIterator it = srctokens.begin(); !it.atEnd(); )
	{
		if(it.type == Token.PPdefine)
		{
			string text = strip(it.text);
			TokenList defList = scanText(text, it.lineno, false);
			TokenIterator tokIt = defList.begin();
			assume(tokIt[0].type == Token.PPdefine);
			assume(tokIt[1].type == Token.Identifier);

			if(TokenList* list = tokIt[1].text in defines)
			{
				// remove trailing comments
				while((defList.end()-1).text.empty())
					(defList.end()-1).erase();

				*list = defList;
				if(mixinMode != MixinMode.ExpandDefine)
				{
					it.text = createMixinFunction(defList, mixinMode);
					it.type = Token.PPinsert;
				}
				else
				{
					string pretext = it.pretext;
					it.erase();
					it.pretext = pretext ~ it.pretext;
					continue;
				}
			}
			else
			{
				// expand content of define
				tokIt = tokIt + 2;
				if(tokIt.text == "(" && tokIt.pretext == "")
					advanceToClosingBracket(tokIt);
				bool changed = false;
				while(!tokIt.atEnd())
				{
					if(tokIt.type == Token.Identifier)
						if(TokenList* list = tokIt.text in defines)
						{
							if(*list !is null)
							{
								if(mixinMode != MixinMode.ExpandDefine)
									invokeMixin(tokIt, mixinMode);
								else
									expandDefine(tokIt, *list, null);
								changed = true;
								continue;
							}
						}
					tokIt.advance();
				}
				if(changed)
					it.text = tokenListToString(defList) ~ "\n";
			}
		}
		else if(it.type == Token.PPundef)
		{
			TokenList undefList = scanText(it.text, it.lineno, false);
			TokenIterator tokIt = undefList.begin();
			assume(tokIt[0].type == Token.PPundef);
			assume(tokIt[1].type == Token.Identifier);
	
			if(TokenList* list = tokIt[1].text in defines)
			{
				string pretext = it.pretext;
				*list = null;
				it.erase();
				it.pretext = pretext ~ it.pretext;
				continue;
			}
		}
		else if(it.type == Token.Identifier)
		{
			if(TokenList* list = it.text in defines)
			{
				if(*list !is null)
				{
					if(mixinMode != MixinMode.ExpandDefine)
						invokeMixin(it, mixinMode);
					else
						expandDefine(it, *list, null);
					continue;
				}
			}
		}
		it.advance();
	}
}

void insertTokenBefore(ref TokenIterator it, Token tok, string tokpretext = "")
{
	it.pretext ~= tok.pretext;
	tok.pretext = tokpretext;
	
	it.insertBefore(tok);
}

void invokeMixin(ref TokenIterator it, MixinMode mixinMode)
{
	TokenIterator start = it;
	assume(it.type == Token.Identifier);
	string text = "mixin(" ~ it.text;

	nextToken(it);
	if(it.type == Token.ParenL && it.pretext.length == 0)
	{
		nextToken(it, false);
		text ~= "(";
		if(it.type != Token.ParenR)
		{
			string sep;
			for( ; ; )
			{
				TokenList arg = scanArgument(it);
				string argtext = strip(tokenListToString(arg));
				//text ~= sep ~ "\"" ~ argtext ~ "\"";
				text ~= sep ~ argtext;
				sep = ", ";

				if(it.type == Token.ParenR)
					break;
				checkToken(it, Token.Comma, false);
			}
		}
		text ~= ")";
		nextToken(it, false);
	}
	text ~= ")";
	if(mixinMode == MixinMode.StatementMixin && it.type != Token.Semicolon)
		text ~= ";";
	if(mixinMode == MixinMode.LabelMixin && it.type == Token.Colon)
	{
		text ~= ";";
		it.erase();
	}

	start.insertBefore(createToken(start.pretext, text, Token.PPinsert, it.lineno));
	start.eraseUntil(it);
}

string createMixinFunction(TokenList tokList, MixinMode mixinMode)
{
	TokenIterator it = tokList.begin();
	checkToken(it, Token.PPdefine, false);
	string ident = it.text;
	checkToken(it, Token.Identifier, false);

	string text = "static __string " ~ ident ~ "(";

	int[string] argsUsage;
	if(it.type == Token.ParenL && it.pretext.length == 0)
	{
		nextToken(it);
		if(it.type != Token.ParenR)
		{
			string sep;
			for( ; ; )
			{
				string arg = it.text;
				checkToken(it, Token.Identifier, false);
				argsUsage[arg] = 0;

				text ~= sep ~ "__string " ~ arg;
				sep = ", ";

				if(it.type == Token.ParenR)
					break;
				checkToken(it, Token.Comma, false);
			}
		}
		nextToken(it);
	}
	text ~= ") { return \"";

	if(!it.atEnd())
		it.pretext = stripLeft(it.pretext);

	while(!it.atEnd())
	{
		if(it.type == Token.Identifier && (it.text in argsUsage))
		{
			text ~= it.pretext ~ "\" ~ " ~ it.text ~ " ~ \"";
			argsUsage[it.text]++;
		}
		else
			text ~= replace(it.pretext ~ it.text, "\"", "\\\"");
		it.advance();
	}

	if(mixinMode == MixinMode.StatementMixin && !endsWith(text, ";"))
		text ~= ";";
	if(mixinMode == MixinMode.LabelMixin && !endsWith(text, ";"))
	{
		if (!endsWith(text, ":"))
			text ~= ":";
		text ~= ";";
	}

	text = replace(text, "##", "");
	text ~= "\"; }\n";
	return text;
}

void regexReplacePPdefines(TokenList srctokens, string[string] defines)
{
	for(TokenIterator it = srctokens.begin(); !it.atEnd(); )
	{
		if(it.type == Token.PPdefine)
		{
			string text = strip(it.text);
			TokenList defList = scanText(text, it.lineno, false);
			TokenIterator tokIt = defList.begin();
			assume(tokIt[0].type == Token.PPdefine);
			assume(tokIt[1].type == Token.Identifier);

			string ident = tokIt[1].text;
			foreach(re, s; defines)
			{
				//if(std.regexp.find(ident, re) >= 0)
				auto rex = std.regex.regex(re);
				if(!std.regex.match(ident, rex).empty())
				{
					// no arguments supported so far
					string posttext = "\n";
					TokenIterator endIt = defList.end();
					while(endIt[-1].type == Token.Newline || endIt[-1].type == Token.EOF || endIt[-1].type == Token.Comment)
					{
						endIt.retreat();
						posttext = endIt.pretext ~ endIt.text ~ posttext;
					}
					string text = tokenListToString(tokIt + 2, endIt);
					string txt = s;
					txt = replace(txt, "$id", ident);
					txt = replace(txt, "$text", text);
					it.pretext ~= tokIt.pretext;
					it.text = txt ~ posttext;
					it.type = Token.PPinsert;
					break;
				}
			}
		}
		it.advance();
	}
}

///////////////////////////////////////////////////////////////////////

string testDefine(string txt, TokenList[string] defines)
{
	TokenList list = scanText(txt);
	expandPPdefines(list, defines, MixinMode.ExpandDefine);
	// src.fixConditionalCompilation();
	string res = tokenListToString(list);
	return res;
}

unittest
{
	string txt = 
		  "#define X(a) a\n"
		~ "before X(1) after\n"
		~ "#undef X\n"
		~ "X(2)\n"
		~ "#define X(a)\n"
		~ "X(3)\n"
		;

	string exp = 
		  "before 1 after\n"
		~ "X(2)\n"
		~ "\n"
		;

	TokenList[string] defines = [ "X" : null ];
	string res = testDefine(txt, defines);
	assume(res == exp);
}

unittest
{
	string txt = 
		  "#define X(a) #a\n"
		~ "X(1)\n"
		~ "#undef X\n"
		~ "#define X(a) x(#a)\n"
		~ "X(1+2+3)\n"
		;

	string exp = 
		  "\"1\"\n"
		~ "x(\"1+2+3\")\n"
		;

	TokenList[string] defines = [ "X" : null ];
	string res = testDefine(txt, defines);
	assume(res == exp);
}

unittest
{
	string txt = 
		  "#define X(a) a##1\n"
		~ "X(2)\n"
		;

	string exp = 
		"21\n"
		;

	TokenList[string] defines = [ "X" : null ];
	string res = testDefine(txt, defines);
	assume(res == exp);
}

///////////////////////////////////////////////////////////////////////

string testMixin(string txt, TokenList[string] mixins)
{
	TokenList list = scanText(txt);
	expandPPdefines(list, mixins, MixinMode.StatementMixin);
	// src.fixConditionalCompilation();
	string res = tokenListToString(list);
	return res;
}

unittest
{
	string txt = 
		  "#define X(a) x = a;\n"
		~ "X(b);\n"
		;

	string exp = 
		  "static __string X(__string a) { return \"x = \" ~ a ~ \";\"; }\n"
		~ "mixin(X(b));\n"
		;

	TokenList[string] mixins = [ "X" : null ];
	string res = testMixin(txt, mixins);
	assume(res == exp);
}

///////////////////////////////////////////////////////////////////////

string testReplace(string txt, TokenList[string] defines)
{
	TokenList list = scanText(txt);
	expandPPdefines(list, defines, MixinMode.ExpandDefine);
	// src.fixConditionalCompilation();
	string res = tokenListToString(list);
	return res;
}

unittest
{
	string txt = 
		  "  if (list_freelist) {\n"
		~ "    list--;\n"
		~ "__static_if(MEM_DEBUG) {\n"
		~ "    mem_setnewfileline(list,file,line);\n"
		~ "}\n"
		~ "  } else {\n"
		~ "    list++;\n"
		~ "  }\n"
		;

	string exp = 
		  "  if (list_freelist) {\n"
		~ "    list--;\n"
		~ "  } else {\n"
		~ "    list++;\n"
		~ "  }\n"
		;

	TokenList list = scanText(txt);

	replaceTokenSequence(list, "__static_if(MEM_DEBUG) { $1 } else { $2 }", "$2", true);
	replaceTokenSequence(list, "__static_if(MEM_DEBUG) { $1 }", "", true);

	string res = tokenListToString(list);
	assume(res == exp);
}

unittest
{
	string txt = 
		  "#define X(p) \\\n"
		~ "    int p##1(); \\\n"
		~ "    int p##2(); \\\n"
		~ "    int p##3();\n"
		~ "X(a)\n"
		~ "X(b)\n"
		~ "X(c)\n";

	string exp = 
		  "int a1(); \n"
		~ "    int a2(); \n"
		~ "    int a3();\n"
		~ "int b1(); \n"
		~ "    int b2(); \n"
		~ "    int b3();\n"
		~ "int c1(); \n"
		~ "    int c2(); \n"
		~ "    int c3();\n";

	TokenList list = scanText(txt);

	TokenList[string] defines = [ "X" : null ];
	expandPPdefines(list, defines, MixinMode.ExpandDefine);

	string res = tokenListToString(list);
	assume(res == exp);
}

unittest 
{
	string txt = "0 a __ b c";
	TokenList list = scanText(txt);
	string ntxt = tokenListToString(list, true);
	assume(ntxt == "0 ab c");
}
