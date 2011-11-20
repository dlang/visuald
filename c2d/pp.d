module c2d.pp;

import c2d.tokenizer;
import c2d.dlist;
import c2d.dgutil;
import c2d.tokutil;

import std.string;

class ConditionalCode
{
	this(bool cond, ConditionalCode cc)
	{
		conditional = cond;
		parent = cc;
	}

	void addChild(ConditionalCode cc)
	{
		if(!children)
			children = new DList!(ConditionalCode);
		children.append(cc);
	}

	void fixIterator(ref TokenIterator oldIt, ref TokenIterator newIt)
	{
		if (children)
			for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
				it.fixIterator(oldIt, newIt);
		
		if(start == oldIt)
			start = newIt;
		if(end == oldIt)
			end = newIt;
	}

	//////////////////////////////////////////////////////////////////////////////
	void parseCode(ref TokenIterator tokIt)
	{
		start = tokIt;

		while(!tokIt.atEnd())
		{
			Token tok = *tokIt;
			tokIt.advance();
			switch(tok.type)
			{
			case Token.PPif:
			case Token.PPifdef:
			case Token.PPifndef:
				ConditionalCode cc = new ConditionalCode(true, this);
				cc.parseConditions(tokIt);
				addChild(cc);
				break;
			case Token.PPelse:
			case Token.PPelif:
			case Token.PPendif:
				goto exit_parse;
			default:
				break;
			}
		}
	exit_parse:
		end = tokIt;
	}

	void parseConditions(ref TokenIterator tokIt)
	{
		start = tokIt;

		// tokIt after #if
		ConditionalCode cc = new ConditionalCode(false, this);
		cc.parseCode(tokIt);

		while(!tokIt.atEnd() && tokIt[-1].type != Token.PPendif)
		{
			addChild(cc);
			cc = new ConditionalCode(false, this);
			cc.parseCode(tokIt);
		}

		end = tokIt;
		addChild(cc);
	}

	//////////////////////////////////////////////////////////////////////////////
	int splitPPCondition(Token pptok, ref string condition, ref string comment)
	{
		Tokenizer tokenizer = new Tokenizer(pptok.text);
		Token tok = new Token;
		int conditionTokens = 0;
		while(tokenizer.next(tok))
		{
			if(Token.isPPToken(tok.type))
				continue;

			if(tok.type == Token.Comment)
				comment ~= tok.pretext ~ tok.text;
			else
			{
				condition ~= tok.pretext ~ tok.text;
				conditionTokens++;
			}
		}
		// throw away trailing spaces
		condition = strip(condition);
		if(endsWith(comment, "\n"))
			comment = comment[0..$-1];
		return conditionTokens;
	}

	//////////////////////////////////////////////////////////////////////////////
	bool hasOpenIf(TokenIterator* pit = null)
	{
		if(end[-2].type != Token.ParenR)
			return false;

		TokenIterator it = end - 2;
		if (!retreatToOpeningBracket(it, start))
			return false;

		--it;
		if (it.type != Token.If) //  && it.type != Token.While && it.type != Token.For)
			return false;

		if(pit)
		    *pit = it;
		return true;
	}
	bool hasOpenElse()
	{
		return (end[-2].type == Token.Else);
	}

	//////////////////////////////////////////////////////////////////////////////

	void convertOpenIfToCondition(string cond)
	{
		TokenIterator it;
		bool hasOpen = hasOpenIf(&it);
		if(!hasOpen)
			it = end - 2;

		Token tok = *it;
		Token condtok = createToken("", cond, Token.Identifier, tok.lineno);
		Token asgntok = createToken(" ", "=", Token.Assign, tok.lineno);
		Token semitok = createToken("", ";", Token.Semicolon, end[-2].lineno);

		(end - 2).insertAfter(semitok);

		if(!hasOpen)
		{
			Token truetok = createToken(" ", "true", Token.Identifier, tok.lineno);
			it.insertAfter(truetok);
		}
		it.insertAfter(asgntok);
		if(!hasOpen)
		{
			condtok.pretext = end[-1].pretext;
			end[-1].pretext = "\n";
			it.insertAfter(condtok);
		}
		else
		{
			tok.type = condtok.type;
			tok.text = condtok.text;
		}
	}

	void insertDecl(string type, string var, string init, TokenIterator it)
	{
		string pretext = it.pretext;
		if(type.length > 0)
		{
			it.insertBefore(createToken(pretext, type, Token.Identifier, it.lineno));
			pretext = " ";
		}
		it.insertBefore(createToken(pretext, var, Token.Identifier, it.lineno));
		if(init.length > 0)
		{
			it.insertBefore(createToken(" ", "=", Token.Assign, it.lineno));
			it.insertBefore(createToken(" ", init, Token.Identifier, it.lineno));
		}
		it.insertBefore(createToken("", ";", Token.Semicolon, it.lineno));
		it.pretext = "";
	}

	void insertIf(string cond, TokenIterator it)
	{
		Token iftok = createToken(it.pretext, "if", Token.If, it.lineno);
		Token pLtok = createToken(" ", "(", Token.ParenL, it.lineno);
		Token condtok = createToken("", cond, Token.Identifier, it.lineno);
		Token pRtok = createToken("", ")", Token.ParenR, it.lineno);
		it.insertBefore(iftok);
		it.insertBefore(pLtok);
		it.insertBefore(condtok);
		it.insertBefore(pRtok);

		it.pretext = " ";
	}

	string createStaticIf(string condition)
	{
		if(isVersionDefine(strip(condition)))
			return "__version(" ~ condition ~ ")";
		return "__static_if(" ~ condition ~ ")";
	}

	///////////////////////////////////////////////////////
	void convertSingleOpenIf()
	{
		// convert
		//     #if C1
		//         exec1;
		//         if (b1)
		//     #endif
		//             exec2;
		// to
		//     static if(!(C1)) goto L_F1;
		//         exec1;
		//         if (b1)
		//     L_F1:
		//             exec2;
		//
		// also works for
		//     #if C1
		//         if (b1)
		//             execif;
		//         else
		//     #endif
		//             exec2;
		Token starttok = start[-1];
		string condition, comment;
		int conditionTokens = splitPPCondition(starttok, condition, comment);
		if(conditionTokens > 1)
			condition = "(" ~ condition ~ ")";
		string label = "L_F" ~ format("%d", starttok.lineno);
		starttok.text = createStaticIf("!" ~ condition) ~ " goto " ~ label ~ ";" ~ comment ~ "\n";
		starttok.type = Token.PPinsert;
			
		Token endtok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endtok, endcondition, endcomment);
		endtok.text = label ~ ":" ~ endcondition ~ endcomment ~ "\n";
		endtok.type = Token.PPinsert;
	}

	void convertMultipleOpenIf()
	{
		// convert
		//     #if C1
		//         exec1;
		//         if (b1)
		//     #elif C2
		//         exec2;
		//         if (b2)
		//     #endif
		//             exec3;
		// to
		//     cond = b1;
		//     static if(C1) {
		//         exec1;
		//         cond = b1;
		//     } else static if(C2) {
		//         exec1;
		//         cond = b2;
		//     }
		//         if(cond)
		//             exec;
		// happens to work for else as last entry
		string cond = "cond_" ~ format("%d", start[-1].lineno);
		insertDecl("bool", cond, "", start - 1);
		start[-1].pretext = "\n";

		for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
		{
			Token starttok = it.start[-1];
			string condition, comment;
			splitPPCondition(starttok, condition, comment);
			if (it == children.begin())
				starttok.text = createStaticIf(condition) ~ " {" ~ comment ~ "\n";
			else if (condition == "")
				starttok.text = "} else {" ~ comment ~ "\n";
			else
				starttok.text = "} else " ~ createStaticIf(condition) ~ " {" ~ comment ~ "\n";
			starttok.type = Token.PPinsert;
			it.convertOpenIfToCondition(cond);
		}

		Token endtok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endtok, endcondition, endcomment);
		endtok.text = "}" ~ endcondition ~ endcomment ~ "\n";
		endtok.type = Token.PPinsert;
		insertIf(cond, end);
	}

	///////////////////////////////////////////////////////
	bool isInElseIfSeries()
	{
		if(start[0].type != Token.Else || end[0].type != Token.Else)
			return false;
		if(start[1].type != Token.If)
			return false;
		// check for single statement?
		return true;
	}

	void convertSingleElseIf()
	{
		// translate
		//       if(a)
		//          exec_a;
		//     #if COND
		//       else if (b)
		//          exec_b;
		//     #endif
		//       else if (c)
		//          exec_c;
		// to
		//       if(a)
		//          exec_a;
		//     else if static if(COND)
		//       if (b)
		//          exec_b;
		//     else goto L_F1; else goto L_F1; if(true) {} else L_F1:
		//       if (c)
		//          exec_c;
		Token starttok = start[-1];
		string condition, comment;
		splitPPCondition(starttok, condition, comment);
		starttok.text = "else " ~ createStaticIf(condition) ~ comment ~ "\n";
		starttok.type = Token.PPinsert;
		
		string label = "L_F" ~ format("%d", starttok.lineno);
		Token endtok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endtok, endcondition, endcomment);
		endtok.text = "else goto " ~ label ~ "; else goto " ~ label ~ "; if (true) {} else " ~ label ~ ":" ~ endcomment ~ "\n";
		endtok.type = Token.PPinsert;

		version(remove_else)
		{
			// remove "else"
			TokenIterator startIt = start;
			TokenIterator endIt = end;
			TokenIterator newStartIt = start + 1;
			TokenIterator newEndIt = end + 1;
        		
			fixIterator(startIt, newStartIt);
			fixIterator(endIt, newEndIt);
			startIt.erase();
			endIt.erase();
		}
		else
		{
			// convert "else" to comment
			start.text = "/*else*/";
			start.type = Token.Comment;
			end.text = "/*else*/";
			end.type = Token.Comment;
		}
	}

	void convertMultipleElseIf()
	{
		assert("not implemented");
	}

	void convertMultipleOpenElseIf()
	{
		// convert
		//   if (x)
		//     c = 0;
		// #if COND1 // comment
		//   else if (a)
		// #elif COND2
		//   else if (b)
		// #endif
		//     c = 1;
		//
		// to
		//   if (x)
		//     c = 0;
		// else __static_if(COND1) // comment
		//   /*else*/ if (a)
		// goto L_T3; else goto L_F3; else __static_if(COND2)
		//   /*else*/ if (b)
		// goto L_T3; else goto L_F3; else L_F3: if(0) L_T3:
		//     c = 1;

		int lineno = -1;
		for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
		{
		    it.convertOneOpenElseIf(lineno);
		}

		string slineno = format("%d", lineno);
		Token endtok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endtok, endcondition, endcomment);
		endtok.text = "goto L_T" ~ slineno ~ "; else goto L_F" ~ slineno ~ "; else goto L_T" ~ slineno ~ "; "
		            ~ "else L_F" ~ slineno ~ ": if(0) L_T" ~ slineno ~ ":" ~ endcomment ~ "\n";
		endtok.type = Token.PPinsert;
	}

	void convertOneOpenElseIf(ref int lineno)
	{
		assert(start.text == "else");
		Token starttok = start[-1];

		string condition, comment;
		splitPPCondition(starttok, condition, comment);
		string txt;
		bool first = lineno < 0;
		if(first)
		{
			lineno = starttok.lineno;
			txt ~= "else if(true)";
		}
		else
		{
			string slineno = format("%d", lineno);
			txt ~= "goto L_T" ~ slineno ~ "; else goto L_F" ~ slineno ~ "; else";
		}
		if(condition.length == 0)
			condition = "true";
		txt ~= " " ~ createStaticIf(condition);
		txt ~= comment ~ "\n";
		starttok.text = txt;
		starttok.type = Token.PPinsert;
		start.text = "/*else*/";
		start.type = Token.PPinsert;
	}

	///////////////////////////////////////////////////////
	// if outside, && and || are expected outside the conditional
	bool isSubExpressionOperator(int type)
	{
		switch(type)
		{
		case Token.Or:
		case Token.Ampersand:
		case Token.OrOr:
		case Token.AmpAmpersand:
			return true;
		default:
			return false;
		}
	}
	string subExpressionOperatorText(int type)
	{
		switch(type)
		{
		case Token.Or:           return "|";
		case Token.Ampersand:    return "&";
		case Token.OrOr:         return "||";
		case Token.AmpAmpersand: return "&&";
		default:
			return "";
		}
	}
	string subExpressionOperatorDefault(int type)
	{
		switch(type)
		{
		case Token.Or:           return "0";
		case Token.Ampersand:    return "-1";
		case Token.OrOr:         return "false";
		case Token.AmpAmpersand: return "true";
		default:
			return "";
		}
	}

	int subConditionOperator(bool outside)
	{
		if(outside)
		{
			if(start.atBegin() || (start - 1).atBegin())
				return -1;
		}
		int off = outside ? 2 : 0;
		if(isSubExpressionOperator(start[0 - off].type))
			return start[0 - off].type;
		if(!(end - 2 + off).atEnd() && isSubExpressionOperator(end[-2 + off].type))
			return end[-2 + off].type;
		return -1;
	}
		
	void convertOneSubCondition(ref string conditions, bool outside, int type)
	{
		if(!outside && subConditionOperator(outside) < 0)
			throwException(start.lineno, "different expression syntax in conditionals");

		int off = outside ? 2 : 0;
		TokenIterator it = start;
		TokenIterator eit = end - 2;
		if(outside)
			++eit;
		else
		{
			type = it[-off].type;
			bool front = isSubExpressionOperator(type);
			if(!front)
				type = end[off-2].type;
		
			if(front)
			{
				++it;
				++eit;
			}
		}

		Token iftok = start[-1];
		string condition, comment;
		splitPPCondition(iftok, condition, comment);

		if(comment.length > 0)
			iftok.text = comment ~ "\n";
		else
			iftok.text = "";
		iftok.type = Token.PPinsert;
		
		string cond;
		bool first = conditions.length == 0;
		if(!first)
			cond = "!(" ~ conditions ~ ")";

		if(condition.length > 0 && cond.length > 0)
			cond ~= " && " ~ condition;
		else if(condition.length > 0)
			cond = condition;
		
		if(condition.length > 0 && conditions.length > 0)
			conditions ~= " || " ~ condition;
		else
			conditions = condition;

		string def = subExpressionOperatorDefault(type);
		string txt = "__static_eval(" ~ cond ~ ", " ~ def ~ ")(";
		if(outside && !first)
			txt = subExpressionOperatorText(type) ~ " " ~ txt;
		it.insertBefore(createToken(it.pretext, txt, Token.PPinsert, it.lineno));
		it.pretext = "";
		
		eit.insertBefore(createToken("", ")", Token.ParenR, (*eit).lineno));
	}

	void convertSubCondition(bool outside)
	{
		string conditions;
		int type;
		if(outside)
			type = subConditionOperator(outside);

		assert(children);
		for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
		{
			it.convertOneSubCondition(conditions, outside, type);
		}

		Token endiftok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endiftok, endcondition, endcomment);

		endiftok.text = endcomment.length > 0 ? endcomment ~ "\n" : "";
		endiftok.type = Token.PPinsert;
	}

	///////////////////////////////////////////////////////
	void convertOneIfElifElseEndif(string prefix, string condprefix)
	{
		Token starttok = start[-1];
		string condition, comment;
		splitPPCondition(starttok, condition, comment);

		if (condition == "")
			starttok.text = prefix ~ "{" ~ comment ~ "\n";
		else
			starttok.text = prefix ~ createStaticIf(condprefix ~ condition) ~ " {" ~ comment ~ "\n";
		starttok.type = Token.PPinsert;
	}

	void convertStandardIfElifElseEndif(string condprefix)
	{
		string prefix;
		bool moveElse = (start.type == Token.Else);
		if(moveElse)
			prefix = "else ";

		assert(children);
		for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
		{
			it.convertOneIfElifElseEndif(prefix, condprefix);
			prefix = "} else ";
		}

		Token endiftok = end[-1];
		string endcondition, endcomment;
		splitPPCondition(endiftok, endcondition, endcomment);

		endiftok.text = "}" ~ endcomment ~ "\n";
		endiftok.type = Token.PPinsert;

		if(moveElse)
		{
			start.text = "/*else*/";
			start.type = Token.PPinsert;
		}
	}

	///////////////////////////////////////////////////////
	bool isExpandableSection()
	{
		if(!conditional)
		{
			// check whether this is the first and only section of a conditional (no #elif/#else)
			return false;
		}

		Token iftok = start[-1];
		string ident, comment;
		int ntokens = splitPPCondition(iftok, ident, comment);

		if(ntokens == 1)
		   if(auto p = ident in PP.expandConditionals)
			   return *p;

		return false;
	}
	void expandSection()
	{
		start[-1].text = "// " ~ start[-1].text;
		start[-1].type = Token.PPinsert;

		TokenIterator stop = end - 1;
		if(children.count() > 1)
		{
			for(TokenIterator it = children[1].start - 1; !it.atEnd() && it != stop; ++it)
			{
				it.text = "";
				it.type = Token.PPinsert;
			}
		}
		stop.text = "// " ~ stop.text;
		stop.type = Token.PPinsert;
	}
	///////////////////////////////////////////////////////
	bool isRemovableSection()
	{
		Token iftok = start[-1];
		string ident, comment;
		int ntokens = splitPPCondition(iftok, ident, comment);

		if((ident == "__DMC__" || ident == "__SC__") && startsWith(start[0].text, "#pragma once") && end == start + 2)
			return true;
		if(ntokens == 1)
			if(auto p = ident in PP.expandConditionals)
				return !*p;

		return false;
	}
	void removeSection()
	{
		end.pretext = start[-1].pretext ~ end.pretext;
		for(TokenIterator it = start - 1; !it.atEnd() && it != end; ++it)
		{
			it.text = "";
			it.type = Token.PPinsert;
		}
	}

	///////////////////////////////////////////////////////
	bool isRemovableIfndef(string ident)
	{
		if(endsWith(ident, "_H"))
			return true;
		return false;
	}
	bool isVersionDefine(string ident)
	{
		return (ident in PP.versionDefines) !is null;
	}

	void convertIfndef()
	{
		Token iftok = start[-1];
		string ident, comment;
		splitPPCondition(iftok, ident, comment);

		Token endiftok = end[-1];
		string endident, endcomment;
		splitPPCondition(endiftok, endident, endcomment);

		if(isRemovableIfndef(ident))
		{
			if(children.count() != 1)
				throwException(iftok.lineno, "unexpected #else with #ifndef " ~ ident);
			iftok.text = comment ~ (comment.length ? "\n" : "");
			if(start.type == Token.PPdefine)
			{
				string deftext, defcomment;
				splitPPCondition(start[0], deftext, defcomment);
				if (startsWith(deftext,ident))
				{
					start.text = "";
					start.type = Token.PPinsert;
				}
			}
			endiftok.text = endcomment.length > 0 ? endcomment ~ "\n" : "";
		}
		else if(isVersionDefine(ident))
		{
			if(children.count() != 1)
				throwException(iftok.lineno, "unsupported #else with #ifndef " ~ ident);
			iftok.text = "__version (" ~ ident ~ ") {} else {" ~ comment ~ "\n";
			endiftok.text = "}" ~ endcomment ~ "\n";
		}
		else
		{
			// treat as #if expreession
			convertStandardIfElifElseEndif("!");
			return;
		}
		iftok.type = Token.PPinsert;
		endiftok.type = Token.PPinsert;
	}

	void convertIfdef()
	{
		Token iftok = start[-1];
		string ident, comment;
		splitPPCondition(iftok, ident, comment);

		Token endiftok = end[-1];
		string endident, endcomment;
		splitPPCondition(endiftok, endident, endcomment);

		if(ident == "__DMC__" && startsWith(start[0].text, "#pragma once") && end == start + 3)
		{
			// completely remove section (obsolete? also covered by isRemovableSection?
		}
		if(isVersionDefine(ident))
		{
			if(children.count() > 2)
				throwException(iftok.lineno, "unsupported #elif with #ifndef " ~ ident);
			iftok.text = "__version (" ~ ident ~ ") {" ~ comment ~ "\n";
			endiftok.text = "}" ~ comment ~ "\n";

			if(children.count() == 2)
			{
				Token elsetok = children.begin()[1].start[-1];
				string elseident, elsecomment;
				splitPPCondition(elsetok, elseident, elsecomment);
				elsetok.text = "} else {" ~ comment ~ "\n";
				elsetok.type = Token.PPinsert;
			}
			iftok.type = Token.PPinsert;
			endiftok.type = Token.PPinsert;
		}
		else
		{
			// treat as #if expreession
			convertStandardIfElifElseEndif("");
		}
	}

	//////////////////////////////////////////////////////////////////////////////
	void fixConditionalIf()
	{
		if(isRemovableSection())
		{
			removeSection();
			return;
		}
		if(isExpandableSection())
		{
			expandSection();
			return;
		}

		bool hasOpen = false;
		bool startWithElse = true; // all children start with "else"?
		if(children)
			for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
			{
				startWithElse = startWithElse && (it.start.type == Token.Else);
				hasOpen = hasOpen || it.hasOpenIf() || it.hasOpenElse();
			}

		if (hasOpen)
		{
			if(startWithElse)
				convertMultipleOpenElseIf();
			else if(children.count() == 1)
				// simple #if / #endif
				convertSingleOpenIf();
			else
				convertMultipleOpenIf();
		}
		else if (isInElseIfSeries())
		{
			if(children.count() == 1)
				// single #if / #endif
				convertSingleElseIf();
			else
				convertMultipleElseIf();
		}
		else if (subConditionOperator(false) >= 0)
		{
			convertSubCondition(false);
		}
		else if (subConditionOperator(true) >= 0)
		{
			convertSubCondition(true);
		}
		else if (start[-1].type == Token.PPif)
		{
			// convert standard #if/#elif/#else/#endif
			convertStandardIfElifElseEndif("");
		}
		else if (start[-1].type == Token.PPifndef)
		{
			convertIfndef();
		}
		else if (start[-1].type == Token.PPifdef)
		{
			convertIfdef();
		}
	}

	void fixConditionalCompilation()
	{
		// fix children first to get balanced brackets
		if(children)
			for(DListIterator!(ConditionalCode) it = children.begin(); !it.atEnd(); ++it)
				it.fixConditionalCompilation();

		if(conditional)
			fixConditionalIf();
	}

	//////////////////////////////////////////////////////////////////////////////
	TokenIterator start; // first token after #if line
	TokenIterator end;   // token after last token (after #endif)

	DList!(ConditionalCode) children;
	ConditionalCode parent;
	bool conditional;
}

//////////////////////////////////////////////////////////////////////////////
class PP
{
	void parseModule(TokenList tokenlist)
	{
		root = new ConditionalCode(false, null);
		TokenIterator tokIt = tokenlist.begin();
		root.parseCode(tokIt);
		if(!tokIt.atEnd())
		    throw new Exception("mismatched #if/#endif");
	}

	// works on token array
	void fixConditionalCompilation(TokenList tokenList)
	{
		parseModule(tokenList);

		root.fixConditionalCompilation();
	}


	void convertDefinesToEnums(TokenList tokenList)
	{
		for(TokenIterator tokIt = tokenList.begin(); !tokIt.atEnd(); ++tokIt)
			if(tokIt.type == Token.PPdefine)
			{
				string enumtext = convertDefineToEnum(tokIt.text, null);
				if(enumtext != tokIt.text)
				{
					tokIt.type = Token.PPinsert;
					tokIt.text = enumtext;
				}
			}
	}

	ConditionalCode root;

	static bool[string] versionDefines;
	static bool[string] expandConditionals;
}

///////////////////////////////////////////////////////////////////////
void rescanPP(TokenList srcTokenList)
{
	for(TokenIterator tokIt = srcTokenList.begin(); !tokIt.atEnd(); )
	{
		Token tok = *tokIt;
		if(tok.type == Token.PPinsert)
		{
			TokenList tokenList = scanText(tok.text, tok.lineno);
			while(!tokenList.empty() && tokenList.end()[-1].text == "")
			{
				TokenIterator endIt = tokenList.end() - 1;
				if(!(tokIt + 1).atEnd())
					tokIt[1].pretext = endIt.pretext ~ tokIt[1].pretext;
				endIt.erase();
			}

			srcTokenList.insertListAfter(tokIt, tokenList);
			tokIt[1].pretext = tokIt.pretext ~ tokIt[1].pretext;
			tokIt.erase(); // skips to next token
		}
		else if(tokIt.type == Token.EOF)
		{
			if(!(tokIt + 1).atEnd())
			{
				tokIt[1].pretext = tokIt.pretext ~ tokIt[1].pretext;
				tokIt.erase();
			}
			else
				tokIt.advance();
		}
		else
			tokIt.advance();
	}		
}

///////////////////////////////////////////////////////////////////////

string convertDefineToEnum(string deftext, string function(string) fixNumber)
{
	TokenList tokList = scanText(deftext, 1, false);
	TokenIterator it = tokList.begin();
	assert(it.type == Token.PPdefine);
	it.advance();
	if(!it.atEnd() && it.type == Token.Identifier)
	{
		it.advance();
		if(!it.atEnd() && it.type == Token.Number)
		{
			it.advance();
			if(it.atEnd() || it.type == Token.EOF)
			{
				string numtext = it[-1].text;
				if(fixNumber)
					numtext = fixNumber(numtext);
				string text = "enum { " ~ it[-2].text ~ " = " ~ numtext ~ " };";
				if(!it.atEnd())
					text ~= it.pretext;
				return text;
			}
		}
	}
	return deftext;
}

///////////////////////////////////////////////////////////////////////

bool staticEval(bool COND)() 
{
	static if(COND)
		return true;
	else
		return false;
}

bool staticEval(bool COND, bool DEF)(lazy bool b) 
{
	static if(COND)
		return b;
	else
		return DEF;
}

// version = EVAL;

unittest
{
// translate
//
//   if(a)
//      exec_a;
// #if COND
//   else if (b)
//      exec_b;
// #endif
//   else if (c)
//      exec_c;

	int fn(bool COND)(bool a, bool b, bool c)
	{
		int x = 0;

version(EVAL) {
		if(a)
			x = 1;
		else if (staticEval!(COND, false)(b))
			x = 2;
		else if(c)
			x = 3;
} 
version(x) { // !EVAL
		if(a)
			x = 1;
		else 
			goto L_C1;
		goto L_C2;
L_C1:
static if (COND) {
		if (b)
			x = 2;
		else
			goto L_C3;
		goto L_C2;
}
L_C3:		if(false) L_C2: {}
		else if (c)
			x = 3;
}
version(0) {
		if(a)
			x = 1;
		else static if(COND) 
		if (b)
			x = 2;
		else goto L_C1; else goto L_C1;
		if(true) {} else L_C1: 
		if(c)
			x = 3;

		return x;
}
	}

	assert(fn!(true)(false, false, false) == 0);
	assert(fn!(true)(false, false, true)  == 3);
	assert(fn!(true)(false, true,  false) == 2);
	assert(fn!(true)(false, true,  true)  == 2);
	assert(fn!(true)(true,  false, false) == 1);
	assert(fn!(true)(true,  false, true)  == 1);
	assert(fn!(true)(true,  true,  false) == 1);
	assert(fn!(true)(true,  true,  true)  == 1);

	assert(fn!(false)(false, false, false) == 0);
	assert(fn!(false)(false, false, true)  == 3);
	assert(fn!(false)(false, true,  false) == 0);
	assert(fn!(false)(false, true,  true)  == 3);
	assert(fn!(false)(true,  false, false) == 1);
	assert(fn!(false)(true,  false, true)  == 1);
	assert(fn!(false)(true,  true,  false) == 1);
	assert(fn!(false)(true,  true,  true)  == 1);
}

unittest
{
// translate
//
//   if(a)
//      exec_a;
// #if COND
//   else
//      exec_not_a;
// #endif

	int fn(bool COND)(bool a)
	{
		int x = 0;

version(EVAL) {
		if(a)
			x = 1;
		else if (staticEval!(COND)()) // braces needed if else follows
		{
			x = 2;
		}
} else { // !EVAL
		if(a)
			x = 1;
		else // trailing else must be moved before static if!
static if (COND) { 
			x = 2;
}
} // !EVAL
		return x;
	}

	assert(fn!(true)(false)  == 2);
	assert(fn!(true)(true)   == 1);
	assert(fn!(false)(false) == 0);
	assert(fn!(false)(true)  == 1);
}

unittest
{
// translate
//
// #if COND
//   if(a1)
// #else
//   if(a2)
// #endif
//      exec_a;
//   else
//      exec_not_a;

	int fn(bool COND)(bool a1, bool a2)
	{
		int x = 0;

static if (COND) { 
		bool cond = a1;
} else {
		bool cond = a2;
}	
		if(cond)
			x = 1;
		else
			x = 2;
		return x;
	}

	assert(fn!(true)(false, false)  == 2);
	assert(fn!(true)(false, true)   == 2);
	assert(fn!(true)(true,  false)  == 1);
	assert(fn!(true)(true,  true)   == 1);

	assert(fn!(false)(false, false)  == 2);
	assert(fn!(false)(false, true)   == 1);
	assert(fn!(false)(true,  false)  == 2);
	assert(fn!(false)(true,  true)   == 1);
}

unittest
{
// translate
//
// #if COND
//   if(a)
// #endif
//      exec_a;

	int fn(bool COND)(bool a)
	{
		int x = 0;

static if (COND) { 
		if(!a)
			goto L_notcond;
}	
			x = 1;
L_notcond:;
		return x;
	}

	assert(fn!(true)(false)  == 0);
	assert(fn!(true)(true)   == 1);
	assert(fn!(false)(false)  == 1);
	assert(fn!(false)(true)   == 1);
}

unittest
{
// translate
//
// #if COND
//   exec;
//   if(a)
//      exec_if;
//   else
// #endif
//      exec_else;

	int fn(bool COND)(bool a)
	{
		int x = 0;

static if (COND) { 
		x = 1;
		if(a)
		{
			x = 2;
			goto L_notcond;
		}
}
		x = 3;
L_notcond:;
		return x;
	}

	assert(fn!(true)(false)  == 3);
	assert(fn!(true)(true)   == 2);
	assert(fn!(false)(false)  == 3);
	assert(fn!(false)(true)   == 3);
}

unittest
{
// translate
//
//   if(a
// #if COND
//      && b
// #endif
//      && c)
//      exec;

	int fn(bool COND)(bool a, bool b, bool c)
	{
		int x = 0;

		if(a 
		    && staticEval!(COND, true)(b) 
		    && c)
			x = 1;
		return x;
	}

	assert(fn!(true)(false, false, false) == 0);
	assert(fn!(true)(false, false, true)  == 0);
	assert(fn!(true)(false, true,  false) == 0);
	assert(fn!(true)(false, true,  true)  == 0);
	assert(fn!(true)(true,  false, false) == 0);
	assert(fn!(true)(true,  false, true)  == 0);
	assert(fn!(true)(true,  true,  false) == 0);
	assert(fn!(true)(true,  true,  true)  == 1);

	assert(fn!(false)(false, false, false) == 0);
	assert(fn!(false)(false, false, true)  == 0);
	assert(fn!(false)(false, true,  false) == 0);
	assert(fn!(false)(false, true,  true)  == 0);
	assert(fn!(false)(true,  false, false) == 0);
	assert(fn!(false)(true,  false, true)  == 1);
	assert(fn!(false)(true,  true,  false) == 0);
	assert(fn!(false)(true,  true,  true)  == 1);
}

unittest
{
	int x = 0;
	//goto label;
	if(true)
		x = 1;
	else
label:	{	x = 2; }

	assert(x == 1);
}

unittest
{
// translate
//   if (a)
//     x = 1;
// #if COND1
//   else if (b)
// #elif COND2
//   else if (c)
// #endif
//     x = 2;

	int fn(bool COND1, bool COND2)(bool a, bool b, bool c)
	{
		int x = 0;

		if (a)
			x = 1;
		else if(true)
			static if(COND1)
		/*else*/        if (b)
					goto L_C3; 
				else 
					goto L_N3; 
			else static if(COND2)
		/*else*/        if (c)
					goto L_C3; 
				else 
					goto L_N3;
			else
				goto L_C3;
		else
L_N3:
			if(false)
L_C3:
				x = 2;

		return x;
	}

	void verify(bool COND1,bool COND2)(bool a, bool b, bool c)
	{
		int exp = a != 0 ? 1 : ((COND1 && b) || (!COND1 && COND2 && c) || (!COND1 && !COND2)) ? 2 : 0;
		int res = fn!(COND1,COND2)(a, b, c);
		assert(res == exp);
	}

	void verify8(bool COND1,bool COND2)()
	{
		verify!(COND1,COND2)(false, false, false);
		verify!(COND1,COND2)(false, false, true);
		verify!(COND1,COND2)(false, true,  false);
		verify!(COND1,COND2)(false, true,  true);
		verify!(COND1,COND2)(true,  false, false);
		verify!(COND1,COND2)(true,  false, true);
		verify!(COND1,COND2)(true,  true,  false);
		verify!(COND1,COND2)(true,  true,  true);
	}

	verify8!(false,false)();
	verify8!(false,true)();
	verify8!(true,false)();
	verify8!(true,true)();
}

///////////////////////////////////////////////////////////////////////

string testPP(string txt)
{
	TokenList list = scanText(txt);
	PP pp = new PP;
	pp.fixConditionalCompilation(list);
	string res = tokenListToString(list);
	return res;
}

unittest
{
	string txt = 
		"  a = 1;\n"
		"#if COND\n"
		"  b = 2;\n"
		"#endif\n"
		"  c = 3;\n"
		;

	string exp =
		"  a = 1;\n"
		"__static_if(COND) {\n"
		"  b = 2;\n"
		"}\n"
		"  c = 3;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"#if COND\n"
		"  if(a)\n"
		"#endif\n"
		"    b = 1;\n"
		;

	string exp = 
		"__static_if(!COND) goto L_F1;\n"
		"  if(a)\n"
		"L_F1:\n"
		"    b = 1;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"#if COND1 // comment\n"
		"  if (a)\n"
		"#elif COND2\n"
		"  if (b)\n"
		"#endif\n"
		"    c = 1;\n"
		;

	string exp = 
		"bool cond_1;\n"
		"__static_if(COND1) { // comment\n"
		"  cond_1 = (a);\n"
		"} else __static_if(COND2) {\n"
		"  cond_1 = (b);\n"
		"}\n"
		"    if (cond_1) c = 1;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"  if (x)\n"
		"    c = 0;\n"
		"#if COND1 // comment\n"
		"  else if (a)\n"
		"#elif COND2\n"
		"  else if (b)\n"
		"#endif\n"
		"    c = 1;\n"
		;

	string exp = 
		"  if (x)\n"
		"    c = 0;\n"
		"else if(true) __static_if(COND1) // comment\n"
		"  /*else*/ if (a)\n"
		"goto L_T3; else goto L_F3; else __static_if(COND2)\n"
		"  /*else*/ if (b)\n"
		"goto L_T3; else goto L_F3; else goto L_T3; else L_F3: if(0) L_T3:\n"
		"    c = 1;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"  if (a)\n"
		"    c = 1;\n"
		"#if COND\n"
		"  else if (b)\n"
		"    c = 2;\n"
		"#endif\n"
		;

	string exp = 
		"  if (a)\n"
		"    c = 1;\n"
		"else __static_if(COND) {\n"
		"  /*else*/ if (b)\n"
		"    c = 2;\n"
		"}\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"#if COND1 // comment\n"
		"  if (a)\n"
		"#elif COND2\n"
		"  if (b)\n"
		"    c = 0;\n"
		"  else\n"
		"#endif\n"
		"    c = 1;\n"
		;

	string exp = 
		"bool cond_1;\n"
		"__static_if(COND1) { // comment\n"
		"  cond_1 = (a);\n"
		"} else __static_if(COND2) {\n"
		"  if (b)\n"
		"    c = 0;\n"
		"  else\n"
		"cond_1 = true;\n"  // todo: fix indentation
		"}\n"
		"    if (cond_1) c = 1;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"  if (a1)\n"
		"    c = 0;\n"
		"#if COND // comment\n"
		"  else if (a2)\n"
		"    c = 1;\n"
		"#endif\n"
		"  else if (a3)\n"
		"    c = 2;\n"
		;

	string exp = 
		"  if (a1)\n"
		"    c = 0;\n"
		"else __static_if(COND) // comment\n"
		"  /*else*/ if (a2)\n"
		"    c = 1;\n"
		"else goto L_F3; else goto L_F3; if (true) {} else L_F3:\n"
		"  /*else*/ if (a3)\n"
		"    c = 2;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"  if (a1\n"
		"#if COND1\n"
		"      && a2\n"
		"#elif COND2\n"
		"      && b2\n"
		"#endif\n"
		"      && a3)\n"
		"    c = 2;\n"
		"\n"
		"  if (a1 ||\n"
		"#if COND1\n"
		"      a2 ||\n"
		"#elif COND2\n"
		"      b2 ||\n"
		"#endif\n"
		"      a3)\n"
		"    c = 2;\n"
		;

	string exp = 
		"  if (a1\n"
		"      && __static_eval(COND1, true)(a2)\n"
		"      && __static_eval(!(COND1) && COND2, true)(b2)\n"
		"      && a3)\n"
		"    c = 2;\n"
		"\n"
		"  if (a1 ||\n"
		"      __static_eval(COND1, false)(a2) ||\n"
		"      __static_eval(!(COND1) && COND2, false)(b2) ||\n"
		"      a3)\n"
		"    c = 2;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"  if (a1 &&\n"
		"#if COND1\n"
		"      a2\n"
		"#elif COND2\n"
		"      b2\n"
		"#endif\n"
		"      )\n"
		"    c = 2;\n"
		"\n"
		"  if (a1 ||\n"
		"#if COND1\n"
		"      a2\n"
		"#elif COND2\n"
		"      b2\n"
		"#endif\n"
		"      || a3)\n"
		"    c = 2;\n"
		;

	string exp = 
		"  if (a1 &&\n"
		"      __static_eval(COND1, true)(a2)\n"
		"      && __static_eval(!(COND1) && COND2, true)(b2)\n"
		"      )\n"
		"    c = 2;\n"
		"\n"
		"  if (a1 ||\n"
		"      __static_eval(COND1, false)(a2)\n"
		"      || __static_eval(!(COND1) && COND2, false)(b2)\n"
		"      || a3)\n"
		"    c = 2;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"#ifndef HDR_H\n"
		"#define HDR_H\n"
		"    a = 0;\n"
		"#endif\n"
		;

	string exp = 
		"    a = 0;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
		"    a = 0;\n"
		"#ifdef __DMC__\n"
		"#pragma once\n"
		"#endif\n"
		"    b = 0;\n"
		;

	string exp = 
		"    a = 0;\n"
		"\n"
		"    b = 0;\n"
		;

	string res = testPP(txt);
	assert(res == exp);
}

