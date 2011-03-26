// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module ast.stmt;

import util;
import simplelexer;
import ast.node;
import ast.expr;
import ast.decl;

//Statement:
//    ScopeStatement
class Statement : Node
{
	mixin ForwardCtor!();
}

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

class EmptyStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(";");
		writer.nl;
	}
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


//LabeledStatement:
//    Identifier : NoScopeStatement
class LabeledStatement : Statement
{
	string ident;
	
	Statement getStatement() { return getMember!Statement(0); }

	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	LabeledStatement clone()
	{
		LabeledStatement n = static_cast!LabeledStatement(super.clone());
		n.ident = ident;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
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
}

//ExpressionStatement:
//    Expression ;
class ExpressionStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(getMember(0), ";");
		writer.nl;
	}
}

//DeclarationStatement:
//    Declaration
class DeclarationStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(getMember(0));
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

	void toD(CodeWriter writer)
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
}

//WhileStatement:
//    while ( Expression ) ScopeNonEmptyStatement
class WhileStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("while(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}
}

//DoStatement:
//    do ScopeNonEmptyStatement while ( Expression )
class DoStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
	{
		writer("for(", getMember(0), getMember(1), "; ", getMember(2), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(3));
		}
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

	void toD(CodeWriter writer)
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
}

class ForeachTypeList : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer.writeArray(members);
	}
}

class ForeachType : Node
{
	mixin ForwardCtor!();

	bool isRef;

	ForeachType clone()
	{
		ForeachType n = static_cast!ForeachType(super.clone());
		n.isRef = isRef;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.isRef == isRef;
	}
	
	void toD(CodeWriter writer)
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

	SwitchStatement clone()
	{
		SwitchStatement n = static_cast!SwitchStatement(super.clone());
		n.isFinal = isFinal;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.isFinal == isFinal;
	}
	
	void toD(CodeWriter writer)
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
}
//FinalSwitchStatement:
//    final switch ( Expression ) ScopeNonEmptyStatement
//
class FinalSwitchStatement : Statement
{
	mixin ForwardCtor!();
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

	void toD(CodeWriter writer)
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
}

//DefaultStatement:
//    default : Statement
class DefaultStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		{
			CodeIndenter indent = CodeIndenter(writer, -1);
			writer("default:");
		}
		writer.nl();
	}
	
}

//ContinueStatement:
//    continue ;
//    continue Identifier ;
class ContinueStatement : Statement
{
	mixin ForwardCtor!();

	string ident;

	ContinueStatement clone()
	{
		ContinueStatement n = static_cast!ContinueStatement(super.clone());
		n.ident = ident;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	void toD(CodeWriter writer)
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
}

//BreakStatement:
//    break ;
//    break Identifier ;
class BreakStatement : Statement
{
	mixin ForwardCtor!();

	string ident;

	BreakStatement clone()
	{
		BreakStatement n = static_cast!BreakStatement(super.clone());
		n.ident = ident;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	void toD(CodeWriter writer)
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
}


//ReturnStatement:
//    return ;
//    return Expression ;
class ReturnStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("return ", getMember(0), ";");
		writer.nl;
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
	
	GotoStatement clone()
	{
		GotoStatement n = static_cast!GotoStatement(super.clone());
		n.ident = ident;
		return n;
	}
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	void toD(CodeWriter writer)
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
}

//WithStatement:
//    with ( Expression ) ScopeNonEmptyStatement
//    with ( Symbol ) ScopeNonEmptyStatement
//    with ( TemplateInstance ) ScopeNonEmptyStatement
class WithStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("with(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
	}
}

//SynchronizedStatement:
//    synchronized ScopeNonEmptyStatement
//    synchronized ( Expression ) ScopeNonEmptyStatement
class SynchronizedStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
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
}

class Catch : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
	{
		writer("throw ", getMember(0), ";");
		writer.nl;
	}
}

//ScopeGuardStatement:
//    scope ( "exit" ) ScopeNonEmptyStatement
//    scope ( "success" ) ScopeNonEmptyStatement
//    scope ( "failure" ) ScopeNonEmptyStatement
class ScopeGuardStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("scope(", getMember(0), ")");
		writer.nl;
		{
			CodeIndenter indent = CodeIndenter(writer);
			writer(getMember(1));
		}
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

	void toD(CodeWriter writer)
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
}

class AsmInstructionList : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
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

	void toD(CodeWriter writer)
	{
		writer(getMember(0), " ", getMember(1));
	}
}

//MixinStatement:
//    mixin ( AssignExpression ) ;
class MixinStatement : Statement
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("mixin(", getMember(0), ");");
		writer.nl;
	}
}

