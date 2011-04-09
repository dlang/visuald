// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.tmpl;

import vdc.util;
import vdc.lexer;
import vdc.ast.node;
import vdc.ast.decl;
import vdc.ast.expr;
import vdc.ast.type;

//TemplateDeclaration:
//    template TemplateIdentifier ( TemplateParameterList ) Constraint_opt { DeclDefs }
class TemplateDeclaration : Node
{
	mixin ForwardCtor!();

	Identifier getIdentifier() { return getMember!Identifier(0); }
	TemplateParameterList getTemplateParameterList() { return getMember!TemplateParameterList(1); }
	Constraint getConstraint() { return members.length > 3 ? getMember!Constraint(2) : null; }
	Node getBody() { return getMember(members.length - 1); }
	bool isMixin() { return id == TOK_mixin; }
	
	void toD(CodeWriter writer)
	{
		if(isMixin())
			writer("mixin ");
		writer("template ", getIdentifier(), getTemplateParameterList());
		writer.nl();
		if(getConstraint())
		{
			writer(getConstraint());
			writer.nl();
		}
//		writer("{");
//		writer.nl();
//		{
//			CodeIndenter indent = CodeIndenter(writer);
			writer(getBody());
//		}
//		writer("}");
//		writer.nl();
		writer.nl();
	}
	void toC(CodeWriter writer)
	{
		// we never write the template, only instantiations
	}
}
//
//TemplateIdentifier:
//    Identifier
//
//TemplateParameterList:
//    TemplateParameter
//    TemplateParameter ,
//    TemplateParameter , TemplateParameterList
class TemplateParameterList : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("(");
		writer.writeArray(members);
		writer(")");
	}
}

//TemplateParameter:
//    TemplateTypeParameter
//    TemplateValueParameter
//    TemplateAliasParameter
//    TemplateTupleParameter
//    TemplateThisParameter
class TemplateParameter : Node
{
	mixin ForwardCtor!();
}

//
//TemplateInstance:
//    TemplateIdentifier ! ( TemplateArgumentList )
//    TemplateIdentifier ! TemplateSingleArgument
class TemplateInstance : Identifier
{
	mixin ForwardCtorTok!();

	void toD(CodeWriter writer)
	{
		writer.writeIdentifier(ident);
		writer("!(", getMember(0), ")");
	}
}
//
//
//TemplateArgumentList:
//    TemplateArgument
//    TemplateArgument ,
//    TemplateArgument , TemplateArgumentList
class TemplateArgumentList : Node
{
	mixin ForwardCtorNoId!();

	void toD(CodeWriter writer)
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

//
//TemplateArgument:
//    Type
//    AssignExpression
//    Symbol
//
//// identical to IdentifierList
//Symbol:
//    SymbolTail
//    . SymbolTail
//
//SymbolTail:
//    Identifier
//    Identifier . SymbolTail
//    TemplateInstance
//    TemplateInstance . SymbolTail
//
//TemplateSingleArgument:
//    Identifier
//    BasicTypeX
//    CharacterLiteral
//    StringLiteral
//    IntegerLiteral
//    FloatLiteral
//    true
//    false
//    null
//    __FILE__
//    __LINE__
	
//TemplateTypeParameter:
//    Identifier
//    Identifier TemplateTypeParameterSpecialization
//    Identifier TemplateTypeParameterDefault
//    Identifier TemplateTypeParameterSpecialization TemplateTypeParameterDefault
class TemplateTypeParameter : TemplateParameter
{
	string ident;
	Type specialization;
	Node def;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	TemplateTypeParameter clone()
	{
		TemplateTypeParameter n = static_cast!TemplateTypeParameter(super.clone());
		n.ident = ident;
		for(int m = 0; m < members.length; m++)
		{
			if(members[m] is specialization)
				n.specialization = static_cast!Type(n.members[m]);
			if(members[m] is def)
				n.def = n.members[m];
		}
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
		writer.writeIdentifier(ident);
		if(specialization)
			writer(" : ", specialization);
		if(def)
			writer(" = ", def);
	}
}

//TemplateTypeParameterSpecialization:
//    : Type
//
//TemplateTypeParameterDefault:
//    = Type
//
//TemplateThisParameter:
//    this TemplateTypeParameter
class TemplateThisParameter : TemplateParameter
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("this ", getMember(0));
	}
}
//
//TemplateValueParameter:
//    Declaration
//    Declaration TemplateValueParameterSpecialization
//    Declaration TemplateValueParameterDefault
//    Declaration TemplateValueParameterSpecialization TemplateValueParameterDefault
class TemplateValueParameter : TemplateParameter
{
	mixin ForwardCtor!();

	Expression specialization;
	Expression def;

	TemplateValueParameter clone()
	{
		TemplateValueParameter n = static_cast!TemplateValueParameter(super.clone());
		for(int m = 0; m < members.length; m++)
		{
			if(members[m] is specialization)
				n.specialization = static_cast!Expression(n.members[m]);
			if(members[m] is def)
				n.def = static_cast!Expression(n.members[m]);
		}
		return n;
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0));
		if(specialization)
			writer(" : ", specialization);
		if(def)
			writer(" = ", def);
	}
}
//
//TemplateValueParameterSpecialization:
//    : ConditionalExpression
//
//TemplateValueParameterDefault:
//    = __FILE__
//    = __LINE__
//    = ConditionalExpression
//
//TemplateAliasParameter:
//    alias Identifier TemplateAliasParameterSpecialization_opt TemplateAliasParameterDefault_opt
//
//TemplateAliasParameterSpecialization:
//    : Type
//
//TemplateAliasParameterDefault:
//    = Type
class TemplateAliasParameter : TemplateParameter
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("alias ", getMember(0));
	}
}
//
//TemplateTupleParameter:
//    Identifier ...
class TemplateTupleParameter : TemplateParameter
{
	string ident;
	
	TemplateTupleParameter clone()
	{
		TemplateTupleParameter n = static_cast!TemplateTupleParameter(super.clone());
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
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	void toD(CodeWriter writer)
	{
		writer.writeIdentifier(ident);
		writer("...");
	}
}
//
//ClassTemplateDeclaration:
//    class Identifier ( TemplateParameterList ) BaseClassList_opt ClassBody
//
//InterfaceTemplateDeclaration:
//    interface Identifier ( TemplateParameterList ) Constraint_opt BaseInterfaceList_opt InterfaceBody
//
//TemplateMixinDeclaration:
//    mixin template TemplateIdentifier ( TemplateParameterList ) Constraint_opt { DeclDefs }

//TemplateMixin:
//    mixin TemplateIdentifier ;
//    mixin TemplateIdentifier MixinIdentifier ;
//    mixin TemplateIdentifier ! ( TemplateArgumentList ) ;
//    mixin TemplateIdentifier ! ( TemplateArgumentList ) MixinIdentifier ;
//
// translated to
//TemplateMixin:
//    mixin GlobalIdentifierList MixinIdentifier_opt ;
//    mixin Typeof . IdentifierList MixinIdentifier_opt ;
class TemplateMixin : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("mixin ", getMember(0));
		if(members.length > 1)
			writer(" ", getMember(1));
		writer(";");
		writer.nl();
	}
}

//
//Constraint:
//    if ( ConstraintExpression )
class Constraint : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(" if(", getMember(0), ")");
	}
}
//
//ConstraintExpression:
//    Expression
//
//MixinIdentifier:
//    Identifier
//
