// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details
//
// interpret: return null to indicate that execution should not continue
//            return special values for program flow control
//            return normal values for returning values
//
module vdc.ast.stmt;

import vdc.util;
import vdc.lexer;
import vdc.ast.node;
import vdc.ast.expr;
import vdc.ast.decl;
import vdc.semantic;
import vdc.interpret;

import vdc.parser.engine;

import std.conv;

//Statement:
//    [Statement...]
class Statement : Node
{
	mixin ForwardCtor!();
	
	override Value interpret(Scope sc)
	{
		foreach(m; members)
		{
			Value v = m.interpret(sc);
			if(v)
				return v;
		}
		return null;
	}
}

class EmptyStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer(";");
		writer.nl;
	}
}

version(obsolete)
{
//ScopeStatement:
//    ;
//    NonEmptyStatement
//    ScopeBlockStatement
//
//ScopeBlockStatement:
//    BlockStatement
class ScopeStatement : Statement
{
	mixin ForwardCtor!();
}

//ScopeNonEmptyStatement:
//    NonEmptyStatement
//    BlockStatement
class ScopeNonEmptyStatement : Statement
{
	mixin ForwardCtor!();
}

//NoScopeNonEmptyStatement:
//    NonEmptyStatement
//    BlockStatement
class NoScopeNonEmptyStatement : ScopeNonEmptyStatement
{
	mixin ForwardCtor!();
}

//NoScopeStatement:
//    ;
//    NonEmptyStatement
//    BlockStatement
class NoScopeStatement : ScopeStatement
{
	mixin ForwardCtor!();
}

//NonEmptyStatement:
//    LabeledStatement
//    ExpressionStatement
//    DeclarationStatement
//    IfStatement
//    WhileStatement
//    DoStatement
//    ForStatement
//    ForeachStatement
//    SwitchStatement
//    FinalSwitchStatement
//    CaseStatement
//    CaseRangeStatement
//    DefaultStatement
//    ContinueStatement
//    BreakStatement
//    ReturnStatement
//    GotoStatement
//    WithStatement
//    SynchronizedStatement
//    VolatileStatement
//    TryStatement
//    ScopeGuardStatement
//    ThrowStatement
//    AsmStatement
//    PragmaStatement
//    MixinStatement
//    ForeachRangeStatement
//    ConditionalStatement
//    StaticAssert
//    TemplateMixin
class NonEmptyStatement : Statement
{
	mixin ForwardCtor!();
}
} // version(obsolete)

//LabeledStatement:
//    Identifier : NoScopeStatement
class LabeledStatement : Statement
{
	string ident;
	
	Statement getStatement() { return getMember!Statement(0); }

	this() {} // default constructor needed for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	override LabeledStatement clone()
	{
		LabeledStatement n = static_cast!LabeledStatement(super.clone());
		n.ident = ident;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}

	override void toD(CodeWriter writer)
	{
		{
			CodeIndenter indent = CodeIndenter(writer, -1);
			writer.writeIdentifier(ident);
			writer(":");
			writer.nl;
		}
		writer(getStatement());
	}
}

//BlockStatement:
//    { }
//    { StatementList }
//
//StatementList:
//    Statement
//    Statement StatementList
class BlockStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("{");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			foreach(m; members)
				writer(m);
		}
		writer("}");
		writer.nl;
	}

	override void _semantic(Scope sc)
	{
		// TODO: TemplateParameterList, Constraint
		if(members.length > 0)
		{
			sc = enterScope(sc);
			super._semantic(sc);
			sc = sc.pop();
		}
	}

}

//ExpressionStatement:
//    [Expression]
class ExpressionStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer(getMember(0), ";");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		getMember(0).interpret(sc);
		return null;
	}
}

//DeclarationStatement:
//    [Decl]
class DeclarationStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer(getMember(0));
	}
	override void _semantic(Scope sc)
	{
		super._semantic(sc);
		auto decl = getMember!Decl(0);
		decl.addSymbols(sc);
		if(decl.attr & Attr_Static)
			initValues(sc, false);
	}

	override Value interpret(Scope sc)
	{
		auto decl = getMember!Decl(0);
		if(!(decl.attr & Attr_Static))
			initValues(sc, true);
		return null;
	}
	
	void initValues(Scope sc, bool reinit)
	{
		auto decl = getMember!Decl(0);
		if(decl.getFunctionBody())
			return; // nothing to do for local functions
		
		auto decls = decl.getDeclarators();
		for(int n = 0; n < decls.members.length; n++)
		{
			auto d = decls.getDeclarator(n);
			if(reinit)
				d.value = null;
			d.interpret(sc);
		}
	}
}

//IfStatement:
//    if ( IfCondition ) ThenStatement
//    if ( IfCondition ) ThenStatement else ElseStatement
//
//IfCondition:
//    Expression
//    auto Identifier = Expression
//    Declarator = Expression
//
//ThenStatement:
//    ScopeNonEmptyStatement
//
//ElseStatement:
//    ScopeNonEmptyStatement
class IfStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("if(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
		if(members.length > 2)
		{
			writer("else");
			writer.nl;
			{
				CodeIndenter indent = CodeIndenter(writer);
				writer(getMember(2));
			}
		}
	}

	override Value interpret(Scope sc)
	{
		Value cond = getMember(0).interpret(sc);
		if(cond.toBool())
		{
			if(Value v = getMember(1).interpret(sc))
				return v;
		}
		else if(members.length > 2)
		{
			if(Value v = getMember(2).interpret(sc))
				return v;
		}
		return null;
	}
}

//WhileStatement:
//    while ( Expression ) ScopeNonEmptyStatement
class WhileStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("while(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}

	override Value interpret(Scope sc)
	{
		while(getMember(0).interpret(sc).toBool())
		{
			if(Value v = getMember(1).interpret(sc))
			{
				if(auto bv = cast(BreakValue)v)
				{
					if(!bv.ident)
						break;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == bv.ident)
							break;
				}
				else if(auto cv = cast(ContinueValue)v)
				{
					if(!cv.ident)
						continue;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == cv.ident)
							continue;
				}
				return v;
			}
		}
		return null;
	}
}

//DoStatement:
//    do ScopeNonEmptyStatement while ( Expression )
class DoStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("do");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(0));
		}
		writer("while(", getMember(1), ");");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		do
		{
			if(Value v = getMember(0).interpret(sc))
			{
				if(auto bv = cast(BreakValue)v)
				{
					if(!bv.ident)
						break;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == bv.ident)
							break;
				}
				else if(auto cv = cast(ContinueValue)v)
				{
					if(!cv.ident)
						continue;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == cv.ident)
							continue;
				}
				return v;
			}
		}
		while(getMember(1).interpret(sc).toBool());
		return null;
	}
}

//ForStatement:
//    for ( Initialize Test ; Increment ) ScopeNonEmptyStatement
//Initialize:
//    ;
//    NoScopeNonEmptyStatement
//
//Test:
//    Expression_opt
//
//Increment:
//    Expression_opt
//
class ForStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("for(", getMember(0), getMember(1), "; ", getMember(2), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(3));
		}
	}

	override Value interpret(Scope sc)
	{
		for(getMember(0).interpret(sc); getMember(1).interpret(sc).toBool();
			getMember(2).interpret(sc))
		{
			if(Value v = getMember(3).interpret(sc))
			{
				if(auto bv = cast(BreakValue)v)
				{
					if(!bv.ident)
						break;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == bv.ident)
							break;
				}
				else if(auto cv = cast(ContinueValue)v)
				{
					if(!cv.ident)
						continue;
					if(auto ls = cast(LabeledStatement)parent)
						if(ls.ident == cv.ident)
							continue;
				}
				return v;
			}
		}
		return null;
	}
}

//ForeachStatement:
//    Foreach ( ForeachTypeList ; Aggregate ) NoScopeNonEmptyStatement
//
//Foreach:
//    foreach
//    foreach_reverse
//
//ForeachTypeList:
//    ForeachType
//    ForeachType , ForeachTypeList
//
//ForeachType:
//    ref Type Identifier
//    Type Identifier
//    ref Identifier
//    Identifier
//
//Aggregate:
//    Expression
//
//ForeachRangeStatement:
//    Foreach ( ForeachType ; LwrExpression .. UprExpression ) ScopeNonEmptyStatement
//
//LwrExpression:
//    Expression
//
//UprExpression:
//    Expression
class ForeachStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer(id, "(", getMember(0), "; ");
		if(members.length == 3)
			writer(getMember(1));
		else
			writer(getMember(1), " .. ", getMember(2));
		
		writer(")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(members.length - 1));
		}
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

class ForeachTypeList : Node
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer.writeArray(members);
	}
}

class ForeachType : Node
{
	mixin ForwardCtor!();

	bool isRef;

	override ForeachType clone()
	{
		ForeachType n = static_cast!ForeachType(super.clone());
		n.isRef = isRef;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.isRef == isRef;
	}
	
	override void toD(CodeWriter writer)
	{
		if(isRef)
			writer("ref ");
		writer.writeArray(members, " ");
	}
}

//SwitchStatement:
//    switch ( Expression ) ScopeNonEmptyStatement
class SwitchStatement : Statement
{
	mixin ForwardCtor!();

	bool isFinal;

	override SwitchStatement clone()
	{
		SwitchStatement n = static_cast!SwitchStatement(super.clone());
		n.isFinal = isFinal;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.isFinal == isFinal;
	}
	
	override void toD(CodeWriter writer)
	{
		if(isFinal)
			writer("final ");
		writer("switch(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//FinalSwitchStatement:
//    final switch ( Expression ) ScopeNonEmptyStatement
//
class FinalSwitchStatement : Statement
{
	mixin ForwardCtor!();

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//CaseStatement:
//    case ArgumentList : Statement
//
//CaseRangeStatement:
//    case FirstExp : .. case LastExp : Statement
//
//FirstExp:
//    AssignExpression
//
//LastExp:
//    AssignExpression
class CaseStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		{
			CodeIndenter indent = CodeIndenter(writer, -1);
			writer("case ", getMember(0));
			if(id == TOK_slice)
			{
				writer(": .. case ", getMember(1));
			}
			else
			{
				writer.writeArray(members[1..$], ", ", true);
			}
			writer(":");
		}
		writer.nl();
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//DefaultStatement:
//    default : Statement
class DefaultStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		{
			CodeIndenter indent = CodeIndenter(writer, -1);
			writer("default:");
		}
		writer.nl();
	}
	
	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//ContinueStatement:
//    continue ;
//    continue Identifier ;
class ContinueStatement : Statement
{
	mixin ForwardCtor!();

	string ident;

	override ContinueStatement clone()
	{
		ContinueStatement n = static_cast!ContinueStatement(super.clone());
		n.ident = ident;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	override void toD(CodeWriter writer)
	{
		writer("continue");
		if(ident.length)
		{
			writer(" ");
			writer.writeIdentifier(ident);
		}
		writer(";");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return new ContinueValue(ident);
	}
}

//BreakStatement:
//    break ;
//    break Identifier ;
class BreakStatement : Statement
{
	mixin ForwardCtor!();

	string ident;

	override BreakStatement clone()
	{
		BreakStatement n = static_cast!BreakStatement(super.clone());
		n.ident = ident;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	override void toD(CodeWriter writer)
	{
		writer("break");
		if(ident.length)
		{
			writer(" ");
			writer.writeIdentifier(ident);
		}
		writer(";");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return new BreakValue(ident);
	}
}


//ReturnStatement:
//    return ;
//    return Expression ;
class ReturnStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("return ", getMember(0), ";");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return getMember(0).interpret(sc);
	}
}


//GotoStatement:
//    goto Identifier ;
//    goto default ;
//    goto case ;
//    goto case Expression ;
class GotoStatement : Statement
{
	mixin ForwardCtor!();

	string ident;
	
	override GotoStatement clone()
	{
		GotoStatement n = static_cast!GotoStatement(super.clone());
		n.ident = ident;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	override void toD(CodeWriter writer)
	{
		if(id == TOK_Identifier)
		{
			writer("goto ");
			writer.writeIdentifier(ident);
			writer(";");
		}
		else if(id == TOK_default)
			writer("goto default;");
		else
		{
			if(members.length > 0)
				writer("goto case ", getMember(0), ";");
			else
				writer("goto case;");
		}
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//WithStatement:
//    with ( Expression ) ScopeNonEmptyStatement
//    with ( Symbol ) ScopeNonEmptyStatement
//    with ( TemplateInstance ) ScopeNonEmptyStatement
class WithStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("with(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//SynchronizedStatement:
//    [Expression_opt ScopeNonEmptyStatement]
class SynchronizedStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		if(members.length > 1)
			writer("synchronized(", getMember(0), ") ");
		else
			writer("synchronized ");
			
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(members.length - 1));
		}
	}

	override Value interpret(Scope sc)
	{
		// no need to synhronize, interpreter is single-threaded
		return getMember(members.length - 1).interpret(sc);
	}
}

//VolatileStatement:
//    [ScopeNonEmptyStatement]
class VolatileStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("volatile ");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(members.length - 1));
		}
	}

	override Value interpret(Scope sc)
	{
		// no need to synhronize, interpreter is single-threaded
		return super.interpret(sc);
	}
}


//TryStatement:
//    try ScopeNonEmptyStatement Catches
//    try ScopeNonEmptyStatement Catches FinallyStatement
//    try ScopeNonEmptyStatement FinallyStatement
//
//Catches:
//    LastCatch
//    Catch
//    Catch Catches
//
//LastCatch:
//    catch NoScopeNonEmptyStatement
//
//Catch:
//    catch ( CatchParameter ) NoScopeNonEmptyStatement
//
//CatchParameter:
//    BasicType Identifier
//
//FinallyStatement:
//    finally NoScopeNonEmptyStatement
class TryStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("try");
		writer.nl();
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(0));
		}
		foreach(m; members[1..$])
			writer(m);
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

class Catch : Node
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		if(members.length > 2)
			writer("catch(", getMember(0), " ", getMember(1), ")");
		else if(members.length > 1)
			writer("catch(", getMember(0), ")");
		else
			writer("catch");
		writer.nl();
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(members.length - 1));
		}
	}
}

class FinallyStatement : Catch
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("finally");
		writer.nl();
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(0));
		}
	}
}


//ThrowStatement:
//    throw Expression ;
class ThrowStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("throw ", getMember(0), ";");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//ScopeGuardStatement:
//    scope ( "exit" ) ScopeNonEmptyStatement
//    scope ( "success" ) ScopeNonEmptyStatement
//    scope ( "failure" ) ScopeNonEmptyStatement
class ScopeGuardStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("scope(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " not implemented."));
	}
}

//AsmStatement:
//    asm { }
//    asm { AsmInstructionList }
//
//AsmInstructionList:
//    AsmInstruction ;
//    AsmInstruction ; AsmInstructionList
class AsmStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("asm {");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(0));
		}
		writer("}");
		writer.nl;
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " cannot be interpreted."));
	}
}

class AsmInstructionList : Node
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		foreach(m; members)
		{
			writer(m, ";");
			writer.nl();
		}
	}
}

//PragmaStatement:
//    Pragma NoScopeStatement
class PragmaStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer(getMember(0), " ", getMember(1));
	}

	override Value interpret(Scope sc)
	{
		getMember(0).interpret(sc);
		return getMember(1).interpret(sc);
	}
}

//MixinStatement:
//    [ AssignExpression ]
class MixinStatement : Statement
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		writer("mixin(", getMember(0), ");");
		writer.nl;
	}

	override void _semantic(Scope sc)
	{
		Value v = getMember(0).interpret(sc);
		string s = v.toStr();
		Parser parser = new Parser;
		Node[] n = parser.parseStatements(s, span);
		parent.replaceMember(this, n);
	}

	override Value interpret(Scope sc)
	{
		return semanticErrorValue(text(this, " semantic not run"));
	}
}

