// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.expr;

import vdc.util;
import vdc.lexer;
import vdc.semantic;
import vdc.interpret;

import vdc.ast.node;
import vdc.ast.decl;
import vdc.ast.misc;
import vdc.ast.tmpl;
import vdc.ast.aggr;
import vdc.ast.mod;
import vdc.ast.type;

import std.conv;
import std.string;

////////////////////////////////////////////////////////////////
// Operator precedence - greater values are higher precedence
enum PREC
{
	zero,
	expr,
	assign,
	cond,
	oror,
	andand,
	or,
	xor,
	and,
	equal,
	rel,
	shift,
	add,
	mul,
	pow,
	unary,
	primary,
}
shared static PREC precedence[NumTokens];

shared static char recursion[NumTokens];

////////////////////////////////////////////////////////////////
void writeExpr(CodeWriter writer, Expression expr, bool paren)
{
	if(paren)
		writer("(");
	writer(expr);
	if(paren)
		writer(")");
}

enum Spaces
{
	None = 0,
	Left = 1,
	Right = 2,
	LeftRight = Left | Right
}

void writeOperator(CodeWriter writer, TokenId op, int spaces)
{
	if(spaces & Spaces.Left)
		writer(" ");
	writer(op);
	if(spaces & Spaces.Right)
		writer(" ");
}

////////////////////////////////////////////////////////////////
//Expression:
//    CommaExpression
class Expression : Node
{
	// semantic data
	Type type;
	
	mixin ForwardCtor!();

	abstract PREC getPrecedence();

	Type calcType(Scope sc)
	{
		if(!type)
			semanticError(text(this, ".calcType not implemented"));
		return type;
	}
	
	Value interpret(Scope sc)
	{
		semanticError(text(this, ".interpret not implemented"));
		return new VoidValue;
	}
}

class BinaryExpression : Expression
{
	mixin ForwardCtor!();

	TokenId getOperator() { return id; }
	Expression getLeftExpr() { return getMember!Expression(0); }
	Expression getRightExpr() { return getMember!Expression(1); }

	override PREC getPrecedence() { return precedence[id]; }

	override void semantic(Scope sc)
	{
		getLeftExpr().semantic(sc);
		getRightExpr().semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		Expression exprL = getLeftExpr();
		Expression exprR = getRightExpr();
		
		bool parenL = (exprL.getPrecedence() < getPrecedence() + (recursion[id] == 'L' ? 0 : 1));
		bool parenR = (exprR.getPrecedence() < getPrecedence() + (recursion[id] == 'R' ? 0 : 1));
		
		writeExpr(writer, exprL, parenL);
		writeOperator(writer, id, Spaces.LeftRight);
		writeExpr(writer, exprR, parenR);
	}

	override Type calcType(Scope sc)
	{
		if(!type)
		{
			Type typeL = getLeftExpr().calcType(sc);
			Type typeR = getRightExpr().calcType(sc);
		}
		return type;
	}
	
	override Value interpret(Scope sc)
	{
		Value vL = getLeftExpr().interpret(sc);
		Value vR = getRightExpr().interpret(sc);

version(all)
{
		return vL.opBin(id, vR);
}
else
		switch(id)
		{
			case TOK_equal:	    return vL.opBinOp!"=="(vR);
			case TOK_notequal:  return vL.opBinOp!"!="(vR);
			case TOK_lt:		return vL.opBinOp!"<"(vR);
			case TOK_gt:		return vL.opBinOp!">"(vR);
			case TOK_le:		return vL.opBinOp!"<="(vR);
			case TOK_ge:		return vL.opBinOp!">="(vR);
			case TOK_unord:		return vL.opBinOp!"!<>="(vR);
			case TOK_ue:		return vL.opBinOp!"!<>"(vR);
			case TOK_lg:		return vL.opBinOp!"<>"(vR);
			case TOK_leg:		return vL.opBinOp!"<>="(vR);
			case TOK_ule:		return vL.opBinOp!"!>"(vR);
			case TOK_ul:		return vL.opBinOp!"!>="(vR);
			case TOK_uge:		return vL.opBinOp!"!<"(vR);
			case TOK_ug:		return vL.opBinOp!"!<="(vR);
			case TOK_is:        return vL.opBinOp!"is"(vR);
			case TOK_notcontains:return vL.opBinOp!"!in"(vR);
			case TOK_notidentity:return vL.opBinOp!"!is"(vR);
				
			case TOK_shl:		return vL.opBinOp!"<<"(vR);
			case TOK_shr:		return vL.opBinOp!">>"(vR);
			case TOK_ushr:		return vL.opBinOp!">>>"(vR);
			
			case TOK_add:		return vL.opBinOp!"+"(vR);
			case TOK_min:		return vL.opBinOp!"-"(vR);
			case TOK_mul:		return vL.opBinOp!"*"(vR);
			case TOK_pow:		return vL.opBinOp!"^^"(vR);
			
			case TOK_div:		return vL.opBinOp!"/"(vR);
			case TOK_mod:		return vL.opBinOp!"%"(vR);
	//[ "slice",            ".." ],
	//[ "dotdotdot",        "..." ],
			case TOK_xor:		return vL.opBinOp!"^"(vR);
			case TOK_and:		return vL.opBinOp!"&"(vR);
			case TOK_or:		return vL.opBinOp!"|"(vR);
			case TOK_tilde:		return vL.opBinOp!"~"(vR);
	//[ "plusplus",         "++" ],
	//[ "minusminus",       "--" ],
	//[ "question",         "?" ],
			case TOK_assign:	return vL.opassign!"="(vR);
			case TOK_addass:	return vL.opassign!"+="(vR);
			case TOK_minass:	return vL.opassign!"-="(vR);
			case TOK_mulass:	return vL.opassign!"*="(vR);
			case TOK_powass:	return vL.opassign!"^^="(vR);
				
			case TOK_shlass:	return vL.opassign!"<<="(vR);
			case TOK_shrass:	return vL.opassign!">>="(vR);
			case TOK_ushrass:	return vL.opassign!">>>="(vR);
			case TOK_xorass:	return vL.opassign!"^="(vR);
			case TOK_andass:	return vL.opassign!"&="(vR);
			case TOK_orass:		return vL.opassign!"|="(vR);
			case TOK_catass:	return vL.opassign!"~="(vR);
				
			case TOK_divass:	return vL.opassign!"/="(vR);
			case TOK_modass:	return vL.opassign!"%="(vR);

			default:
				semanticError(text("interpretation of binary operator ", tokenString(id), " not implemented"));
				return vL;
		}
	}

};

mixin template BinaryExpr()
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
	}
}

//CommaExpression:
//    AssignExpression
//    AssignExpression , CommaExpression
class CommaExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//AssignExpression:
//    ConditionalExpression
//    ConditionalExpression = AssignExpression
//    ConditionalExpression += AssignExpression
//    ConditionalExpression -= AssignExpression
//    ConditionalExpression *= AssignExpression
//    ConditionalExpression /= AssignExpression
//    ConditionalExpression %= AssignExpression
//    ConditionalExpression &= AssignExpression
//    ConditionalExpression |= AssignExpression
//    ConditionalExpression ^= AssignExpression
//    ConditionalExpression ~= AssignExpression
//    ConditionalExpression <<= AssignExpression
//    ConditionalExpression >>= AssignExpression
//    ConditionalExpression >>>= AssignExpression
//    ConditionalExpression ^^= AssignExpression
class AssignExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//ConditionalExpression:
//    OrOrExpression
//    OrOrExpression ? Expression : ConditionalExpression
class ConditionalExpression : Expression
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
	}
	
	Expression getCondition() { return getMember!Expression(0); }
	Expression getThenExpr() { return getMember!Expression(1); }
	Expression getElseExpr() { return getMember!Expression(2); }
	
	override PREC getPrecedence() { return PREC.cond; }

	override void semantic(Scope sc)
	{
		getCondition().semantic(sc);
		getThenExpr().semantic(sc);
		getElseExpr().semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		Expression condExpr = getCondition();
		Expression thenExpr = getThenExpr();
		Expression elseExpr = getElseExpr();
		
		bool condParen = (condExpr.getPrecedence() <= getPrecedence());
		bool thenParen = (thenExpr.getPrecedence() < PREC.expr);
		bool elseParen = (elseExpr.getPrecedence() < getPrecedence());

		writeExpr(writer, condExpr, condParen);
		writeOperator(writer, TOK_question, Spaces.LeftRight);
		writeExpr(writer, thenExpr, thenParen);
		writeOperator(writer, TOK_colon, Spaces.LeftRight);
		writeExpr(writer, elseExpr, elseParen);
	}
	
	override Value interpret(Scope sc)
	{
		Value cond = getCondition().interpret(sc);
		Expression e = (cond.toBool() ? getThenExpr() : getElseExpr());
		return e.interpret(sc);
	}
}

//OrOrExpression:
//    AndAndExpression
//    OrOrExpression || AndAndExpression
class OrOrExpression : BinaryExpression
{
	mixin BinaryExpr!();

	override Value interpret(Scope sc)
	{
		Value vL = getLeftExpr().interpret(sc);
		if(vL.toBool())
			return Value.create(true);
		Value vR = getRightExpr().interpret(sc);
		return Value.create(vR.toBool());
	}
}

//AndAndExpression:
//    OrExpression
//    AndAndExpression && OrExpression
class AndAndExpression : BinaryExpression
{
	mixin BinaryExpr!();

	override Value interpret(Scope sc)
	{
		Value vL = getLeftExpr().interpret(sc);
		if(!vL.toBool())
			return Value.create(false);
		Value vR = getRightExpr().interpret(sc);
		return Value.create(vR.toBool());
	}
}

//OrExpression:
//    XorExpression
//    OrExpression | XorExpression
class OrExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//XorExpression:
//    AndExpression
//    XorExpression ^ AndExpression
class XorExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//AndExpression:
//    CmpExpression
//    AndExpression & CmpExpression
class AndExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//CmpExpression:
//    ShiftExpression
//    EqualExpression
//    IdentityExpression
//    RelExpression
//    InExpression
//
//EqualExpression:
//    ShiftExpression == ShiftExpression
//    ShiftExpression != ShiftExpression
//
//IdentityExpression:
//    ShiftExpression is ShiftExpression
//    ShiftExpression !is ShiftExpression
//
//RelExpression:
//    ShiftExpression < ShiftExpression
//    ShiftExpression <= ShiftExpression
//    ShiftExpression > ShiftExpression
//    ShiftExpression >= ShiftExpression
//    ShiftExpression !<>= ShiftExpression
//    ShiftExpression !<> ShiftExpression
//    ShiftExpression <> ShiftExpression
//    ShiftExpression <>= ShiftExpression
//    ShiftExpression !> ShiftExpression
//    ShiftExpression !>= ShiftExpression
//    ShiftExpression !< ShiftExpression
//    ShiftExpression !<= ShiftExpression
//
//InExpression:
//    ShiftExpression in ShiftExpression
//    ShiftExpression !in ShiftExpression
class CmpExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//ShiftExpression:
//    AddExpression
//    ShiftExpression << AddExpression
//    ShiftExpression >> AddExpression
//    ShiftExpression >>> AddExpression
class ShiftExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//AddExpression:
//    MulExpression
//    AddExpression + MulExpression
//    AddExpression - MulExpression
//    AddExpression ~ MulExpression
class AddExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//MulExpression:
//    PowExpression
//    MulExpression * PowExpression
//    MulExpression / PowExpression
//    MulExpression % PowExpression
class MulExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//PowExpression:
//    UnaryExpression
//    UnaryExpression ^^ PowExpression
class PowExpression : BinaryExpression
{
	mixin BinaryExpr!();
}

//UnaryExpression:
//    PostfixExpression
//    & UnaryExpression
//    ++ UnaryExpression
//    -- UnaryExpression
//    * UnaryExpression
//    - UnaryExpression
//    + UnaryExpression
//    ! UnaryExpression
//    ~ UnaryExpression
//    NewExpression
//    DeleteExpression
//    CastExpression
//    /*NewAnonClassExpression*/
class UnaryExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.unary; }
	
	Expression getExpression() { return getMember!Expression(0); }

	override void semantic(Scope sc)
	{
		getExpression().semantic(sc);
	}
	
	override Value interpret(Scope sc)
	{
		Value v = getExpression().interpret(sc);
version(all)
		return v.opUn(id);
else
		switch(id)
		{
			case TOK_and:        return v.opRefPointer();
			case TOK_mul:        return v.opDerefPointer();
			case TOK_plusplus:   return v.opUnOp!"++"();
			case TOK_minusminus: return v.opUnOp!"--"();
			case TOK_min:        return v.opUnOp!"-"();
			case TOK_add:        return v.opUnOp!"+"();
			case TOK_not:        return v.opUnOp!"!"();
			case TOK_tilde:      return v.opUnOp!"~"();
			default:
				semanticError(text("interpretation of unary operator ", tokenString(id), " not implemented"));
				return v;
		}
	}
	
	override void toD(CodeWriter writer)
	{
		Expression expr = getExpression();
		bool paren = (expr.getPrecedence() < getPrecedence());

		writeOperator(writer, id, Spaces.Right);
		writeExpr(writer, expr, paren);
	}
}

//NewExpression:
//    NewArguments Type [ AssignExpression ]
//    NewArguments Type ( ArgumentList )
//    NewArguments Type
//    NewArguments ClassArguments BaseClassList_opt { DeclDefs } 
class NewExpression : Expression
{
	bool hasNewArgs;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK_new, tok.span);
	}

	override NewExpression clone()
	{
		NewExpression n = static_cast!NewExpression(super.clone());
		n.hasNewArgs = hasNewArgs;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.hasNewArgs == hasNewArgs;
	}
	
	override PREC getPrecedence() { return PREC.unary; }
	
	ArgumentList getNewArguments() { return hasNewArgs ? getMember!ArgumentList(0) : null; }
	Type getType() { return getMember!Type(hasNewArgs ? 1 : 0); }
	ArgumentList getCtorArguments() { return members.length > (hasNewArgs ? 2 : 1) ? getMember!ArgumentList(members.length - 1) : null; }
	
	override void semantic(Scope sc)
	{
		if(auto args = getNewArguments())
			args.semantic(sc);
		getType().semantic(sc);
		if(auto args = getCtorArguments())
			args.semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		if(ArgumentList nargs = getNewArguments())
			writer("new(", nargs, ") ");
		else
			writer("new ");
		writer(getType());
		if(ArgumentList cargs = getCtorArguments())
			writer("(", cargs, ")");
	}
}

class AnonymousClassType : Type
{
	mixin ForwardCtor!();

	ArgumentList getArguments() { return members.length > 1 ? getMember!ArgumentList(0) : null; }
	AnonymousClass getClass() { return getMember!AnonymousClass(members.length - 1); }
	
	override bool propertyNeedsParens() const { return true; }
	
	override void toD(CodeWriter writer)
	{
		if(ArgumentList args = getArguments())
			writer("class(", args, ") ");
		else
			writer("class ");
		writer(getClass());
	}
}

//CastExpression:
//    cast ( Type )         UnaryExpression
//    cast ( )              UnaryExpression
//    cast ( const )        UnaryExpression
//    cast ( immutable )    UnaryExpression
//    cast ( inout )        UnaryExpression
//    cast ( shared )       UnaryExpression
//    cast ( shared const ) UnaryExpression
//    cast ( const shared ) UnaryExpression
//    cast ( shared inout ) UnaryExpression
//    cast ( inout shared ) UnaryExpression
class CastExpression : Expression
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK_cast, tok.span);
	}

	override PREC getPrecedence() { return PREC.unary; }
	
	Type getType() { return members.length > 1 ? getMember!Type(0) : null; }
	Expression getExpression() { return getMember!Expression(members.length - 1); }
	
	override void semantic(Scope sc)
	{
		if(auto type = getType())
			type.semantic(sc);
		getExpression().semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		writer("cast(");
		writer.writeAttributes(attr);
		if(Type type = getType())
			writer(getType());
		writer(")");
			
		if(getExpression().getPrecedence() < getPrecedence())
			writer("(", getExpression(), ")");
		else
			writer(getExpression());
	}
}

//PostfixExpression:
//    PrimaryExpression
//    PostfixExpression . Identifier
//    PostfixExpression . NewExpression
//    PostfixExpression ++
//    PostfixExpression --
//    PostfixExpression ( )
//    PostfixExpression ( ArgumentList )
//    IndexExpression
//    SliceExpression
//
//IndexExpression:
//    PostfixExpression [ ArgumentList ]
//
//SliceExpression:
//    PostfixExpression [ ]
//    PostfixExpression [ AssignExpression .. AssignExpression ]
class PostfixExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	Expression getExpression() { return getMember!Expression(0); }

	override void semantic(Scope sc)
	{
		foreach(m; members)
			m.semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		Expression expr = getExpression();
		bool paren = (expr.getPrecedence() < getPrecedence());

		writeExpr(writer, expr, paren);
		switch(id)
		{
			case TOK_lbracket:
				writer("[");
				if(members.length == 2)
					writer(getMember!ArgumentList(1));
				else if(members.length == 3)
				{
					writer(getMember!Expression(1));
					writer(" .. ");
					writer(getMember!Expression(2));
				}
				writer("]");
				break;

			case TOK_lparen:
				writer("(");
				if(members.length > 1)
					writer(getMember!ArgumentList(1));
				writer(")");
				break;
				
			case TOK_dot:
			case TOK_new:
				writer(".", getMember(1));
				break;
				
			default:
				writeOperator(writer, id, Spaces.Right);
				break;
		}
	}
}

//ArgumentList:
//    AssignExpression
//    AssignExpression ,
//    AssignExpression , ArgumentList
class ArgumentList : Node
{
	mixin ForwardCtor!();

	override void semantic(Scope sc)
	{
		foreach(m; members)
			m.semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		bool writeSep = false;
		foreach(m; members)
		{
			if(writeSep)
				writer(", ");
			writeSep = true;
			
			bool paren = false;
			if(auto expr = cast(Expression) m)
				paren = (expr.getPrecedence() <= PREC.expr);
			
			if(paren)
				writer("(", m, ")");
			else
				writer(m);
		}
	}
}

//PrimaryExpression:
//    Identifier
//    . Identifier
//    TemplateInstance
//    this
//    super
//    null
//    true
//    false
//    $
//    __FILE__
//    __LINE__
//    IntegerLiteral
//    FloatLiteral
//    CharacterLiteral
//    StringLiterals
//    ArrayLiteral
//    AssocArrayLiteral
//    FunctionLiteral
//    AssertExpression
//    MixinExpression
//    ImportExpression
//    BasicType . Identifier
//    Typeof
//    TypeidExpression
//    IsExpression
//    ( Expression )
//    ( Type ) . Identifier
//    TraitsExpression

class PrimaryExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	override void toD(CodeWriter writer)
	{
		writer(id);
	}
}

//ArrayLiteral:
//    [ ArgumentList ]
class ArrayLiteral : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	override void semantic(Scope sc)
	{
		foreach(m; members)
			m.semantic(sc);
	}
	
	override void toD(CodeWriter writer)
	{
		writer("[");
		writer.writeArray(members);
		writer("]");
	}
}

//VoidInitializer:
//    void
class VoidInitializer : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	override void toD(CodeWriter writer)
	{
		writer("void");
	}
}

// used for Expression_opt in for and return statements
class EmptyExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.expr; }

	override void toD(CodeWriter writer)
	{
	}
}


//AssocArrayLiteral:
//    [ KeyValuePairs ]
//
//KeyValuePairs:
//    KeyValuePair
//    KeyValuePair , KeyValuePairs
//
//KeyValuePair:
//    KeyExpression : ValueExpression
//
//KeyExpression:
//    ConditionalExpression
//
//ValueExpression:
//    ConditionalExpression
class KeyValuePair : BinaryExpression
{
	mixin ForwardCtor!();

	static this()
	{
		precedence[TOK_colon] = PREC.assign;
	}
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK_colon, tok.span);
	}
}

//FunctionLiteral:
//    function Type_opt ParameterAttributes_opt FunctionBody
//    delegate Type_opt ParameterAttributes_opt FunctionBody
//    ParameterAttributes FunctionBody
//    FunctionBody
class FunctionLiteral : Expression
{
	mixin ForwardCtor!();

	Type getType() { return members.length > 2 ? getMember!Type(0) : null; }
	ParameterList getParameterList() { return getMember!ParameterList(members.length - 2); }
	FunctionBody getFunctionBody() { return getMember!FunctionBody(members.length - 1); }
	
	override PREC getPrecedence() { return PREC.primary; }

	override void toD(CodeWriter writer)
	{
		if(id != 0)
			writer(id, " ");
		if(Type type = getType())
			writer(type, " ");
		writer(getParameterList(), " ");
		writer.writeAttributes(attr, false);
		writer(getFunctionBody());
	}
}

class StructLiteral : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	override void toD(CodeWriter writer)
	{
		writer("{ ", getMember(0), " }");
	}
}

//ParameterAttributes:
//    Parameters
//    Parameters FunctionAttributes
//
//AssertExpression:
//    assert ( AssignExpression )
//    assert ( AssignExpression , AssignExpression )
class AssertExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	Expression getExpression() { return getMember!Expression(0); }
	Expression getMessage() { return getMember!Expression(1); }
	
	override void toD(CodeWriter writer)
	{
		writer("assert(");
		writer(getExpression());
		if(Expression msg = getMessage())
			writer(", ", msg);
		writer(")");
	}
}

//MixinExpression:
//    mixin ( AssignExpression )
class MixinExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	Expression getExpression() { return getMember!Expression(0); }
	
	override void toD(CodeWriter writer)
	{
		writer("mixin(", getMember!Expression(0), ")");
	}
}

//ImportExpression:
//    import ( AssignExpression )
class ImportExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	Expression getExpression() { return getMember!Expression(0); }
	
	override void toD(CodeWriter writer)
	{
		writer("import(", getMember!Expression(0), ")");
	}
}

//TypeidExpression:
//    typeid ( Type )
//    typeid ( Expression )
class TypeIdExpression : Expression
{
	mixin ForwardCtor!();

	override PREC getPrecedence() { return PREC.primary; }

	override void toD(CodeWriter writer)
	{
		writer("typeid(", getMember(0), ")");
	}
}

//IsExpression:
//    is ( Type )
//    is ( Type : TypeSpecialization )
//    is ( Type == TypeSpecialization )
//    is ( Type Identifier )
//    is ( Type Identifier : TypeSpecialization )
//    is ( Type Identifier == TypeSpecialization )
//    is ( Type Identifier : TypeSpecialization , TemplateParameterList )
//    is ( Type Identifier == TypeSpecialization , TemplateParameterList )
//
//TypeSpecialization:
//    Type
//    struct
//    union
//    class
//    interface
//    enum
//    function
//    delegate
//    super
//    const
//    immutable
//    inout
//    shared
//    return
//
class IsExpression : PrimaryExpression
{
	int kind;
	string ident;

	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK_is, tok.span);
	}
	
	override IsExpression clone()
	{
		IsExpression n = static_cast!IsExpression(super.clone());
		n.kind = kind;
		n.ident = ident;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.kind == kind
			&& tn.ident == ident;
	}
	
	Type getType() { return getMember!Type(0); }
	TypeSpecialization getTypeSpecialization() { return members.length > 1 ? getMember!TypeSpecialization(1) : null; }
	
	override void toD(CodeWriter writer)
	{
		writer("is(", getType());
		if(ident.length)
		{
			writer(" ");
			writer.writeIdentifier(ident);
		}
		if(kind != 0)
			writer(" ", kind, " ");
		if(auto ts = getTypeSpecialization())
			writer(ts);
		writer(")");
	}
}

class TypeSpecialization : Node
{
	mixin ForwardCtor!();
	
	Type getType() { return getMember!Type(0); }
	
	override void toD(CodeWriter writer)
	{
		if(id != 0)
			writer(id);
		else
			writer(getMember(0));
	}
}

class IdentifierExpression : PrimaryExpression
{
	bool global;

	// semantic data	
	Node resolved;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK_Identifier, tok.span);
	}
	
	override IdentifierExpression clone()
	{
		IdentifierExpression n = static_cast!IdentifierExpression(super.clone());
		n.global = global;
		return n;
	}
	
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.global == global;
	}
	
	Identifier getIdentifier() { return getMember!Identifier(0); }

	override void semantic(Scope sc)
	{
		if(global)
			sc = Module.getModule(this).scop;
		
		string ident = getIdentifier().ident;
		resolved = sc.resolve(ident, span);
	}
	
	override void toD(CodeWriter writer)
	{
		if(global)
			writer(".");
		writer(getIdentifier());
	}

	override void toC(CodeWriter writer)
	{
		if(resolved)
		{
			Module thisMod = Module.getModule(this);
			Module thatMod = Module.getModule(resolved);
			if(global || thisMod is thatMod)
			{
				thatMod.writeNamespace(writer);
			}
		}
		writer(getIdentifier());
	}
}

class IntegerLiteralExpression : PrimaryExpression
{
	string txt;
	
	ulong value;
	bool unsigned;
	bool lng;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		txt = tok.txt;
		initValue();
	}
	
	void initValue()
	{
		string val = txt; 
		while(val.length > 1)
		{
			if(val[$-1] == 'L')
				lng = true;
			else if(val[$-1] == 'U' || val[$-1] == 'u')
				unsigned = true;
			else
				break;
			val = val[0..$-1];
		}
		int radix = 10;
		if(val[0] == '0' && val.length > 1)
		{
			if(val[1] == 'x' || val[1] == 'X')
				radix = 16;
			else if(val[1] == 'b' || val[1] == 'B')
				radix = 2;
			else
				radix = 8;
		}
		val = removechars(val, "_");
		value = parse!ulong(val, radix);
	}
	
	override IntegerLiteralExpression clone()
	{
		IntegerLiteralExpression n = static_cast!IntegerLiteralExpression(super.clone());
		n.txt = txt;
		n.value = value;
		n.unsigned = unsigned;
		n.lng = lng;
		return n;
	}

	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.txt == txt
			&& tn.value == value
			&& tn.unsigned == unsigned
			&& tn.lng == lng;
	}

	override void toD(CodeWriter writer)
	{
		writer(txt);
	}
	
	override void semantic(Scope sc)
	{
		if(type)
			return;
		
		if(lng)
			if(unsigned)
				type = new BasicType(TOK_ulong, span);
			else
				type = new BasicType(TOK_long, span);
		else
			if(unsigned)
				type = new BasicType(TOK_uint, span);
			else
				type = new BasicType(TOK_int, span);
		
		type.semantic(sc);
	}
	
	T create(T)()
	{
		T v = new T;
		v.val = cast(T.ValType) value;
		return v;
	}
	
	override Value interpret(Scope sc)
	{
		if(lng || value >= 0x80000000)
			if(unsigned)
				return create!ULongValue();
			else
				return create!LongValue();
		else if(value >= 0x8000)
			if(unsigned)
				return create!UIntValue();
			else
				return create!IntValue();
		else if(value >= 0x80)
			if(unsigned)
				return create!UShortValue();
			else
				return create!ShortValue();
		else
			if(unsigned)
				return create!UByteValue();
			else
				return create!ByteValue();
	}
	
	int getInt()
	{
		if(value > int.max)
			semanticError(span.start, text(value, " too large to fit an integer"));
		return cast(int) value;
	}
	uint getUInt()
	{
		if(value > uint.max)
			semanticError(span.start, text(value, " too large to fit an unsigned integer"));
		return cast(uint) value;
	}
}

class FloatLiteralExpression : PrimaryExpression
{
	string txt;

	real value;
	bool complex;
	bool lng;
	bool flt;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		txt = tok.txt;
		initValue();
	}
	
	void initValue()
	{
		string val = txt; 
		while(val.length > 1)
		{
			if(val[$-1] == 'L')
				lng = true;
			else if(val[$-1] == 'f' || val[$-1] == 'F')
				flt = true;
			else if(val[$-1] == 'i')
				complex = true;
			else if(val[$-1] == '.')
			{
				val = val[0..$-1];
				break;
			}
			else
				break;
			val = val[0..$-1];
		}
		val = removechars(val, "_");
		value = parse!real(val);
	}
	
	override FloatLiteralExpression clone()
	{
		FloatLiteralExpression n = static_cast!FloatLiteralExpression(super.clone());
		n.txt = txt;
		n.value = value;
		n.complex = complex;
		n.lng = lng;
		n.flt = flt;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.txt == txt
			&& tn.value == value
			&& tn.complex == complex
			&& tn.flt == flt
			&& tn.lng == lng;
	}
	
	override void toD(CodeWriter writer)
	{
		writer(txt);
	}
}

class StringLiteralExpression : PrimaryExpression
{
	string txt;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		txt = tok.txt;
	}

	void addText(Token tok)
	{
		txt ~= " " ~ tok.txt;
	}

	override StringLiteralExpression clone()
	{
		StringLiteralExpression n = static_cast!StringLiteralExpression(super.clone());
		n.txt = txt;
		return n;
	}
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.txt == txt;
	}

	override void semantic(Scope sc)
	{
		type = createTypeString(span);
	}
	
	override Value interpret(Scope sc)
	{
		return Value.create(txt);
	}
	
	override void toD(CodeWriter writer)
	{
		writer(txt);
	}
}

class CharacterLiteralExpression : PrimaryExpression
{
	string txt;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		txt = tok.txt;
	}
	
	override CharacterLiteralExpression clone()
	{
		CharacterLiteralExpression n = static_cast!CharacterLiteralExpression(super.clone());
		n.txt = txt;
		return n;
	}
	
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.txt == txt;
	}
	
	override void toD(CodeWriter writer)
	{
		writer(txt);
	}
}

class TypeProperty : PrimaryExpression
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(0, tok.span);
	}
	
	Type getType() { return getMember!Type(0); }
	Identifier getProperty() { return getMember!Identifier(1); }
	
	override void toD(CodeWriter writer)
	{
		Type type = getType();
		if(type.propertyNeedsParens())
			writer("(", getType(), ").", getProperty());
		else
			writer(getType(), ".", getProperty());
	}
}

class StructConstructor : PrimaryExpression
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(0, tok.span);
	}
	
	Type getType() { return getMember!Type(0); }
	ArgumentList getArguments() { return getMember!ArgumentList(1); }
	
	override void toD(CodeWriter writer)
	{
		Type type = getType();
		if(type.propertyNeedsParens())
			writer("(", getType(), ")(", getArguments(), ")");
		else
			writer(getType(), "(", getArguments(), ")");
	}
}

class TraitsExpression : PrimaryExpression
{
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(TOK___traits, tok.span);
	}
	
	override void toD(CodeWriter writer)
	{
		writer("__traits(", getMember(0));
		if(members.length > 1)
			writer(", ", getMember(1));
		writer(")");
	}
}

class TraitsArguments : TemplateArgumentList
{
	mixin ForwardCtorNoId!();
}
