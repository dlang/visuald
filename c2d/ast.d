// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module c2d.ast;

import c2d.tokenizer;
import c2d.dlist;
import c2d.dgutil;
import c2d.tokutil;

import std.conv;

//////////////////////////////////////////////////////////////////////////////

debug = VERIFY;
//debug = TOKENTEXT;

bool tryRecover = true;
int syntaxErrors;
string syntaxErrorMessages;

// how to handle identifier in declaration
enum IdentPolicy
{
	SingleMandantory,   // not used
	SingleOptional,
	MultipleMandantory, // at least one must exist
	MultipleOptional,
	Prohibited
}

struct ToStringData
{
	// options
	bool noIdentifierInPrototype;
	bool addScopeToIdentifier;
	bool addClassPrefix;
	bool addEnumPrefix;
	bool addArgumentDefaults;
	bool addFunctionBody;
	// state variables
	bool inDeclarator;
	bool inPrototype;
}

alias DList!(AST) ASTList;
alias DListIterator!(AST) ASTIterator;

class AST
{
	enum Type
	{
		// decl-children: DeclarationGroup, ConditionalDeclaration, Declaration, mixin-Expression, Protection
		Module,                    // decl-children
		Statement,
		Declaration,               // children: TypeDeclaration, VarDeclaration*
		Protection,
		CtorInitializer,
		CtorInitializers,
		TypeDeclaration,
		EnumDeclaration,
		VarDeclaration,            // children: declarator Expression, init Expression
		ConditionalDeclaration,    // static if or version on declaration level
		DeclarationGroup,          // non-scoped group of declarations in conditional

		PrimaryExp,
		PostExp,
		UnaryExp,
		BinaryExp,
		CondExp,
		CastExp,                   // child0: decl, child1: expression
		EmptyExp,                  // third arg in for

		PPLine,
	}

	this(Type type)
	{
		_type = type;
	}

	void addChild(AST ast)
	{
		if(!children)
			children = new DList!(AST);
		children.append(ast);
		ast._parent = this;
	}

	//////////////////////////////////////////////////////////////
	void insertChildBefore(ASTIterator it, AST ast, TokenList toklist, TokenIterator* pInsertPos = null)
	{
		bool insertAtStart = !children || children.empty();
		if(!children)
		{
			children = new DList!(AST);
			children.append(ast);
			it = children.end();
		}
		else
			it.insertBefore(ast);
		ast._parent = this;

		// it on child after inserted ast
		TokenIterator insertPos;
		if(pInsertPos)
			insertPos = *pInsertPos;
		else if(insertAtStart)
			insertPos = defaultInsertStartTokenPosition();
		else if (it.atEnd())
			insertPos = defaultInsertEndTokenPosition();
		else
			insertPos = it.start;
		insertPos.insertListBefore(toklist); // insertPos now points after inserted token list

		ast.fixIteratorList(start.getList());

		if(ast.start != ast.end)
		{
			if(AST prev = ast.prevSibling())
				fixIteratorChildrenEnd(prev, insertPos, ast.start);
			else
				fixIteratorParentsStart(this, insertPos, ast.start);

			if(AST next = ast.nextSibling())
				fixIteratorChildrenEnd(ast, ast.end, insertPos);
			else
				fixIteratorChildrenEnd(ast, ast.end, insertPos);
		}
		debug(TOKENTEXT) verify();
	}

	void appendChild(AST ast, TokenList toklist)
	{
		ASTIterator it;
		if(children)
			it = children.end();
		insertChildBefore(it, ast, toklist);
	}

	void prependChild(AST ast, TokenList toklist)
	{
		ASTIterator it;
		if(children)
			it = children.begin();
		insertChildBefore(it, ast, toklist);
	}

	TokenList removeChild(AST ast, bool keepComments = false)
	{
		assume(children && ast._parent == this);
		ASTIterator it = children.find(ast);
		assume(!it.atEnd());

		TokenIterator end = ast.end;
		if(keepComments)
		{
			while(ast.start != end)
			{
				if(!isCommentToken(end[-1]))
					break;
				end.retreat();
			}
		}
		if(ast.start != end)
		{
			if(AST prev = ast.prevSibling())
				fixIteratorChildrenEnd(prev, ast.start, end);
			else
				fixIteratorParentsStart(this, ast.start, end);
		}

		TokenList list = (ast.start + 0).eraseUntil(end);
		fixIteratorChildrenEnd(ast, ast.end, list.end());

		it.erase();
		ast.fixIteratorList(list);
		ast._parent  = null;

		debug(TOKENTEXT) verify();
		return list;
	}

	int countChildren()
	{
		if(!children)
			return 0;
		return children.count();
	}

	ASTIterator childrenBegin()
	{
		if(!children)
			return ASTIterator();
		return children.begin();
	}

	//////////////////////////////////////////////////////////////
	void insertTokenListBefore(AST child, TokenList toklist)
	{
		assume(true || child._parent is this);

		TokenIterator insertPos;
		if(!child)
			insertPos = end;
		else
			insertPos = child.start;
		TokenIterator begIt = insertPos.insertListBefore(toklist);

		if(child)
			if(AST prev = child.prevSibling())
				fixIteratorChildrenEnd(prev, insertPos, begIt);

		fixIteratorParentsStart(this, insertPos, begIt);
	}

	void insertTokenBefore(AST child, Token tok)
	{
		TokenList toklist = new TokenList;
		toklist.append(tok);
		insertTokenListBefore(child, toklist);
	}

	void removeToken(TokenIterator removeIt)
	{
		AST prevChild;

		void _removeToken()
		{
			if(prevChild)
				fixIteratorChildrenEnd(prevChild, removeIt, removeIt + 1);
			fixIteratorParentsStart(this, removeIt, removeIt + 1);
			removeIt.erase();
		}

		TokenIterator tokIt = start;
		if(children)
		{
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
			{
				for( ; tokIt != it.start; ++tokIt)
					if(removeIt == tokIt)
					{
						_removeToken();
						return;
					}
				tokIt = it.end;
				prevChild = *it;
			}
		}
		for( ; tokIt != end; ++tokIt)
			if(removeIt == tokIt)
			{
				_removeToken();
				return;
			}

		assume(false, "token not part of AST");
	}

	void removeToken(int toktype)
	{
		TokenIterator tokIt = start;
		while(tokIt != end && tokIt.type != toktype)
			tokIt.advance();

		if(tokIt != end)
			removeToken(tokIt);
	}

	//////////////////////////////////////////////////////////////
	AST prevSibling()
	{
		if(!_parent)
			return null;
		
		assume(_parent.children, "inconsistent AST");
		ASTIterator it = _parent.children.begin();
		if(it.atEnd() || *it is this)
			return null;

		for(++it; !it.atEnd(); ++it)
			if(*it is this)
				return it[-1];

		assume(false, "inconsistent AST");
		return null;
	}

	AST nextSibling()
	{
		if(!_parent)
			return null;
		
		assume(_parent.children, "inconsistent AST");
		
		ASTIterator it = _parent.children.find(this);
		assume(!it.atEnd(), "inconsistent AST");
		
		++it;
		if(it.atEnd())
			return null;
		return *it;
	}

	static void fixIteratorChildrenEnd(AST ast, TokenIterator end, TokenIterator newEnd)
	{
		while(ast && ast.end == end)
		{
			if(ast.children && !ast.children.empty())
				fixIteratorChildrenEnd(ast.children.end()[-1], end, newEnd);
			ast.end = newEnd;

			if(ast.start != end)
				break;

			ast.start = newEnd;
			ast = ast.prevSibling();
		}
	}

	static void fixIteratorParentsStart(AST ast, TokenIterator start, TokenIterator newStart)
	{
		while(ast && start == ast.start)
		{
			if(AST prev = ast.prevSibling())
				fixIteratorChildrenEnd(prev, start, newStart);
			if(ast._parent)
				fixIteratorParentsStart(ast._parent, start, newStart);
			ast.start = newStart;

			if(ast.end != start)
				break;

			ast = ast.nextSibling();
		}
	}

	void fixIteratorList(TokenList list)
	{
		start.setList(list);
		end.setList(list);

		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
				it.fixIteratorList(list);
	}

	//////////////////////////////////////////////////////////////
	void verifyIteratorList(ref TokenIterator tokIt)
	{
		if(tokIt.getList() != start.getList())
			assume(tokIt.getList() == start.getList());

		debug(TOKENTEXT) toktext = tokenListToString(start, end);

		while(tokIt != start)
			tokIt.advance();
		
		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
				it.verifyIteratorList(tokIt);

		assume(tokIt.getList() == end.getList());
		while(tokIt != end)
			tokIt.advance();
	}

	void verifyChildren()
	{
		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
			{
				assume(it._parent is this);
				it.verifyChildren();
			}
	}

	final void verify()
	{
		debug(VERIFY)
		{
			TokenIterator tokIt = start;
			verifyIteratorList(tokIt);

			verifyChildren();
		}
	}

	//////////////////////////////////////////////////////////////
	AST getRoot()
	{
		AST ast = this;
		while(ast._parent)
			ast = ast._parent;
		return ast;
	}

	TokenIterator defaultInsertStartTokenPosition()
	{
		return start;
	}

	TokenIterator defaultInsertEndTokenPosition()
	{
		return end;
	}

	static void recoverFromSyntaxError(Exception e, ref TokenIterator tokIt)
	{
		if(!tryRecover)
			throw e;

		syntaxErrors++;
		syntaxErrorMessages ~= "$FILENAME$" ~ e.msg ~ "\n";
		if(!tokIt.atEnd())
			tokIt.pretext ~= " /* SYNTAX ERROR: " ~ e.msg ~ " */ ";

		while(!tokIt.atEnd() && tokIt.type != Token.EOF && 
			   tokIt.type != Token.BraceR && tokIt.type != Token.Semicolon)
			nextToken(tokIt);
		if(!tokIt.atEnd() && tokIt.type == Token.Semicolon)
			nextToken(tokIt);
	}

	//////////////////////////////////////////////////////////////////////
	AST parseProtection(ref TokenIterator tokIt)
	{
		AST prot = new AST(Type.Protection);
		prot.start = tokIt;
		nextToken(tokIt);   // checked by caller
		checkToken(tokIt, Token.Colon);
		prot.end = tokIt;
		return prot;
	}

	//////////////////////////////////////////////////////////////////////
	void parseDeclarations(ref TokenIterator tokIt, string className = "")
	{
		// extern "C" { and namespace only allowed on highest level and thrown away
		while(!tokIt.atEnd() && tokIt.type != Token.EOF && tokIt.type != Token.BraceR)
		{
			TokenIterator start = tokIt;
			try
			{
			switch(tokIt.type)
			{
			case Token.Namespace:
				nextToken(tokIt);
				if(tokIt.type == Token.Identifier)
					nextToken(tokIt);
				checkToken(tokIt, Token.BraceL);

				DeclGroup grp = new DeclGroup;
				grp.parseDeclarations(tokIt);
				checkToken(tokIt, Token.BraceR);
				grp.start = start;
				grp.end = tokIt;
				addChild(grp);
				break;

			case Token.Extern:
				if(tokIt[1].type == Token.String)
				{
					tokIt[1].text = "(" ~ tokIt[1].text[1..$-1] ~ ")";
					nextToken(tokIt);
					nextToken(tokIt);
					if(tokIt.type == Token.BraceL)
					{
						nextToken(tokIt);

						DeclGroup grp = new DeclGroup;
						grp.parseDeclarations(tokIt);
						checkToken(tokIt, Token.BraceR);
						grp.start = start;
						grp.end = tokIt;
						addChild(grp);
						break;
					}
				}
				// otherwise fall through to normal declaration
				goto default;

			case Token.Version:
			case Token.Static_if:
				addChild(Declaration.parseStaticIfVersion(tokIt));
				break;

			case Token.Mixin:
				addChild(Expression.parsePrimaryExp(tokIt));
				checkToken(tokIt, Token.Semicolon);
				break;

			case Token.Tilde:
			case Token.Identifier:
				if(className.length > 0 && DeclType.isProtection(tokIt.text))
				{
					addChild(parseProtection(tokIt));
					break;
				}
				bool isDtor;
				int len = Declaration.isCtorDtor(tokIt, isDtor, className);
				if(len > 0)
				{
					addChild(Declaration.parseCtorDtor(tokIt, len, isDtor));
					break;
				}
				goto default; // otherwise fall through
			default:
				Declaration decl = Declaration.parseDeclaration(tokIt);
				addChild(decl);
				break;
			}
			} 
			catch(Exception e)
			{
				recoverFromSyntaxError(e, tokIt);

				auto dtype = new DeclType(DeclType.Basic, "error");
				Declaration decl = new Declaration(dtype);
				decl.start = dtype.start = start;
				decl.end = dtype.end = tokIt;
				addChild(decl);
			}
		}
	}

	void parseArguments(ref TokenIterator tokIt, int terminator)
	{
		// inserts expression as children into this
		if(tokIt.type != terminator)
		{
			for ( ; ; )
			{
				Expression e = Expression.parseAssignExp(tokIt);
				addChild(e);
				if(tokIt.type == terminator)
					break;
				checkToken(tokIt, Token.Comma);
				if(tokIt.type == terminator) // allow empty initializer after comma
					break;
			}
		}
	}

	void parseDeclArguments(ref TokenIterator tokIt, int terminator)
	{
		// inserts expression as children into this
		if(tokIt.type != terminator)
		{
			for ( ; ; )
			{
				if(tokIt.type == Token.Elipsis)
				{
					DeclType decltype = new DeclType(DeclType.Elipsis, "");
					decltype.start = tokIt;
					nextToken(tokIt);
					decltype.end = tokIt;
					Declaration decl = new Declaration(decltype);
					decl.start = decltype.start;
					decl.end = decltype.end;
					addChild(decl);
				}
				else
				{
					Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.SingleOptional);
					addChild(decl);
				}
		    		if(tokIt.type == terminator)
					break;
				checkToken(tokIt, Token.Comma);
			}
		}
	}

	//////////////////////////////////////////////////////////////////////
	void parseModule(ref TokenIterator tokIt)
	{
		start = tokIt;
	retry:
		skipComments(tokIt);

		//parseStatements(tokIt);
		parseDeclarations(tokIt);
		if(!tokIt.atEnd() && tokIt.type == Token.BraceR)
		{
			/+
			syntaxErrors++;
			tokIt.pretext ~= "/* SYNTAX ERROR: unexpected } */";
			tokIt.advance();
			goto retry;
			+/
		}
		end = tokIt;
		if(!tokIt.atEnd() && tokIt.type != Token.EOF)
			throwException((*tokIt).lineno, "not parsed until the end of the file");
	
		addEnumerators();
	}

	//////////////////////////////////////////////////////////////////////
	string toString(ref ToStringData tsd)
	{
		throwException(start.lineno, "toString(tsd) not implemented!");
		return "<not implemented>";
	}

	long evaluate()
	{
		throwException(start.lineno, "evaluate() not implemented!");
		return 0;
	}
	
	string getScope()
	{
		string txt;
		for(AST parent = _parent; parent; parent = parent._parent)
		{
			switch(parent._type)
			{
			case Type.DeclarationGroup:
				if(parent.start.type == Token.Namespace)
					txt = parent.start[1].text ~ "::" ~ txt;
				break;

			case Type.ConditionalDeclaration:
			case Type.PrimaryExp: // for mixin
				break;
			case Type.Declaration:
				Declaration decl = cast(Declaration) parent;
				if (DeclType dtype = isClassDefinition(decl))
					txt = dtype._ident ~ "::" ~ txt;
				break;
			default:
				break;
			}
		}
		return txt;
	}

	AST clone()
	{
		AST ast = new AST(_type);
		cloneChildren(ast);
		return ast;
	}

	void cloneChildren(AST ast)
	{
		ast.start = start;
		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
				ast.addChild(it.clone());
		ast.end = end;
	}

	//////////////////////////////////////////////////////////////////////
	void reassignTokens(ref TokenIterator cloneIt)
	{
		TokenIterator tokIt = start;
		start = cloneIt;

		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
			{
				while(tokIt != it.start)
				{
					tokIt.advance();
					cloneIt.advance();
				}
				tokIt = it.end;
				it.reassignTokens(cloneIt);
			}

		while(tokIt != end)
		{
			tokIt.advance();
			cloneIt.advance();
		}
		end = cloneIt;
	}

	TokenList cloneTokens(bool copyTokens = true)
	{
		TokenList toklist = copyTokenList(start, end, copyTokens);
		TokenIterator tokIt = toklist.begin();

		reassignTokens(tokIt);
		return toklist;
	}

	//////////////////////////////////////////////////////////////////////
	void addEnumerators()
	{
		if(_type == Type.Declaration && children && !children.empty())
			if(DeclType dtype = cast(DeclType) children[0])
			{
				if(dtype._dtype == DeclType.Enum)
					if(dtype.children)
					{
						string scp = getScope();
						if(dtype._ident)
							scp ~= dtype._ident ~ "::";
						for(ASTIterator it = dtype.children.begin(); !it.atEnd(); ++it)
							if(DeclVar var = cast(DeclVar) *it)
								addEnumIdentifier(scp, var._ident);
					}
				if(dtype._dtype == DeclType.Basic && dtype._ident == "__enum")
				{
					string scp = getScope();
					for(ASTIterator it = children.begin() + 1; !it.atEnd(); ++it)
						if(DeclVar var = cast(DeclVar) *it)
							addEnumIdentifier(scp, var._ident);
				}
			}

		if(children)
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
				it.addEnumerators();
	}

	//////////////////////////////////////////////////////////////////////
	static void addInheritence(string base, string derived)
	{
		if(derived in baseClass)
		{
			if(base != baseClass[derived])
				throwException("different base classes for " ~ derived);
			return;
		}
		baseClass[derived] = base;
		derivedClasses[base] ~= derived;
	}

	static bool isPOD(string className)
	{
		int loop = 0;
		while(loop++ < 20)
		{
			if(className in baseClass)
				return false;
			if(className in derivedClasses)
				return false;
			if(auto p = className in typedefIdentifier)
				className = *p;
			else
				break;
		}
		return true;
	}

	static void addEnumIdentifier(string enumName, string enumIdent)
	{
		if(enumName.length)
			enumIdentifier[enumIdent] = enumName;
	}

	static bool isBaseClass(string base, string derived)
	{
		if(string *ps = derived in baseClass)
			return *ps == base;
		return false;
	}

	static void addTypedef(DeclType dtype, DeclVar dvar)
	{
		if(dvar._ident.length == 0 || dtype._ident.length == 0)
			return;
		if(dvar._ident in typedefIdentifier)
			return;
		if(dvar.children && !dvar.children.empty && dvar.children[0]._type != Type.PrimaryExp)
			return;
		typedefIdentifier[dvar._ident] = dtype._ident;
	}

	//////////////////////////////////////////////////////////////////////
	TokenIterator start; // first token
	TokenIterator end;   // token after last token
	debug(TOKENTEXT) string toktext;

	DList!(AST) children;

	AST _parent;
	Type _type;

	//////////////////////////////////////////////////////////////////////
	static string[string]   baseClass;
	static string[][string] derivedClasses;
	static string[string]   enumIdentifier;
	static string[string]   typedefIdentifier;

	// call this to cleanup garbage from unittests
	static void clearStatic()
	{
		string[string] ini1;
		baseClass = ini1; // = baseClass.init;
		string[][string] ini2;
		derivedClasses = ini2; // = derivedClasses.init;
		string[string] ini3;
		enumIdentifier = ini3; // = enumIdentifier.init;
		typedefIdentifier = ini3; // = enumIdentifier.init;
	}
}

/********************************* Expression Parser ***************************/

class Expression : AST
{
	int _toktype;

	this(Type type, int toktype, Expression child1 = null, Expression child2 = null, Expression child3 = null)
	{
		_toktype = toktype;
		super(type);
		if(child1)
			addChild(child1);
		if(child2)
			addChild(child2);
		if(child3)
			addChild(child3);
	}

	static Expression parseFullExpression(ref TokenIterator tokIt)
	{
		return parseCommaExp(tokIt);
	}

	static Expression parsePrimaryExp(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		Expression e;

		switch (start.type)
		{
		case Token.DoubleColon:
			nextToken(tokIt);
			goto L_doubleColon;
		case Token.Identifier:
			nextToken(tokIt);
			while(tokIt.type == Token.DoubleColon)
			{
				nextToken(tokIt);
			L_doubleColon:
				if(tokIt.type == Token.Operator)
				{
					nextToken(tokIt);
					checkOperator(tokIt);
				}
				else
					checkToken(tokIt, Token.Identifier);
			}
			e = new Expression(Type.PrimaryExp, Token.Identifier);
			break;
		case Token.Operator:
			nextToken(tokIt);
			checkOperator(tokIt);
			e = new Expression(Type.PrimaryExp, Token.Operator);
			break;

		case Token.This:
		case Token.Number:
			nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, start.type);
			break;
		case Token.String:
			nextToken(tokIt);
			while(tokIt.type == Token.String) // concatenate strings
				nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, start.type);
			break;

		case Token.Mixin:
			nextToken(tokIt);
			checkToken(tokIt, Token.ParenL);
			e = new Expression(Type.PrimaryExp, Token.Mixin, parseFullExpression(tokIt));
			checkToken(tokIt, Token.ParenR);
			break;

		case Token.Sizeof:
			nextToken(tokIt);
			if(tokIt.type != Token.ParenL)
				throwException(tokIt.lineno, "( expected after sizeof");
			if(isTypeInParenthesis(tokIt) > 0)
			{
				nextToken(tokIt);
				Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.Prohibited);
				e = new Expression(Type.PrimaryExp, Token.Sizeof);
				e.addChild(decl);
				checkToken(tokIt, Token.ParenR);
			}
			else
			{
				nextToken(tokIt);
				e = new Expression(Type.PrimaryExp, Token.Sizeof, parseFullExpression(tokIt));
				checkToken(tokIt, Token.ParenR);
			}
			break;

		case Token.ParenL:
			nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, Token.ParenL, parseFullExpression(tokIt));
			checkToken(tokIt, Token.ParenR);
			break;

		case Token.BraceL:
			nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, Token.BraceL);
			e.parseArguments(tokIt, Token.BraceR);
			checkToken(tokIt, Token.BraceR);
			break;

		case Token.Static_cast, Token.Dynamic_cast, Token.Reinterpret_cast, Token.Const_cast:
			nextToken(tokIt);
			checkToken(tokIt, Token.LessThan);
			Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.Prohibited);
			e = new Expression(Type.CastExp, start.type);
			e.addChild(decl);
			checkToken(tokIt, Token.GreaterThan);
			checkToken(tokIt, Token.ParenL);
			e.addChild(parseFullExpression(tokIt));
			checkToken(tokIt, Token.ParenR);
			break;

		default:
			throwException(tokIt.lineno, "expression expected, not " ~ tokIt.text);
		}

		e.start = start;
		e.end = tokIt;
		return e;
	}

	static Expression parsePostExp(ref TokenIterator tokIt, Expression e)
	{
		TokenIterator start = e.start; // sub-expression e included
		int startType = tokIt.type;

		switch (startType)
		{
		case Token.Deref:
		case Token.Dot:
			nextToken(tokIt);
			e = new Expression(Type.PostExp, startType, e); // identifier as primary expression
			Expression idexpr = new Expression(Type.PrimaryExp, Token.Identifier);
			idexpr.start = tokIt;
			checkToken(tokIt, Token.Identifier);
			while(tokIt.type == Token.DoubleColon)
			{
				nextToken(tokIt);
				checkToken(tokIt, Token.Identifier);
			}
			idexpr.end = tokIt;
			e.addChild(idexpr);
			break;

		case Token.PlusPlus:
		case Token.MinusMinus:
			nextToken(tokIt);
			e = new Expression(Type.PostExp, startType, e);
			break;

		case Token.ParenL:
			// currently includes casts
			nextToken(tokIt);
			e = new Expression(Type.PostExp, Token.ParenL, e);
			e.parseArguments(tokIt, Token.ParenR);
			checkToken(tokIt, Token.ParenR);
			break;

		case Token.BracketL:
			nextToken(tokIt);
			e = new Expression(Type.PostExp, Token.BracketL, e, parseFullExpression(tokIt));
			checkToken(tokIt, Token.BracketR);
			break;

		default:
			return e;
		}

		e.start = start;
		e.end = tokIt;
		return parsePostExp(tokIt, e);
	}

	static Expression parseDeleteExp(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;

		checkToken(tokIt, Token.Delete);
		if(tokIt.type == Token.BracketL)
		{
			nextToken(tokIt);
			checkToken(tokIt, Token.BracketR);
		}
		Expression e = new Expression(Type.UnaryExp, Token.Delete, parseUnaryExp(tokIt));

		e.start = start;
		e.end = tokIt;
		return e;
	}

	static Expression parseNewExp(ref TokenIterator tokIt)
	{
		throwException(tokIt.lineno, "not implemented");
		return null;
	}

	//////////////////////////////////////////////////////////////////////
	static int isTypeInParenthesis(TokenIterator tokIt)
	{
		TokenIterator close;
		return isTypeInParenthesis(tokIt, close);
	}

	// return -1 if not type, 0 if undecided, 1 if type
	static int isTypeInParenthesis(TokenIterator tokIt, ref TokenIterator close)
	{
		TokenIterator it = tokIt + 1;
		if(DeclType.isBasicType(it.text) || DeclType.isTypeModifier(it.text))
			return 1;
		switch(it.type)
		{
		case Token.Enum:
		case Token.Struct:
		case Token.Union:
		case Token.Class:
		case Token.Interface:
			return 1;
		case Token.Identifier:
			break;
		default:
			return -1;
		}

		close = tokIt;
		TokenIterator noStop;
		advanceToClosingBracket(close, noStop);

		// close after ')'
		if(close[-2].type == Token.Asterisk)
			return 1;

		return 0;
	}

	static bool isCast(TokenIterator tokIt)
	{
		TokenIterator close;
		int res = isTypeInParenthesis(tokIt, close);
		
		if(res != 0)
			return res > 0;

		switch(close.type)
		{
		case Token.Identifier:
		case Token.Number:
		case Token.String:
		case Token.ParenL:
		case Token.This:
			return true;
		default:
			return false;
		}
	}

	static Expression parseUnaryExp(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		Expression e;

		switch (start.type)
		{
		case Token.Ampersand:
		case Token.Asterisk:
		case Token.PlusPlus:
		case Token.MinusMinus:
		case Token.Minus:
		case Token.Plus:
		case Token.Exclamation:
		case Token.Tilde:
		case Token.New:
			nextToken(tokIt);
			e = new Expression(Type.UnaryExp, start.type, parseUnaryExp(tokIt)); 
			break;
		case Token.Delete:
			return parseDeleteExp(tokIt);
		case Token.ParenL:
   			if(isCast(tokIt))
			{
				nextToken(tokIt);
				Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.Prohibited);
				checkToken(tokIt, Token.ParenR);
				Expression expr = parseUnaryExp(tokIt);
				e = new Expression(Type.CastExp, Token.ParenL);
				e.addChild(decl);
				e.addChild(expr);
				break;
			}
			goto default; // fall through
		default:
			e = parsePrimaryExp(tokIt);
			e = parsePostExp(tokIt, e);
			return e;
		}

		e.start = start;
		e.end = tokIt;
		return e;
	}

	alias Expression fnParseExp(ref TokenIterator);

	static Expression parseBinaryExp(tokens...) (fnParseExp* fn, ref TokenIterator tokIt) // binaryParseFn fn, 
	{
		TokenIterator start = tokIt;

		Expression e = fn(tokIt); // fn(tokIt);
	L_nextExpr:
		foreach(int type; tokens)
			if(tokIt.type == type)
			{
				nextToken(tokIt); 
				e = new Expression(Type.BinaryExp, type, e, fn(tokIt));
				e.start = start;
				e.end = tokIt;
				goto L_nextExpr;
			}

		return e;
	}

	static Expression parseMulExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Asterisk, Token.Div, Token.Mod)(&parseUnaryExp, tokIt);
	}
	static Expression parseAddExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Plus, Token.Minus, Token.Tilde)(&parseMulExp, tokIt);
	}
	static Expression parseShiftExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Shl, Token.Shr)(&parseAddExp, tokIt);
	}
	static Expression parseRelExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.LessThan, Token.LessEq, Token.GreaterThan, Token.GreaterEq,
		                       Token.Unordered, Token.LessGreater, Token.LessEqGreater, Token.UnordGreater,
		                       Token.UnordGreaterEq, Token.UnordLess, Token.UnordLessEq, Token.UnordEq)
		                      (&parseShiftExp, tokIt);
	}
	static Expression parseEqualExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Equal, Token.Unequal)(&parseRelExp, tokIt);
	}
	static Expression parseAndExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Ampersand)(&parseEqualExp, tokIt);
	}
	static Expression parseXorExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Xor)(&parseAndExp, tokIt);
	}
	static Expression parseOrExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Or)(&parseXorExp, tokIt);
	}
	static Expression parseAndAndExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.AmpAmpersand)(&parseOrExp, tokIt);
	}
	static Expression parseOrOrExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.OrOr)(&parseAndAndExp, tokIt);
	}
	static Expression parseCondExp(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;

		Expression e = parseOrOrExp(tokIt);
		if (tokIt.type != Token.Question)
			return e;
		nextToken(tokIt);

		Expression eif = parseFullExpression(tokIt);
		checkToken(tokIt, Token.Colon);
		Expression eelse = parseCondExp(tokIt);
		e = new Expression(Type.CondExp, Token.Question, e, eif, eelse);

		e.start = start;
		e.end = tokIt;
		return e;
	}
	static Expression parseAssignExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Assign, Token.AddAsgn, Token.SubAsgn, Token.MulAsgn, 
		                       Token.DivAsgn, Token.ModAsgn, Token.AndAsgn, Token.XorAsgn, Token.OrAsgn,
		                       Token.ShlAsgn, Token.ShrAsgn)
		                      (&parseCondExp, tokIt);
	}

	static Expression parseCommaExp(ref TokenIterator tokIt)
	{
		return parseBinaryExp!(Token.Comma)(&parseAssignExp, tokIt);
	}


	//////////////////////////////////////////////////////////////////////
	// declaration expression

	static Expression parsePrimaryDeclExp(ref TokenIterator tokIt, IdentPolicy idpolicy)
	{
		TokenIterator start = tokIt;
		Expression e;

		switch (start.type)
		{
		case Token.DoubleColon:
			nextToken(tokIt);
			goto L_doubleColon;

		case Token.Identifier:
			nextToken(tokIt);
			while(tokIt.type == Token.DoubleColon)
			{
				nextToken(tokIt);
			L_doubleColon:
				if(tokIt.type == Token.Operator)
				{
					nextToken(tokIt);
					checkOperator(tokIt);
				}
				else
					checkToken(tokIt, Token.Identifier);
			}
			e = new Expression(Type.PrimaryExp, Token.Identifier);
			break;
		case Token.Operator:
			nextToken(tokIt);
			checkOperator(tokIt);
			e = new Expression(Type.PrimaryExp, Token.Operator);
			break;

		case Token.Number:
		case Token.String:
			nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, start.type);
			break;

		case Token.ParenL:
			nextToken(tokIt);
			e = new Expression(Type.PrimaryExp, Token.ParenL, parseDeclModifierExp(tokIt, idpolicy, false));
			checkToken(tokIt, Token.ParenR);
			break;

		default:
			if(idpolicy == IdentPolicy.Prohibited || 
			   idpolicy == IdentPolicy.SingleOptional || idpolicy == IdentPolicy.MultipleOptional)
				e = new Expression(Type.PrimaryExp, Token.Empty);
			else
				throwException(tokIt.lineno, "expression expected, not " ~ tokIt.text);
		}

		e.start = start;
		e.end = tokIt;
		return e;
	}

	static Expression parsePostDeclExp(ref TokenIterator tokIt, Expression e, IdentPolicy idpolicy)
	{
		TokenIterator start = e.start; // sub-expression e included

		switch (tokIt.type)
		{
		case Token.ParenL:
			// currently includes casts
			nextToken(tokIt);
			e = new Expression(Type.PostExp, Token.ParenL, e);
			e.parseDeclArguments(tokIt, Token.ParenR);
			checkToken(tokIt, Token.ParenR);
			break;

		case Token.BracketL:
			nextToken(tokIt);
			e = new Expression(Type.PostExp, Token.BracketL, e);
			if(tokIt.type != Token.BracketR)
				e.addChild(parseFullExpression(tokIt));
			checkToken(tokIt, Token.BracketR);
			break;

		case Token.Colon:
			nextToken(tokIt);
			if(tokIt.type != Token.Number && tokIt.type != Token.Identifier)
				throwException(tokIt.lineno, "number or identifier expected for bitfield size");
			e = new Expression(Type.PostExp, Token.Colon, e, parsePrimaryDeclExp (tokIt, idpolicy));
			break;

		default:
			return e;
		}

		e.start = start;
		e.end = tokIt;
		return parsePostDeclExp(tokIt, e, idpolicy);
	}

	static Expression parseUnaryDeclExp(ref TokenIterator tokIt, IdentPolicy idpolicy)
	{
		TokenIterator start = tokIt;
		Expression e;

		switch (start.type)
		{
		case Token.Ampersand:
		case Token.Asterisk:
			nextToken(tokIt);
			DeclType.skipModifiers(tokIt);
			e = new Expression(Type.UnaryExp, start.type, parseUnaryDeclExp(tokIt, idpolicy)); 
			break;
		default:
			e = parsePrimaryDeclExp(tokIt, idpolicy);
			e = parsePostDeclExp(tokIt, e, idpolicy);
			return e;
		}

		e.start = start;
		e.end = tokIt;
		return e;
	}

	static Expression parseDeclModifierExp(ref TokenIterator tokIt, IdentPolicy idpolicy, bool declstmt)
	{
		TokenIterator start = tokIt;
		DeclType.skipModifiers(tokIt);

		Expression e = parseDeclExp(tokIt, idpolicy, declstmt);
		e.start = start;
		return e;
	}

	static Expression parseDeclExp(ref TokenIterator tokIt, IdentPolicy idpolicy, bool declstmt)
	{
		TokenIterator start = tokIt;
		Expression e;
		bool funcLike = start.type == Token.Identifier && start[1].type == Token.ParenL;
		if(funcLike)
			// two identifier following '(' looks like a function prototype
			if(start[2].type == Token.Identifier && start[3].type == Token.Identifier)
				funcLike = false;

		if(declstmt && funcLike)
		{
			// reverse order to avoid most exceptions
			try
			{
				e = parsePrimaryExp(tokIt);
				e = parsePostExp(tokIt, e);
			}
			catch(SyntaxException)
			{
				tokIt = start;
				e = parseUnaryDeclExp(tokIt, idpolicy);
			}
		}
		else
		{
			try
			{
				e = parseUnaryDeclExp(tokIt, idpolicy);
			}
			catch(SyntaxException)
			{
				// expecting function like var initializer
				tokIt = start;
				e = parsePrimaryExp(tokIt);
				e = parsePostExp(tokIt, e);
			}
		}
		return e;
	}

	//////////////////////////////////////////////////////////////////////
	//////////////////////////////////////////////////////////////////////

	override Expression clone()
	{
		Expression expr = new Expression(_type, _toktype);
		cloneChildren(expr);
		return expr;
	}

	override string toString(ref ToStringData tsd)
	{
		string txt;
		switch(_type)
		{
		case Type.PrimaryExp:
			switch(_toktype)
			{
			case Token.Empty:
				break;
			case Token.Identifier:
			case Token.Operator:
			case Token.This:
			case Token.Tilde:
				if(!tsd.inPrototype || !tsd.noIdentifierInPrototype)
				{
					txt = tokensToIdentifier(start, end);
					if(tsd.addScopeToIdentifier && !tsd.inPrototype)
						txt = getScope() ~ txt;
				}
				break;
			case Token.Number:
				txt = start.text;
				break;

			case Token.ParenL:
				txt = "(" ~ children[0].toString(tsd) ~ ")";
				break;
			case Token.BraceL:
				txt = "{";
				string prefix = " ";
				for(ASTIterator it = children.begin() + 1; !it.atEnd(); ++it)
				{
					txt ~= prefix ~ it.toString(tsd);
					prefix = ", ";
				}
				txt ~= " }";
				break;

			case Token.String:
				txt = "\"" ~ start.text ~ "\"";
				break;
			case Token.Sizeof:
				txt = "sizeof(" ~ children[0].toString(tsd) ~ ")";
				break;
			case Token.Mixin:
				txt = "mixin(" ~ children[0].toString(tsd) ~ ")";
				break;
			default:
				assume(0);
			}
			break;

		case Type.PostExp:
			switch(_toktype)
			{
			case Token.Deref:
			case Token.Dot:
				txt = children[0].toString(tsd) ~ Token.toString(_toktype) ~ children[1].toString(tsd);
				break;
			case Token.PlusPlus:
			case Token.MinusMinus:
				txt = children[0].toString(tsd) ~ Token.toString(_toktype);
				break;
			case Token.ParenL:
				txt = children[0].toString(tsd);
				txt ~= "(";

				bool wasInPrototype = tsd.inPrototype;
				scope(exit) tsd.inPrototype = wasInPrototype;
				if(tsd.inDeclarator)
					tsd.inPrototype = true;

				string prefix = "";
				for(ASTIterator it = children.begin() + 1; !it.atEnd(); ++it)
				{
					txt ~= prefix ~ it.toString(tsd);
					prefix = ", ";
				}
				txt ~= ")";
				break;
			case Token.BracketL:
				txt = children[0].toString(tsd) ~ "[";

				bool wasInPrototype = tsd.inPrototype;
				scope(exit) tsd.inPrototype = wasInPrototype;
				if(tsd.inDeclarator)
					tsd.inPrototype = false;

				if(children.count() > 1)
				{
					bool wasAddScopeToIdentifier = tsd.addScopeToIdentifier;
					scope(exit) tsd.addScopeToIdentifier = wasAddScopeToIdentifier;
					tsd.addScopeToIdentifier = false;

					txt ~= children[1].toString(tsd);
				}
				txt ~= "]";
				break;
			default:
				assume(0);
			}
			break;

		case Type.UnaryExp:
			switch(_toktype)
			{
			case Token.Ampersand:
			case Token.Asterisk:
			case Token.PlusPlus:
			case Token.MinusMinus:
			case Token.Minus:
			case Token.Plus:
			case Token.Exclamation:
			case Token.Tilde:
				txt = Token.toString(_toktype) ~ children[0].toString(tsd);
				break;
			case Token.New:
			case Token.Delete:
				txt = Token.toString(_toktype) ~ " " ~ children[0].toString(tsd);
				break;
			default:
				assume(0);
			}
			break;

		case Type.EmptyExp:
			break;

		case Type.BinaryExp:
			switch(_toktype)
			{
			case Token.Asterisk, Token.Div, Token.Mod,
			     Token.Plus, Token.Minus, Token.Tilde,
			     Token.Shl, Token.Shr,
			     Token.LessThan, Token.LessEq, Token.GreaterThan, Token.GreaterEq,
			     Token.Unordered, Token.LessGreater, Token.LessEqGreater, Token.UnordGreater,
			     Token.UnordGreaterEq, Token.UnordLess, Token.UnordLessEq, Token.UnordEq,
			     Token.Equal, Token.Unequal,
			     Token.Ampersand,
			     Token.Xor,
			     Token.Or,
			     Token.AmpAmpersand,
			     Token.OrOr,
			     Token.Assign, Token.AddAsgn, Token.SubAsgn, Token.MulAsgn,
			     Token.DivAsgn, Token.ModAsgn, Token.AndAsgn, Token.XorAsgn, Token.OrAsgn,
			     Token.ShlAsgn, Token.ShrAsgn,
			     Token.Comma:
				txt = children[0].toString(tsd) ~ " " ~ Token.toString(_toktype) ~ " " ~ children[1].toString(tsd);
				break;
			default:
				assume(0);
			}
			break;

		case Type.CondExp:
			txt = children[0].toString(tsd) ~ " ? " ~ children[1].toString(tsd) ~ " : " ~ children[2].toString(tsd);
			break;
		case Type.CastExp:
			txt = "(" ~ children[0].toString(tsd) ~ ")" ~ children[1].toString(tsd);
			break;
		default:
			assume(0);
		}
		return txt;
	}

	override long evaluate()
	{
		switch(_type)
		{
		default:
			break;
		case Type.PrimaryExp:
			switch(_toktype)
			{
			default:
				break;
			case Token.Identifier:
				return 0; // undefined identifier
			case Token.Number:
				return parse!long(start.text);
			case Token.ParenL:
				return children[0].evaluate();

			}
			break;

		case Type.UnaryExp:
			switch(_toktype)
			{
			default:
				break;
			case Token.Minus:
				return -children[0].evaluate();
			case Token.Plus:
				return children[0].evaluate();
			case Token.Exclamation:
				return !children[0].evaluate();
			case Token.Tilde:
				return ~children[0].evaluate();
			}
			break;

		case Type.EmptyExp:
			break;

		case Type.BinaryExp:
			long v1 = children[0].evaluate();
			long v2 = children[1].evaluate();
			switch(_toktype)
			{
			case Token.Asterisk:       return v1 * v2;
			case Token.Div:            return v1 / v2;
			case Token.Mod:            return v1 % v2;
			case Token.Plus:           return v1 + v2;
			case Token.Minus:          return v1 - v2;
			case Token.Shl:            return v1 << v2;
			case Token.Shr:            return v1 >> v2;
			case Token.LessThan:       return v1 < v2;
			case Token.LessEq:         return v1 <= v2;
			case Token.GreaterThan:    return v1 > v2;
			case Token.GreaterEq:      return v1 >= v2;
			case Token.Equal:          return v1 == v2;
			case Token.Unequal:        return v1 != v2;
			case Token.Ampersand:      return v1 & v2;
			case Token.Xor:            return v1 ^ v2;
			case Token.Or:             return v1 | v2;
			case Token.AmpAmpersand:   return v1 && v2;
			case Token.OrOr:           return v1 || v2;
			case Token.Comma:          return v1, v2;
			case Token.Tilde:
			case Token.Unordered:
			case Token.UnordGreater:
			case Token.UnordGreaterEq:
			case Token.UnordLess:
			case Token.UnordLessEq:
			case Token.UnordEq:
			case Token.LessGreater:
			case Token.LessEqGreater:
			default:
				break;
			}
			break;

		case Type.CondExp:
			return children[0].evaluate() ? children[1].evaluate() : children[2].evaluate();
		}
		ToStringData tsd;
		throwException("cannot evaluate " ~ toString(tsd));
		return 0;
	}
}

/********************************* Statement Parser ***************************/

class Statement : AST
{
	int _toktype;
	// toktype == Token.Identifier means Declaration statement
	// toktype == Token.Number     means Expression statement

	this(int toktype, AST child1 = null, AST child2 = null, AST child3 = null, AST child4 = null)
	{
		super(Type.Statement);
		_toktype = toktype;

		if(child1)
			addChild(child1);
		if(child2)
			addChild(child2);
		if(child3)
			addChild(child3);
		if(child4)
			addChild(child4);
	}

	static Statement parseStatement(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		Statement stmt;

		try
		{
	L_reparse:
		int type = tokIt.type;
		switch (type)
		{
		case Token.Struct:
		case Token.Class:
		case Token.Union:
		case Token.Enum:
		case Token.Interface:
			Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.MultipleOptional, true);
			stmt = new Statement(type, decl);
			break;
		case Token.Typedef:
		case Token.Const:
		case Token.Extern:
		case Token.Static:
			Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.MultipleMandantory, true);
			stmt = new Statement(type, decl);
			break;

		case Token.Identifier:
			if(tokIt[1].type == Token.Colon)
			{
				// label not a statement, just skip and reparse
				nextToken(tokIt);
				nextToken(tokIt);
				goto L_reparse;
			}
			if(tokIt[1].type == Token.Identifier || tokIt[1].type == Token.Asterisk || 
			   DeclType.isTypeModifier(tokIt[1].text))
			{
				Declaration decl = Declaration.parseDeclaration(tokIt, IdentPolicy.MultipleMandantory, true);
				stmt = new Statement(Token.Identifier, decl);
			}
			else
			{
				Expression expr = Expression.parseFullExpression(tokIt);
				stmt = new Statement(Token.Number, expr);
				checkToken(tokIt, Token.Semicolon);
			}
			break;

		case Token.BraceR:
			// though this is invalid, we handle it as an empty statment being followed by ';'
			stmt = new Statement(Token.BraceR);
			break;

		case Token.BraceL:
			nextToken(tokIt);
			stmt = new Statement(Token.BraceL);
			while(tokIt.type != Token.BraceR)
			{
				Statement s = parseStatement(tokIt);
				stmt.addChild(s);
			}
			nextToken(tokIt);
			break;

		case Token.Version:
		case Token.Static_if:
		case Token.If:
			nextToken(tokIt);
			checkToken(tokIt, Token.ParenL);
			Expression expr = Expression.parseFullExpression(tokIt);
			checkToken(tokIt, Token.ParenR);
			Statement ifstmt = parseStatement(tokIt);
			stmt = new Statement(type, expr, ifstmt);
			if(tokIt.type == Token.Else)
			{
				nextToken(tokIt);
				Statement elsestmt = parseStatement(tokIt);
				stmt.addChild(elsestmt);
			}
			break;

		case Token.Default:
			// treat as label, just skip and reparse
			nextToken(tokIt);
			checkToken(tokIt, Token.Colon);
			goto L_reparse;

		case Token.Case:
			// treat as statement, though it should be a label
			nextToken(tokIt);
			Expression expr = Expression.parseFullExpression(tokIt);
			checkToken(tokIt, Token.Colon);
			stmt = new Statement(type, expr);
			break;

		case Token.Switch:
		case Token.While:
			nextToken(tokIt);
			checkToken(tokIt, Token.ParenL);
			Expression expr = Expression.parseFullExpression(tokIt);
			checkToken(tokIt, Token.ParenR);
			Statement bodystmt = parseStatement(tokIt);
			stmt = new Statement(type, expr, bodystmt);
			break;

		case Token.Do:
			nextToken(tokIt);
			Statement bodystmt = parseStatement(tokIt);
			checkToken(tokIt, Token.While);
			checkToken(tokIt, Token.ParenL);
			Expression expr = Expression.parseFullExpression(tokIt);
			checkToken(tokIt, Token.ParenR);
			checkToken(tokIt, Token.Semicolon);
			stmt = new Statement(type, bodystmt, expr);
			break;

		case Token.For:
			nextToken(tokIt);
			checkToken(tokIt, Token.ParenL);
			Statement s1 = parseStatement(tokIt);
			Statement s2 = parseStatement(tokIt);
			Expression expr;
			if(tokIt.type != Token.ParenR)
				expr = Expression.parseFullExpression(tokIt);
			else
			{
				expr = new Expression(Type.EmptyExp, Token.Empty);
				expr.start = expr.end = tokIt;
			}
			checkToken(tokIt, Token.ParenR);
			Statement bodystmt = parseStatement(tokIt);
			stmt = new Statement(type, s1, s2, expr, bodystmt);
			break;

		case Token.Return:
			nextToken(tokIt);
			stmt = new Statement(type);
			if(tokIt.type != Token.Semicolon)
			{
				Expression expr = Expression.parseFullExpression(tokIt);
				stmt.addChild(expr);
			}
			checkToken(tokIt, Token.Semicolon);
			break;

		case Token.Continue:
		case Token.Break:
			nextToken(tokIt);
			goto case;
		case Token.Semicolon:
			checkToken(tokIt, Token.Semicolon);
			stmt = new Statement(type);
			break;

		case Token.Goto:
			nextToken(tokIt);
			checkToken(tokIt, Token.Identifier);
			checkToken(tokIt, Token.Semicolon);
			stmt = new Statement(type);
			break;

		case Token.__Asm:
			stmt = new Statement(type);
			skipAsmStatement(tokIt);
			break;

		default:
			Expression expr = Expression.parseFullExpression(tokIt);
			stmt = new Statement(Token.Number, expr);
			checkToken(tokIt, Token.Semicolon);
			break;
		}
		}
		catch(Exception e)
		{
			recoverFromSyntaxError(e, tokIt);
			
			stmt = new Statement(Token.Semicolon); // empty statement
		}
		
		stmt.start = start;
		stmt.end = tokIt;
		return stmt;
	}

	static void skipAsmStatement(ref TokenIterator tokIt)
	{
		nextToken(tokIt);
		if (tokIt.type == Token.BraceL)
		{
			nextToken(tokIt);
			while(!tokIt.atEnd() && tokIt.type != Token.BraceR)
				nextToken(tokIt);
			checkToken(tokIt, Token.BraceR);
		}
		else
		{
			while(!tokIt.atEnd() && tokIt.type != Token.BraceR && tokIt.type != Token.__Asm)
				nextToken(tokIt);
		}
	}

	///////////////////////////////////////////////////////////////////////

	override Statement clone()
	{
		Statement stmt = new Statement(_toktype);
		cloneChildren(stmt);
		return stmt;
	}

	override TokenIterator defaultInsertStartTokenPosition()
	{
		TokenIterator it = start;
		if(_toktype == Token.BraceL)
			if(it != end && it.type == Token.BraceL)
				it.advance();
		return it;
	}

	override TokenIterator defaultInsertEndTokenPosition()
	{
		TokenIterator it = end;
		if(_toktype == Token.BraceL)
			if(it != start && it[-1].type == Token.BraceR)
				it.retreat();
		return it;
	}
}

/********************************* Declaration Parser ***************************/

class DeclType : AST
{
	enum
	{
		Basic,
		Enum,
		Class,
		Template,
		CtorDtor,
		Elipsis,
	}

	this(int dtype, string ident)
	{
		super(Type.TypeDeclaration);
		_dtype = dtype;
		_ident = ident;
	}

	int _dtype;
	string _ident;

	override TokenIterator defaultInsertStartTokenPosition()
	{
		if(_dtype == Class)
		{
			for(TokenIterator it = start; !it.atEnd() && it != end; ++it)
				if(it.type == Token.BraceL)
					return it + 1;
		}
		return super.defaultInsertStartTokenPosition();
	}

	override TokenIterator defaultInsertEndTokenPosition()
	{
		if(_dtype == Class)
		{
			TokenIterator it = end;
			if(it != start && it[-1].type == Token.BraceR)
					return it - 1;
		}
		return super.defaultInsertEndTokenPosition();
	}

	bool isTypedef()
	{
		for(TokenIterator tokIt = start; tokIt != end; ++tokIt)
			if(tokIt.type == Token.Typedef)
				return true;
		return false;
	}

	TokenIterator mainTypeIterator()
	{
		TokenIterator tokIt;
		for(tokIt = start; tokIt != end; ++tokIt)
			if(!isTypeModifier(tokIt.text))
				break;
		return tokIt;
	}

	override string toString(ref ToStringData tsd)
	{
		string txt;
		switch(_dtype)
		{
		case Basic:
			txt = _ident;
			break;
		case Enum:
			if(tsd.addEnumPrefix)
				txt = "enum ";
			txt ~= _ident;
			break;
		case Class:
			if(tsd.addClassPrefix)
				txt = "class ";
			txt ~= _ident;
			break;
		case Template:
			string args;
			for(ASTIterator it = children.begin(); !it.atEnd(); ++it)
			{
				if(args.length)
					args ~= ", ";
				args ~= it.toString(tsd);
			}
			txt ~= _ident ~ "<" ~ args ~ ">";
			break;
		case CtorDtor: 
			break;
		case Elipsis:
			txt = "..."; 
			break;
		default:
			assume(0);
		}
		return txt;
	}

	override DeclType clone()
	{
		DeclType dtype = new DeclType(_dtype, _ident);
		cloneChildren(dtype);
		return dtype;
	}

	//////////////////////////////////////////////////////////////////////////////

	static bool isBasicType(string ident)
	{
		switch(ident)
		{
		case "void":
		case "bool":
		case "char":
		case "int":
		case "long":
		case "short":
		case "signed":
		case "unsigned":
		case "float":
		case "double":
		case "_Complex":
		case "__int64":
		case "_int64":
		case "INT32":
		case "UINT32":
		case "wchar_t":
		case "__auto":
		case "__enum":
			return true;
		default:
			return false;
		}
	}

	static bool isCallingType(string ident)
	{
		switch(ident)
		{
		case "__cdecl":
		case "__pascal":
		case "__stdcall":
		case "__near":
		case "__far":
		case "__inline":
		case "__ss":
		case "__naked":
		case "__noexpr": // added by pp4d to avoid interpretation of single modifier as expression
			return true;
		default:
			return false;
		}
	}
	static bool isMutabilityModifier(string ident)
	{
		switch(ident)
		{
		case "const":
		case "volatile":
			return true;
		default:
			return false;
		}
	}
	
	static bool isPersistentTypeModifier(string ident)
	{
		switch(ident)
		{
		case "typedef":
		case "static":
		case "STATIC": // used for private functions
			return true;
		default:
			return false;
		}
	}
	static bool isTypeModifier(string ident)
	{
		switch(ident)
		{
		case "register":
		case "virtual":
		case "extern":
		case "inline":
		case "__declspec":
		case "CEXTERN":
			return true;
		default:
			return isPersistentTypeModifier(ident) 
				|| isCallingType(ident)
				|| isMutabilityModifier(ident);
		}
	}

	static bool isProtection(string text)
	{
		switch(text)
		{
		case "public":
		case "private":
		case "protected":
			return true;
		default:
			return false;
		}
	}

	static void skipModifiers(ref TokenIterator tokIt)
	{
		while(isTypeModifier(tokIt.text))
		{
			bool isExtern = tokIt.type == Token.Extern;
			bool isDeclspec = tokIt.text == "__declspec";
			nextToken(tokIt);
			if(isExtern && tokIt.type == Token.String)
				nextToken(tokIt);
			if(isDeclspec && tokIt.type == Token.ParenL)
				advanceToClosingBracket(tokIt);
		}
	}
}

class DeclVar : AST
{
	this(string ident, Expression init = null)
	{
		super(Type.EnumDeclaration);
		_ident = ident;
		if(init)
			addChild(init);
	}

	this(Expression vardecl, Expression init = null)
	{
		super(Type.VarDeclaration);

		if(vardecl)
		{
			addChild(vardecl);
			// drill into vardecl to find identifier
			if(auto id = findIdentifier(vardecl))
				_ident = getIdentifier(id);
		}
		if(init)
			addChild(init);
	}

	override string toString(ref ToStringData tsd)
	{
		bool wasInDeclarator = tsd.inDeclarator;
		scope(exit) tsd.inDeclarator = wasInDeclarator;
		tsd.inDeclarator = true;

		string txt;
		ASTIterator it;
		if(children)
			it = children.begin();

		if(_type == Type.EnumDeclaration)
		{
			txt = _ident;
		}
		else
		{
			if(children && !it.atEnd())
			{
				txt = it.toString(tsd);
				it.advance();
			}
		}
		if(tsd.addArgumentDefaults && children && !it.atEnd())
			if(cast(Expression) *it)  // skip function body
				txt ~= " = " ~ it.toString(tsd);
		return txt;
	}

	override DeclVar clone()
	{
		DeclVar var = _type == Type.EnumDeclaration ? new DeclVar(_ident) : new DeclVar(cast(Expression) null);
		cloneChildren(var);
		return var;
	}

	string _ident;
}

class DeclGroup : AST
{
	this()
	{
		super(Type.DeclarationGroup);
	}

	override DeclGroup clone()
	{
		DeclGroup grp = new DeclGroup;
		cloneChildren(grp);
		return grp;
	}

	override TokenIterator defaultInsertStartTokenPosition()
	{
		TokenIterator it = start;
		if(it != end && it.type == Token.BraceL)
			it.advance();
		return it;
	}

	override TokenIterator defaultInsertEndTokenPosition()
	{
		TokenIterator it = end;
		if(it != start && it[-1].type == Token.BraceR)
			it.retreat();
		return it;
	}
}

class DeclConditional : AST
{
	this()
	{
		super(Type.ConditionalDeclaration);
	}

	override DeclConditional clone()
	{
		DeclConditional cond = new DeclConditional;
		cloneChildren(cond);
		return cond;
	}

}

class CtorInitializer : AST
{
	this()
	{
		super(Type.CtorInitializer);
	}

	override CtorInitializer clone()
	{
		CtorInitializer ctor = new CtorInitializer;
		cloneChildren(ctor);
		return ctor;
	}

}

class CtorInitializers : AST
{
	this()
	{
		super(Type.CtorInitializers);
	}

	override CtorInitializers clone()
	{
		CtorInitializers ctors = new CtorInitializers;
		cloneChildren(ctors);
		return ctors;
	}

}

class Declaration : AST
{
	this(DeclType decltype)
	{
		super(Type.Declaration);
		if(decltype)
			addChild(decltype);
	}

	static DeclVar parseEnumValue(ref TokenIterator tokIt, string enumName)
	{
		TokenIterator start = tokIt;

		string ident = tokIt.text;
		checkToken(tokIt, Token.Identifier);
		Expression init;
		if(tokIt.type == Token.Assign)
		{
			nextToken(tokIt);
			init = Expression.parseCondExp(tokIt);
		}

		DeclVar var = new DeclVar(ident, init);

		var.start = start;
		var.end = tokIt;
		return var;
	}

	static DeclType parseEnum(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		nextToken(tokIt);

		string ident;
		if (tokIt.type == Token.Identifier)
		{
			ident = tokIt.text;
			nextToken(tokIt);
		}

		DeclType dtype = new DeclType(DeclType.Enum, ident);
		if (tokIt.type == Token.BraceL)
		{
			nextToken(tokIt);
			while(tokIt.type != Token.BraceR)
			{
				DeclVar var = parseEnumValue(tokIt, ident);
				dtype.addChild(var);
				if(tokIt.type == Token.Comma)
					nextToken(tokIt);
				else if(tokIt.type != Token.BraceR)
					throwException("unexpected " ~ tokIt.text ~ " in enum declaration");
			}
			nextToken(tokIt);
		}

		dtype.start = start;
		dtype.end = tokIt;
		return dtype;
	}

	static int isCtorDtor(ref TokenIterator tokIt, ref bool isDtor, string className)
	{
		isDtor = false;
		int off = 0;
		if(className.length == 0)
		{
			if(tokIt.type != Token.Identifier || tokIt[1].type != Token.DoubleColon)
				return 0;
			className = tokIt.text;
			off += 2;
		}
		if(tokIt[off].text == className && tokIt[off+1].type == Token.ParenL)
			return off + 1;
		if(tokIt[off].type == Token.Tilde && tokIt[off+1].text == className && tokIt[off+2].type == Token.ParenL)
		{
			isDtor = true;
			return off + 2;
		}
		
		return 0;
	}

	static CtorInitializer parseCtorInitializer(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;

		CtorInitializer ini = new CtorInitializer;
		checkToken(tokIt, Token.Identifier);
		checkToken(tokIt, Token.ParenL);
		ini.parseArguments(tokIt, Token.ParenR);
		checkToken(tokIt, Token.ParenR);

		ini.start = start;
		ini.end = tokIt;
		return ini;
	}

	static CtorInitializers parseCtorInitializers(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		
		checkToken(tokIt, Token.Colon);
		CtorInitializers inis = new CtorInitializers;
		inis.addChild(parseCtorInitializer(tokIt));

		while(tokIt.type == Token.Comma)
		{
			nextToken(tokIt);
			inis.addChild(parseCtorInitializer(tokIt));
		}

		inis.start = start;
		inis.end = tokIt;
		return inis;
	}

	static Declaration parseCtorDtor(ref TokenIterator tokIt, int len, bool isDtor)
	{
		TokenIterator start = tokIt;
		tokIt += len;

		string ident = tokIt[-1].text;
		checkToken(tokIt, Token.ParenL);
		Expression e = new Expression(Type.PrimaryExp, isDtor ? Token.Tilde : Token.This);
		e.start = start;
		e.end = tokIt - 1;

		e = new Expression(Type.PostExp, Token.ParenL, e);
		e.parseDeclArguments(tokIt, Token.ParenR);
		checkToken(tokIt, Token.ParenR);
		e.start = start;
		e.end = tokIt;

		DeclType decltype = new DeclType(DeclType.CtorDtor, ident);
		decltype.start = start;
		decltype.end = start;

		Declaration decl = new Declaration(decltype);
		DeclVar vdecl = new DeclVar(e);
		vdecl.start = start;
		vdecl.end = tokIt;

		decl.addChild(vdecl);

		if(!isDtor && tokIt.type == Token.Colon)
		{
			decl.addChild(parseCtorInitializers(tokIt));
		}

		if(tokIt.type == Token.__In || tokIt.type == Token.__Out || 
		   tokIt.type == Token.__Body || tokIt.type == Token.BraceL)
		{
			Statement stmt = parseFunctionBody(tokIt);
			decl.addChild(stmt);
		}
		else
			checkToken(tokIt, Token.Semicolon);

		decl.start = start;
		decl.end = tokIt;
		return decl;
	}

	static DeclType parseStruct(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		nextToken(tokIt);
		DeclType.skipModifiers(tokIt);

		string ident;
		if (tokIt.type == Token.Identifier)
		{
			ident = tokIt.text;
			nextToken(tokIt);
			if (tokIt.type == Token.Colon)
			{
				nextToken(tokIt);
				if (DeclType.isProtection(tokIt.text))
					nextToken(tokIt);

				string baseclass = tokIt.text;
				checkToken(tokIt, Token.Identifier);
				
				addInheritence(baseclass, ident);
				// multiple inheritance not supported
			}
		}

		DeclType decl = new DeclType(DeclType.Class, ident);
		if (tokIt.type == Token.BraceL)
		{
			decl.children = new ASTList; // ensure list exists, albeit empty
			nextToken(tokIt);
			decl.parseDeclarations(tokIt, ident);
			checkToken(tokIt, Token.BraceR);
		}

		decl.start = start;
		decl.end = tokIt;
		return decl;
	}

	static DeclType parseTypeDeclaration(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		DeclType decl;

		if(tokIt.text == "typename")
			tokIt.advance();
		DeclType.skipModifiers(tokIt);

		switch (tokIt.type)
		{
		case Token.Enum:
			decl = parseEnum(tokIt);
			break;
		case Token.Struct:
		case Token.Class:
		case Token.Union:
		case Token.Interface:
			decl = parseStruct(tokIt);
			break;
		default:
			string ident = tokIt.text;
			if(DeclType.isBasicType(ident))
			{
				nextToken(tokIt);
				while(DeclType.isBasicType(tokIt.text))
					nextToken(tokIt);
				decl = new DeclType(DeclType.Basic, ident);
			}
			else
			{
				checkToken(tokIt, Token.Identifier);
				if(tokIt.type == Token.LessThan)
				{
					nextToken(tokIt);
					decl = new DeclType(DeclType.Template, ident);
					decl.parseDeclArguments(tokIt, Token.GreaterThan);
					checkToken(tokIt, Token.GreaterThan);
				}
				else
					decl = new DeclType(DeclType.Class, ident);
			}
			break;
		}

		while(DeclType.isCallingType(tokIt.text) || DeclType.isMutabilityModifier(tokIt.text))
			nextToken(tokIt);

		decl.start = start;
		decl.end = tokIt;
		return decl;
	}

	static DeclVar parseDeclVar(ref TokenIterator tokIt, IdentPolicy idpolicy, bool declstmt)
	{
		TokenIterator start = tokIt;

		Expression expr = Expression.parseDeclExp(tokIt, idpolicy, declstmt);
		DeclVar vdecl = new DeclVar(expr);
		if(tokIt.type == Token.Assign)
		{
			nextToken(tokIt);
			Expression init = Expression.parseAssignExp(tokIt);
			vdecl.addChild(init);
		}

		vdecl.start = start;
		vdecl.end = tokIt;
		return vdecl;
	}

	static DeclGroup parseDeclarationGroup(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		DeclGroup grp = new DeclGroup;

		if(tokIt.type == Token.Version || tokIt.type == Token.Static_if)
		{
			grp.addChild(Declaration.parseStaticIfVersion(tokIt));
		}
		else if(tokIt.type == Token.BraceL)
		{
			nextToken(tokIt);
			grp.parseDeclarations(tokIt);
			checkToken(tokIt, Token.BraceR);
		}
		else
		{
			nextToken(tokIt);
			Declaration decl = parseDeclaration(tokIt);
			grp.addChild(grp);
		}

		grp.start = start;
		grp.end = tokIt;
		return grp;
	}

	static DeclConditional parseStaticIfVersion(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		DeclConditional decl;

		switch(start.type)
		{
		case Token.Version:
		case Token.Static_if:
			nextToken(tokIt);
			checkToken(tokIt, Token.ParenL);
			Expression expr = Expression.parseFullExpression(tokIt);
			checkToken(tokIt, Token.ParenR);

			decl = new DeclConditional;
			decl.addChild(expr);
			DeclGroup dif = parseDeclarationGroup(tokIt);
			decl.addChild(dif);
			if(tokIt.type == Token.Else)
			{
				nextToken(tokIt);
				DeclGroup delse = parseDeclarationGroup(tokIt);
				decl.addChild(delse);
			}
			break;
		default:
			throwException(start.lineno, "unexpected " ~ start.text);
		}

		decl.start = start;
		decl.end = tokIt;
		return decl;
	}

	static Declaration parseTemplateDeclaration(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;

		DeclType decltype = new DeclType(DeclType.Template, "template");
		checkToken(tokIt, Token.Template);
		if(!tokIt.atEnd() && tokIt.type == Token.LessGreater) // special case for <>
		{
			tokIt.text = "<";
			tokIt.type = Token.LessThan;
			tokIt.insertAfter(createToken("", ">", Token.GreaterThan, tokIt.lineno));
			checkToken(tokIt, Token.LessThan);
			checkToken(tokIt, Token.GreaterThan);
		}
		else
		{
			checkToken(tokIt, Token.LessThan);
			if(!tokIt.atEnd() && tokIt.type != Token.GreaterThan)
			{
				decltype.addChild(parseTypeDeclaration(tokIt));
				while(!tokIt.atEnd() && tokIt.type == Token.Comma)
				{
					tokIt.advance();
					decltype.addChild(parseTypeDeclaration(tokIt));
				}
			}
			checkToken(tokIt, Token.GreaterThan);
		}
		decltype.start = start;
		decltype.end = tokIt;

		Declaration decl = new Declaration(decltype);
		decl.addChild(parseDeclaration(tokIt));
		decl.start = start;
		decl.end = tokIt;
		return decl;
	}
		
	static Declaration parseDeclaration(ref TokenIterator tokIt, 
	                                    IdentPolicy idpolicy = IdentPolicy.MultipleOptional, bool declstmt = false)
	{
		if(tokIt.type == Token.Template)
			return parseTemplateDeclaration(tokIt);

		TokenIterator start = tokIt;
		DeclType decltype = parseTypeDeclaration(tokIt);
		Declaration decl = new Declaration(decltype);

		if (tokIt.type != Token.Semicolon)
		{
			while(!tokIt.atEnd())
			{
				DeclVar vdecl = parseDeclVar(tokIt, idpolicy, declstmt);
				decl.addChild(vdecl);

				if(decltype.isTypedef())
					addTypedef(decltype, vdecl);

				if(idpolicy == IdentPolicy.SingleOptional || idpolicy == IdentPolicy.SingleMandantory || 
				   idpolicy == IdentPolicy.Prohibited)
					goto L_eodecl;

				if(DeclType.isMutabilityModifier(tokIt.text))
					nextToken(tokIt);

				if(tokIt.type == Token.__In || tokIt.type == Token.__Out || 
				   tokIt.type == Token.__Body || tokIt.type == Token.BraceL)
				{
					Statement stmt = parseFunctionBody(tokIt);
					decl.addChild(stmt);
					goto L_eodecl;
				}
				if(tokIt.type != Token.Comma)
					break;
				nextToken(tokIt);
			}
		}
		checkToken(tokIt, Token.Semicolon);

	L_eodecl:
		decl.start = start;
		decl.end = tokIt;
		return decl;
	}

	static Statement parseFunctionBody(ref TokenIterator tokIt)
	{
		TokenIterator start = tokIt;
		Statement stmt = new Statement(Token.__Body);

		while(!tokIt.atEnd())
		{
			int toktype = tokIt.type;
			if(tokIt.type == Token.__Out)
			{
				nextToken(tokIt);
				checkToken(tokIt, Token.ParenL);
				checkToken(tokIt, Token.Identifier);
				checkToken(tokIt, Token.ParenR);
				Statement s = Statement.parseStatement(tokIt);
				stmt.addChild(s);
			}
			else if(tokIt.type == Token.__In || tokIt.type == Token.__Body)
			{
				nextToken(tokIt);
				Statement s = Statement.parseStatement(tokIt);
				stmt.addChild(s);
				if(toktype == Token.__Body)
					break;
			}
			else if (tokIt.type == Token.BraceL)
			{
				Statement s = Statement.parseStatement(tokIt);
				stmt.addChild(s);
				break;
			}
			else
				throwException(tokIt.lineno, "function body expected");
		}

	L_eodecl:
		stmt.start = start;
		stmt.end = tokIt;
		return stmt;
	}

	///////////////////////////////////////////////////////////////////////////////

	override string toString(ref ToStringData tsd)
	{
		string txt;
		ASTIterator it = children.begin();
		txt ~= it.toString(tsd);

		string prefix = txt.length > 0 ? " " : "";
		for(it.advance(); !it.atEnd(); ++it)
		{
			if(!tsd.addFunctionBody && (it._type == Type.Statement || it._type == Type.CtorInitializers))
				continue;
			txt ~= prefix ~ it.toString(tsd);
			prefix = ", ";
		}
		return txt;
	}

	override Declaration clone()
	{
		Declaration decl = new Declaration(null);
		cloneChildren(decl);
		return decl;
	}

}

///////////////////////////////////////////////////////////////////////////////
// tree manipulations
///////////////////////////////////////////////////////////////////////////////

int expressionType(Expression expr)
{
	assume(expr);
	return expr._toktype;
}

int expressionType(AST ast)
{
	Expression expr = cast(Expression) ast;
	return expressionType(expr);
}

enum DeclClassification
{
	None,
	FuncDeclaration,
	AbstractFuncDeclaration,
	FuncDefinition,
	VarDeclaration,
	VarDefinition,
}

DeclClassification classifyDeclaration(AST ast)
{
	if(Declaration decl = cast(Declaration) ast)
	{
		if(decl.children.count() >= 2)
		{
			DeclType dtype = cast(DeclType) decl.children[0];
			DeclVar  dvar  = cast(DeclVar)  decl.children[1];
			if(dtype && dvar)
			{
				ASTIterator it = dvar.children.begin();
				if(!it.atEnd() && isFunctionDeclExpression(*it))
				{
					for(it.advance(); !it.atEnd(); ++it)
						if(expressionType(*it) == Token.Number) // = 0?
							return DeclClassification.AbstractFuncDeclaration;

					for(it = decl.children.begin(); !it.atEnd(); ++it)
						if(it._type == AST.Type.Statement)
							return DeclClassification.FuncDefinition;

					return DeclClassification.FuncDeclaration;
				}
				else if(!it.atEnd())
				{
					for(it.advance(); !it.atEnd(); ++it)
						if(cast(Expression)*it)
							return DeclClassification.VarDefinition;
					return DeclClassification.VarDeclaration;
				}
			}
		}
	}
	return DeclClassification.None;
}

bool isFunctionDeclExpression(AST ast)
{
	while(ast._type == AST.Type.UnaryExp)
		ast = ast.children[0];
	
	if (ast._type != AST.Type.PostExp || expressionType(ast) != Token.ParenL)
		return false;

	// check arguments: if these are not declarations, it's a var initializer
	if(!ast.children || ast.children.count() <= 1)
		return true;

	return (cast(Declaration) ast.children[1]) !is null; // check first argument
}

bool isFunctionDeclaration(AST ast)
{
	DeclClassification type = classifyDeclaration(ast);
	return type == DeclClassification.FuncDeclaration;
}

bool isFunctionDefinition(AST ast)
{
	DeclClassification type = classifyDeclaration(ast);
	return type == DeclClassification.FuncDefinition;
}

bool isVarDeclaration(AST ast)
{
	DeclClassification type = classifyDeclaration(ast);
	return type == DeclClassification.VarDeclaration;
}

bool isVarDefinition(AST ast)
{
	DeclClassification type = classifyDeclaration(ast);
	return type == DeclClassification.VarDefinition;
}

DeclType isClassDefinition(AST ast)
{
	if(Declaration decl = cast(Declaration) ast)
	{
		if(decl.children.count() >= 1)
		{
			DeclType dtype = cast(DeclType) decl.children[0];
			if(dtype._dtype == DeclType.Class && dtype.children)
				return dtype;
		}
	}
	return null;
}

string getIdentifier(AST ast)
{
	for(TokenIterator tokIt = ast.start; tokIt != ast.end; ++tokIt)
		if(tokIt.type == Token.Identifier)
			return tokIt.text;
	return null;
}

AST findIdentifier(AST ast)
{
	if(ast._type == AST.Type.PrimaryExp)
	{
		switch(ast.start.type)
		{
		case Token.Identifier:
		case Token.Operator:
		case Token.Tilde:
		case Token.This:
			return ast;
		default:
			break;
		}
	}

	if(ast.children)
		for(ASTIterator it = ast.children.begin(); !it.atEnd(); ++it)
			if(AST ident = findIdentifier(*it))
				return ident;

	return null;
}

debug
void dumpIdentifier(Declaration decl)
{
	import std.stdio;

	string txt;
	ASTIterator it = decl.children.begin();
	DeclType decltype = cast(DeclType) *it;
	assume(decltype);

	ToStringData tsd;
	tsd.noIdentifierInPrototype = true;
	txt ~= decltype.toString(tsd);

	string prefix = " ";
	for(it.advance(); !it.atEnd(); ++it)
	{
		DeclVar declvar = cast(DeclVar) *it;
		assume(declvar);
		string ident;
		if(AST ast = findIdentifier(declvar.children[0]))
			ident = tokensToIdentifier(ast.start, ast.end);
		txt ~= prefix ~ ident;
		prefix = ", ";
	}
	writefln(txt ~ ";");
}

void iterateTopLevelDeclarations(AST ast, void delegate(Declaration) apply)
{
	if(!ast.children)
		return;

	for(ASTIterator it = ast.children.begin(); !it.atEnd(); ++it)
	{
		switch(it._type)
		{
		case AST.Type.ConditionalDeclaration:
			// first child is expression
			if(it.children.count() >= 2)
				iterateTopLevelDeclarations(it.children[1], apply);
			if(it.children.count() >= 3)
				iterateTopLevelDeclarations(it.children[2], apply);
			break;
		case AST.Type.DeclarationGroup:
			iterateTopLevelDeclarations(*it, apply);
			break;

		case AST.Type.PrimaryExp:
			if(it.start.type == Token.Mixin)
				break;
			// TODO?
			break;
		case AST.Type.Protection:
			break;

		default:
			if(Declaration decl = cast(Declaration) *it)
				apply(decl);
			else
				throwException(it.start.lineno, "declaration expected");
		}
	}
}

bool copyDefaultArguments(Declaration from, Declaration to)
{
	if(!from.children || from.children.count < 2 || !to.children || to.children.count < 2)
		return false;

	DeclVar fromVar = cast(DeclVar) from.children[1];
	DeclVar toVar   = cast(DeclVar) to.children[1];
	if(!fromVar || !toVar)
		return false;

	// assume post expression ParenL for arguments
	if(!fromVar.children || fromVar.children.count < 1 || !toVar.children || toVar.children.count < 1)
		return false;
	Expression fromExpr = cast(Expression) fromVar.children[0];
	Expression toExpr   = cast(Expression) toVar.children[0];

	while(fromExpr && fromExpr._type == AST.Type.UnaryExp && toExpr && toExpr._type == AST.Type.UnaryExp)
	{
		fromExpr = cast(Expression) fromExpr.children[0];
		toExpr   = cast(Expression) toExpr.children[0];
	}
	if(!fromExpr || fromExpr._type != AST.Type.PostExp || fromExpr._toktype != Token.ParenL)
		return false;
	if(!toExpr || toExpr._type != AST.Type.PostExp || toExpr._toktype != Token.ParenL)
		return false;

	ASTIterator fromIt = fromExpr.children.begin() + 1;
	ASTIterator toIt   = toExpr.children.begin() + 1;

	while(!fromIt.atEnd() && !toIt.atEnd())
	{
		Declaration fromDecl = cast(Declaration) *fromIt;
		Declaration toDecl   = cast(Declaration) *toIt;

		if(!fromDecl || !toDecl)
			break;
		if(!fromDecl.children || fromDecl.children.count < 2 || !toDecl.children || toDecl.children.count < 2)
			break;

		DeclVar fromArg = cast(DeclVar) fromDecl.children[1];
		DeclVar toArg   = cast(DeclVar) toDecl.children[1];
		if(!fromArg || !toArg)
			break;
		
		if(fromArg.children && fromArg.children.count > 1 && toArg.children && toArg.children.count == 1)
		{
			Expression fromInit = cast(Expression) fromArg.children[1];
			Expression toInit = fromInit.clone();
			TokenList cloneList = toInit.cloneTokens();
			toArg.insertChildBefore(toArg.children.end(), toInit, cloneList);

			// need to insert "=" here
			TokenList asgnList = copyTokenList(fromInit.start - 1, fromInit.start, true);
			toArg.insertTokenListBefore(toInit, asgnList);
		}

		fromIt.advance();
		toIt.advance();
	}
	return (fromIt.atEnd() && toIt.atEnd());
}

///////////////////////////////////////////////////////////////////////

AST testAST(string txt)
{
	bool oldRecover = tryRecover;
	scope(exit) tryRecover = oldRecover;
	tryRecover = false;
	
	TokenList tokenList = scanText(txt);
	AST ast = new AST(AST.Type.Module);
	TokenIterator tokIt = tokenList.begin();
	ast.parseModule(tokIt);
	return ast;
}

unittest
{
	string txt = "X::~X() {}";
	AST ast = testAST(txt);

	Declaration decl = cast(Declaration) ast.children[0];
	assert(decl);
	assert(isFunctionDefinition(decl));

	ToStringData tsd;
	tsd.noIdentifierInPrototype = true;
	string ident = decl.toString(tsd);
	assert(ident == "X::~X()");
}

unittest
{
	string txt = "X::~X() {}";
	AST ast = testAST(txt);

	Declaration decl = cast(Declaration) ast.children[0];
	assert(decl);
	assert(decl.children.count() > 2);

	Statement stmt = cast(Statement) decl.children[2];
	Statement s2 = stmt.clone();
	s2.cloneTokens();

	string exp = " {}";
	string res = tokenListToString(s2.start, s2.end);
	assert(exp == res);
}

unittest
{
	string txt = "struct S { int x; } s;";
	AST ast = testAST(txt);

	Declaration decl = cast(Declaration) ast.children[0];
	assert(decl);
	assert(decl.children.count() == 2);

	DeclType dtype = cast(DeclType) decl.children[0];
	assert(dtype);
	assert(dtype.children.count() == 1);

	dtype.removeToken(dtype.start + 2);  // '{'
	dtype.removeChild(dtype.children[0]);
	dtype.removeToken(dtype.start + 2);  // '}'
	ast.verify();

	string exp = "struct S s;";
	string res = tokenListToString(ast.start, ast.end);
	assert(exp == res);
}

unittest
{
	string txt = "typedef X const*PX;";
	AST ast = testAST(txt);
}

unittest
{
	string txt = "typedef void (__noexpr __stdcall *fn)();";
	AST ast = testAST(txt);
}
