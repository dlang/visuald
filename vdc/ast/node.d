// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.node;

import vdc.util;
import vdc.semantic;
import vdc.lexer;
import vdc.ast.expr;
import vdc.ast.type;
import vdc.ast.mod;
import vdc.ast.tmpl;
import vdc.ast.decl;
import vdc.ast.misc;
import vdc.logger;
import vdc.interpret;

import std.exception;
import std.stdio;
import std.string;
import std.conv;
import std.algorithm;

import stdext.util;

class Node
{
	TokenId id;
	Attribute attr;
	Annotation annotation;
	TextSpan span; // file extracted from parent module
	TextSpan fulspan;
	
	Node parent;
	Node[] members;
	
	// semantic data
	int semanticSearches;
	Scope scop;
	
	this()
	{
		// default constructor needed for clone()
	}
	
	this(ref const(TextSpan) _span)
	{
		fulspan = span = _span;
	}
	this(Token tok)
	{
		id = tok.id;
		span = tok.span;
		fulspan = tok.span;
	}
	this(TokenId _id, ref const(TextSpan) _span)
	{
		id = _id;
		fulspan = span = _span;
	}

	mixin template ForwardCtor()
	{
		this()
		{
			// default constructor needed for clone()
		}
		this(ref const(TextSpan) _span)
		{
			super(_span);
		}
		this(Token tok)
		{
			super(tok);
		}
		this(TokenId _id, ref const(TextSpan) _span)
		{
			super(_id, _span);
		}
	}
		
	mixin template ForwardCtorTok()
	{
		this() {} // default constructor needed for clone()
		
		this(Token tok)
		{
			super(tok);
		}
	}
	
	mixin template ForwardCtorNoId()
	{
		this() {} // default constructor needed for clone()
		
		this(ref const(TextSpan) _span)
		{
			super(_span);
		}
		this(Token tok)
		{
			super(tok.span);
		}
	}
	
	void reinit()
	{
		id = 0;
		attr = 0;
		annotation = 0;
		members.length = 0;
		clearSpan();
	}

	Node clone()
	{
		Node	n = static_cast!Node(this.classinfo.create());
		
		n.id = id;
		n.attr = attr;
		n.annotation = annotation;
		n.span = span;
		n.fulspan = fulspan;
		
		foreach(m; members)
			n.addMember(m.clone());
		
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(this.classinfo !is n.classinfo)
			return false;
		
		if(n.id != id || n.attr != attr || n.annotation != annotation)
			return false;
		// ignore span
		
		if(members.length != n.members.length)
			return false;
			
		for(int m = 0; m < members.length; m++)
			if(!members[m].compare(n.members[m]))
				return false;
	
		return true;
	}
	
	////////////////////////////////////////////////////////////
	abstract void toD(CodeWriter writer)
	{
		writer(this.classinfo.name);
		writer.nl();
		
		auto indent = CodeIndenter(writer);
		foreach(c; members)
			writer(c);
	}

	void toC(CodeWriter writer)
	{
		toD(writer);
	}

	////////////////////////////////////////////////////////////
	static string genCheckState(string state)
	{
		return "
			if(" ~ state ~ "!= 0)
				return;
			" ~ state ~ " = 1;
			scope(exit) " ~ state ~ " = 2;
		";
	}

	enum SemanticState
	{
		None,
		ExpandingNonScopeMembers,
		ExpandedNonScopeMembers,
		AddingSymbols,
		AddedSymbols,
		ResolvingSymbols,
		ResolvedSymbols,
		SemanticDone,
	}
	int semanticState;
	
	void expandNonScopeSimple(Scope sc, int i, int j)
	{
		Node[1] narray;
		for(int m = i; m < j; )
		{
			Node n = members[m];
			narray[0] = n;
			Node[] nm = n.expandNonScopeBlock(sc, narray);
			if(nm.length == 1 && nm[0] == n)
			{
				n.addSymbols(sc);
				m++;
			}
			else
			{
				replaceMember(m, nm);
				j += nm.length - 1;
			}
		}
	}
	
	void expandNonScopeBlocks(Scope sc)
	{
		if(semanticState >= SemanticState.ExpandingNonScopeMembers)
			return;
		
		// simple expansions
		semanticState = SemanticState.ExpandingNonScopeMembers;
		expandNonScopeSimple(sc, 0, members.length);

		// expansions with interpretation
		Node[1] narray;
		for(int m = 0; m < members.length; )
		{
			Node n = members[m];
			narray[0] = n;
			Node[] nm = n.expandNonScopeInterpret(sc, narray);
			if(nm.length == 1 && nm[0] == n)
				m++;
			else
			{
				replaceMember(m, nm);
				expandNonScopeSimple(sc, m, m + nm.length);
			}
		}
		semanticState = SemanticState.ExpandedNonScopeMembers;
	}
	
	Node[] expandNonScopeBlock(Scope sc, Node[] athis)
	{
		return athis;
	}
	
	Node[] expandNonScopeInterpret(Scope sc, Node[] athis)
	{
		return athis;
	}
	
	void addMemberSymbols(Scope sc)
	{
		if(semanticState >= SemanticState.AddingSymbols)
			return;
		
		scop = sc;
		expandNonScopeBlocks(scop);

		semanticState = SemanticState.AddedSymbols;
	}
	
	void addSymbols(Scope sc)
	{
	}
	
	bool createsScope() const { return false; }

	Scope enterScope(ref Scope nscope, Scope sc)
	{
		if(!nscope)
		{
			nscope = sc.pushClone();
			nscope.node = this;
			addMemberSymbols(nscope);
			return nscope;
		}
		return sc.push(nscope);
	}
	Scope enterScope(Scope sc)
	{
		return enterScope(scop, sc);
	}
	
	final void semantic(Scope sc)
	{
		assert(sc);
		
		if(semanticState < SemanticState.SemanticDone)
		{
			logInfo("Scope(%s):semantic(%s=%s)", cast(void*)sc, this, cast(void*)this);
			LogIndent indent = LogIndent(1);
		
			_semantic(sc);
			semanticState = SemanticState.SemanticDone;
		}
	}
	
	void _semantic(Scope sc)
	{
//		throw new SemanticException(text(this, ".semantic not implemented"));
		foreach(m; members)
			m.semantic(sc);
	}

	Scope getScope()
	{
		if(scop)
			return scop;
		if(parent)
			return parent.getScope();
		return null;
	}
	
	Type calcType()
	{
		return semanticErrorType(this, ".calcType not implemented");
	}

	Value interpret(Context sc)
	{
		return semanticErrorValue(this, ".interpret not implemented");
	}
	
	Value interpretCatch(Context sc)
	{
		try
		{
			return interpret(sc);
		}
		catch(InterpretException)
		{
		}
		return semanticErrorValue(this, ": interpretation stopped");
	}
	
	ParameterList getParameterList()
	{
		return null;
	}
	ArgumentList getFunctionArguments()
	{
		return null;
	}
		
	bool isTemplate()
	{
		return false;
	}
	Node expandTemplate(Scope sc, TemplateArgumentList args)
	{
		return this;
	}
	
	////////////////////////////////////////////////////////////
	invariant()
	{
		if(!__ctfe)
		foreach(m; members)
			assert(m.parent is this);
	}
	
	void addMember(Node m) 
	{
		assert(m.parent is null);
		members ~= m;
		m.parent = this;
		extendSpan(m.fulspan);
	}

	Node removeMember(int m) 
	{
		Node n = members[m];
		removeMember(m, 1);
		return n;
	}

	void removeMember(int m, int cnt) 
	{
		assert(m >= 0 && m + cnt <= members.length);
		for (int i = 0; i < cnt; i++)
			members[m + i].parent = null;
			
		for (int n = m + cnt; n < members.length; n++)
			members[n - cnt] = members[n];
		members.length = members.length - cnt;
	}
	
	Node[] removeAll() 
	{
		for (int m = 0; m < members.length; m++)
			members[m].parent = null;
		Node[] nm = members;
		members = members.init;
		return nm;
	}

	void replaceMember(Node m, Node[] nm) 
	{
		int n = std.algorithm.countUntil(members, m);
		assert(n >= 0);
		replaceMember(n, nm);
	}
	
	void replaceMember(int m, Node[] nm) 
	{
		if(m < members.length)
			members[m].parent = null;
		members = members[0..m] ~ nm ~ members[m+1..$];
		foreach(n; nm)
			n.parent = this;
	}
	
	T getMember(T = Node)(int idx) 
	{ 
		if (idx < 0 || idx >= members.length)
			return null;
		return static_cast!T(members[idx]);
	}

	Module getModule()
	{
		Node n = this;
		while(n)
		{
			if(n.scop)
				return n.scop.mod;
			n = n.parent;
		}
		return null;
	}
	string getModuleFilename()
	{
		Module mod = getModule();
		if(!mod)
			return null;
		return mod.filename;
	}
	
	void semanticError(T...)(T args)
	{
		semanticErrorLoc(getModuleFilename(), span.start, args);
	}

	ErrorValue semanticErrorValue(T...)(T args)
	{
		semanticErrorLoc(getModuleFilename(), span.start, args);
		return Singleton!(ErrorValue).get();
	}

	ErrorType semanticErrorType(T...)(T args)
	{
		semanticErrorLoc(getModuleFilename(), span.start, args);
		return Singleton!(ErrorType).get();
	}

	////////////////////////////////////////////////////////////
	void extendSpan(ref const(TextSpan) _span)
	{
		if(_span.start < fulspan.start)
			fulspan.start = _span.start;
		if(_span.end > fulspan.end)
			fulspan.end = _span.end;
	}
	void limitSpan(ref const(TextSpan) _span)
	{
		if(_span.start > fulspan.start)
			fulspan.start = _span.start;
		if(_span.end < fulspan.end)
			fulspan.end = _span.end;
	}
	void clearSpan()
	{
		span.end.line = span.start.line;
		span.end.index = span.start.index;
		fulspan = span;
	}
}

interface CallableNode
{
	Value interpretCall(Context sc);
	
	ParameterList getParameterList();
	FunctionBody getFunctionBody();
}

TextPos minimumTextPos(Node node)
{
	version(all)
		return node.fulspan.start;
	else
	{
		TextPos start = node.span.start;
		while(node.members.length > 0)
		{
			if(compareTextSpanAddress(node.members[0].span.start.line, node.members[0].span.start.index,
									  start.line, start.index) < 0)
				start = node.members[0].span.start;
			node = node.members[0];
		}
		return start;
	}
}

TextPos maximumTextPos(Node node)
{
	version(all)
		return node.fulspan.end;
	else
	{
		TextPos end = node.span.end;
		while(node.members.length > 0)
		{
			if(compareTextSpanAddress(node.members[$-1].span.end.line, node.members[$-1].span.start.index,
									  end.line, end.index) > 0)
				end = node.members[$-1].span.end;
			node = node.members[$-1];
		}
		return end;
	}
}

bool nodeContains(Node node, TextPos pos)
{
	TextPos start = minimumTextPos(node);
	if(start > pos)
		return false;
	TextPos end = maximumTextPos(node);
	if(end <= pos)
		return false;
	return true;
}

// figure out whether the given range is between the children of a binary expression
bool isBinaryOperator(Node root, int startLine, int startIndex, int endLine, int endIndex)
{
	TextPos pos = TextPos(startIndex, startLine);
	if(!nodeContains(root, pos))
		return false;

L_loop:
	if(root.members.length == 2)
	{
		if(cast(BinaryExpression) root)
			if(maximumTextPos(root.members[0]) <= pos && minimumTextPos(root.members[1]) > pos)
				return true;
	}

	foreach(m; root.members)
		if(nodeContains(m, pos))
		{
			root = m;
			goto L_loop;
		}

	return false;
}

Scope getTextPosScope(Node root, int line, int index, bool *inDotExpr)
{
	TextPos pos = TextPos(index, line);
	if(!nodeContains(root, pos))
		return null;

	Scope sc;
	if(root.parent)
		sc = root.parent.getScope();
	if(sc && root.createsScope())
		sc = root.enterScope(sc);
	else
		sc = root.getScope();
	if(!sc)
		return null;

L_loop:
	foreach(m; root.members)
		if(nodeContains(m, pos))
		{
			if(m.createsScope())
				sc = m.enterScope(sc);
			root = m;
			goto L_loop;
		}

	if(inDotExpr)
		*inDotExpr = false;
	if(auto id = cast(Identifier)root)
		if(auto dotexpr = cast(DotExpression)id.parent)
		{
			sc = dotexpr.getExpression().calcType().getScope();
			if(inDotExpr)
				*inDotExpr = true;
		}

	return sc;
}
