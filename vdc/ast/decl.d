// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.decl;

import vdc.util;
import vdc.lexer;
import vdc.semantic;
import vdc.interpret;

import vdc.ast.node;
import vdc.ast.expr;
import vdc.ast.misc;
import vdc.ast.aggr;
import vdc.ast.tmpl;
import vdc.ast.stmt;
import vdc.ast.type;
import vdc.ast.mod;

import std.conv;

//Declaration:
//    alias Decl
//    Decl
class Declaration : Node
{
	mixin ForwardCtor!();
}

// AliasDeclaration:
//    [Decl]
class AliasDeclaration : Node
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
	{
		if(writer.writeDeclarations)
			writer("alias ", getMember(0));
	}
	override void addSymbols(Scope sc)
	{
		getMember(0).addSymbols(sc);
	}
}

//Decl:
//    attributes annotations [Type Declarators FunctionBody_opt]
class Decl : Node
{
	mixin ForwardCtor!();

	bool hasSemi;
	bool isAlias;
	
	Type getType() { return getMember!Type(0); }
	Declarators getDeclarators() { return getMember!Declarators(1); }
	FunctionBody getFunctionBody() { return getMember!FunctionBody(2); }
	
	override Decl clone()
	{
		Decl n = static_cast!Decl(super.clone());
		n.hasSemi = hasSemi;
		n.isAlias = isAlias;
		return n;
	}
	
	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.hasSemi == hasSemi
			&& tn.isAlias == isAlias;
	}

	override void toD(CodeWriter writer)
	{
		if(isAlias)
			writer(TOK_alias, " ");
		writer.writeAttributes(attr);
		writer.writeAnnotations(annotation);
		
		writer(getType(), " ", getDeclarators());
		bool semi = true;
		if(auto fn = getFunctionBody())
		{
			if(writer.writeImplementations)
			{
				writer.nl;
				writer(fn);
				semi = hasSemi;
			}
		}
		if(semi)
		{
			writer(";");
			writer.nl();
		}
	}

	override void toC(CodeWriter writer)
	{
		bool addExtern = false;
		if(!isAlias && writer.writeDeclarations && !(attr & Attr_ExternC))
		{
			Node p = parent;
			while(p && !cast(Aggregate) p && !cast(TemplateDeclaration) p && !cast(Statement) p)
				p = p.parent;
			
			if(!p)
				addExtern = true;
		}
		if(auto fn = getFunctionBody())
		{
			if(writer.writeReferencedOnly && getDeclarators().getDeclarator(0).semanticSearches == 0)
				return;
				
			writer.nl;
			if(isAlias)
				writer(TOK_alias, " ");
			writer.writeAttributes(attr | (addExtern ? Attr_Extern : 0));
			writer.writeAnnotations(annotation);
			
			bool semi = true;
			writer(getType(), " ", getDeclarators());
			if(writer.writeImplementations)
			{
				writer.nl;
				writer(fn);
				semi = hasSemi;
			}
			if(semi)
			{
				writer(";");
				writer.nl();
			}
		}
		else
		{
			foreach(i, d; getDeclarators().members)
			{
				if(writer.writeReferencedOnly && getDeclarators().getDeclarator(i).semanticSearches == 0)
					continue;
				
				if(isAlias)
					writer(TOK_alias, " ");
				writer.writeAttributes(attr | (addExtern ? Attr_Extern : 0));
				writer.writeAnnotations(annotation);
				
				writer(getType(), " ", d, ";");
				writer.nl();
			}
		}
	}
	
	override void addSymbols(Scope sc)
	{
		getDeclarators().addSymbols(sc);
	}

	override void _semantic(Scope sc)
	{
		if(auto fn = getFunctionBody())
		{
			// if it is a function declaration, create a new scope including function parameters
			scop = sc.push(scop);
			if(auto decls = getDeclarators())
				if(auto decl = decls.getDeclarator(0))
				{
					foreach(m; decl.members) // template parameters and function parameters and constraint
					{
						m.addSymbols(scop);
					}
				}
			
			super._semantic(scop);
			//fn.semantic(scop);
			sc = scop.pop();
		}
		else
			super._semantic(sc);
	}
}

//Declarators:
//    [DeclaratorInitializer|Declarator...]
class Declarators : Node
{
	mixin ForwardCtor!();

	Declarator getDeclarator(int n)
	{
		if(auto decl = cast(Declarator) getMember(n))
			return decl;

		return getMember!DeclaratorInitializer(n).getDeclarator();
	}
	
	override void toD(CodeWriter writer)
	{
		writer(getMember(0));
		foreach(decl; members[1..$])
			writer(", ", decl);
	}
	override void addSymbols(Scope sc)
	{
		foreach(decl; members)
			decl.addSymbols(sc);
	}
}

//DeclaratorInitializer:
//    [Declarator Initializer_opt]
class DeclaratorInitializer : Node
{
	mixin ForwardCtor!();
	
	Declarator getDeclarator() { return getMember!Declarator(0); }
	Expression getInitializer() { return getMember!Expression(1); }

	override void toD(CodeWriter writer)
	{
		writer(getMember(0));
		if(Expression expr = getInitializer())
		{
			if(expr.getPrecedence() <= PREC.assign)
				writer(" = (", expr, ")");
			else
				writer(" = ", getMember(1));
		}
	}

	override void addSymbols(Scope sc)
	{
		getDeclarator().addSymbols(sc);
	}
}

// unused
class DeclaratorIdentifierList : Node
{
	mixin ForwardCtor!();
	
	override void toD(CodeWriter writer)
	{
		assert(false);
	}
}

// unused
class DeclaratorIdentifier : Node
{
	mixin ForwardCtor!();
	
	override void toD(CodeWriter writer)
	{
		assert(false);
	}
}

class Initializer : Expression
{
	mixin ForwardCtor!();
}

//Declarator:
//    Identifier [DeclaratorSuffixes...]
class Declarator : Identifier
{
	mixin ForwardCtorTok!();

	Type type;
	Value value;
	
	Expression getInitializer()
	{
		if(auto di = cast(DeclaratorInitializer) parent)
			return di.getInitializer();
		return null;
	}
	
	override void toD(CodeWriter writer)
	{
		super.toD(writer);
		foreach(m; members) // template parameters and function parameters and constraint
			writer(m);
	}

	bool isAlias()
	{
		for(Node p = parent; p; p = p.parent)
			if(auto decl = cast(Decl) p)
				return decl.isAlias;
			else if(auto pdecl = cast(ParameterDeclarator) p)
				break;
		return false;
	}
	
	override void addSymbols(Scope sc)
	{
		sc.addSymbol(ident, this);
	}

	Type applySuffixes(Type t)
	{
		foreach(m; members) // template parameters and function parameters and constraint
		{
			if(auto pl = cast(ParameterList) m)
			{
				auto tf = new TypeFunction(pl.id, pl.span);
				tf.mInit = this;
				tf.addMember(t.clone());
				tf.addMember(pl.clone());
				t = tf;
			}
			else if(auto saa = cast(SuffixAssocArray) m)
			{
				auto taa = new TypeAssocArray(saa.id, saa.span);
				taa.addMember(t.clone());
				taa.addMember(saa.getKeyType().clone());
				t = taa;
			}
			else if(auto sda = cast(SuffixDynamicArray) m)
			{
				auto tda = new TypeDynamicArray(sda.id, sda.span);
				tda.addMember(t.clone());
				t = tda;
			}
			else if(auto ssa = cast(SuffixStaticArray) m)
			{
				auto tsa = new TypeStaticArray(ssa.id, ssa.span);
				tsa.addMember(t.clone());
				tsa.addMember(ssa.getDimension().clone());
				t = tsa;
			}
			// TODO: slice suffix? template parameters, constraint
		}
		return t;
	}
	
	override Type calcType(Scope sc)
	{
		if(type)
			return type;
		
		for(Node p = parent; p; p = p.parent)
		{
			if(auto decl = cast(Decl) p)
			{
				type = decl.getType();
				if(type)
				{
					type = applySuffixes(type);
					type = type.calcType(sc);
				}
				return type;
			}
			else if(auto pdecl = cast(ParameterDeclarator) p)
			{
				type = pdecl.getType();
				if(type)
				{
					type = applySuffixes(type);
					type = type.calcType(sc);
				}
				return type;
			}
		}
		semanticError("cannot find Declarator type");
		return null;
	}

	override Value interpret(Scope sc)
	{
		if(value)
			return value;
		
		Type type = calcType(sc);
		if(!type)
			value = new ErrorValue;
		else if(isAlias())
			value = new TypeValue(type);
		else
		{
			value = type.createValue();
			if(auto expr = getInitializer())
				value.opBin(TOK_assign, expr.interpret(sc));
		}
		return value;
	}
	
	Value interpretCall(Scope sc)
	{
		for(Node p = parent; p; p = p.parent)
			if(auto decl = cast(Decl) p)
			{
				if(auto fbody = decl.getFunctionBody())
					return fbody.interpret(sc);
				semanticError(ident, " is not a interpretable function");
				return new ErrorValue;
			}

		semanticError("cannot interpret external function ", ident);
		return new ErrorValue;
	}
}

//IdentifierList:
//    [IdentifierOrTemplateInstance...]
class IdentifierList : Node
{
	mixin ForwardCtor!();

	bool global;
	
	// semantic data
	Node resolved;
	
	override IdentifierList clone()
	{
		IdentifierList n = static_cast!IdentifierList(super.clone());
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
	
	override void _semantic(Scope sc)
	{
		// TODO: does not work for package qualified symbols
		if(global)
			sc = Module.getModule(this).scop;

		for(int m = 0; sc && m < members.length; m++)
		{
			string ident = getMember!Identifier(m).ident;
			resolved = sc.resolve(ident, span);
			sc = (resolved ? resolved.scop : null);
		}
	}
	
	override void toD(CodeWriter writer)
	{
		if(global)
			writer(".");
		writer.writeArray(members, ".");
	}
}

class Identifier : Node
{
	string ident;
	
	this() {} // default constructor needed for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	override Identifier clone()
	{
		Identifier n = static_cast!Identifier(super.clone());
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
		writer.writeIdentifier(ident);
	}
}

//ParameterList:
//    [Parameter...] attributes
class ParameterList : Node
{
	mixin ForwardCtor!();

	Parameter getParameter(int i) { return getMember!Parameter(i); }

	bool varargs;
	
	override ParameterList clone()
	{
		ParameterList n = static_cast!ParameterList(super.clone());
		n.varargs = varargs;
		return n;
	}

	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.varargs == varargs;
	}
	
	override void toD(CodeWriter writer)
	{
		writer("(");
		writer.writeArray(members);
		if(varargs)
			writer("...");
		writer(")");
		if(attr)
		{
			writer(" ");
			writer.writeAttributes(attr);
		}
	}
	
	override void addSymbols(Scope sc)
	{
		foreach(m; members)
			m.addSymbols(sc);
	}
}

//Parameter:
//    io [ParameterDeclarator Expression_opt]
class Parameter : Node
{
	mixin ForwardCtor!();

	TokenId io;
	
	ParameterDeclarator getParameterDeclarator() { return getMember!ParameterDeclarator(0); }
	
	override Parameter clone()
	{
		Parameter n = static_cast!Parameter(super.clone());
		n.io = io;
		return n;
	}

	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.io == io;
	}
	
	override void toD(CodeWriter writer)
	{
		if(io)
			writer(io, " ");
		writer(getMember(0));
		if(members.length > 1)
			writer(" = ", getMember(1));
	}

	override void addSymbols(Scope sc)
	{
		getParameterDeclarator().addSymbols(sc);
	}
}

//ParameterDeclarator:
//    attributes [Type Declarator]
class ParameterDeclarator : Node
{
	mixin ForwardCtor!();

	Type getType() { return getMember!Type(0); }
	Declarator getDeclarator() { return members.length > 1 ? getMember!Declarator(1) : null; }
	
	override void toD(CodeWriter writer)
	{
		writer.writeAttributes(attr);
		writer(getType());
		if(auto decl = getDeclarator())
			writer(" ", decl);
	}
	
	override void addSymbols(Scope sc)
	{
		if (auto decl = getDeclarator())
			decl.addSymbols(sc);
	}
}
