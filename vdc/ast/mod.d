// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module ast.mod;

import util;
import semantic;
import simplelexer;

import ast.node;
import ast.decl;
import ast.expr;
import ast.misc;
import ast.aggr;

import std.conv;
import std.path;
import std.algorithm;

////////////////////////////////////////////////////////////////

//Module:
//    [ModuleDeclaration_opt DeclDef...]
class Module : Node
{
	mixin ForwardCtor!();

	string filename;
	bool imported;
	
	Module clone()
	{
		Module n = static_cast!Module(super.clone());
		n.filename = filename;
		n.imported = imported;
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.filename == filename
			&& tn.imported == imported;
	}
	
	
	Project getProject() { return static_cast!Project(parent); }
	
	void toD(CodeWriter writer)
	{
		foreach(m; members)
			writer(m);
	}

	void toC(CodeWriter writer)
	{
		if(members.length > 0 && cast(ModuleDeclaration) getMember(0))
		{
			auto fqn = getMember(0).getMember!ModuleFullyQualifiedName(0);

			foreach(m; fqn.members)
			{
				writer("namespace ", m, " {");
				writer.nl;
			}
			writer.nl;
			foreach(m; members[1..$])
				writer(m);

			writer.nl(false);
			foreach_reverse(m; fqn.members)
			{
				writer("} // namespace ", m);
				writer.nl;
			}
		}
		else
		{
			writer("namespace ", basename(filename), " {");
			writer.nl;
			foreach(m; members)
				writer(m);
			writer.nl(false);
			writer("} // namespace ", basename(filename));
			writer.nl;
		}
	}

	void writeNamespace(CodeWriter writer)
	{
		if(members.length > 0 && cast(ModuleDeclaration) getMember(0))
		{
			auto fqn = getMember(0).getMember!ModuleFullyQualifiedName(0);

			foreach(m; fqn.members)
				writer("::", m);
		}
		else
			writer("::", basename(filename));
		writer("::");
	}
	
	string getModuleName()
	{
		if(auto md = cast(ModuleDeclaration) getMember(0))
		{
			auto mfqn = md.getMember!ModuleFullyQualifiedName(0);
			string name = mfqn.getName();
			return name;
		}
		return getName(basename(filename));
	}

	static Module getModule(Node n)
	{
		while(n)
		{
			if(n.scop)
				return n.scop.mod;
			n = n.parent;
		}
		return null;
	}
	
	Node[] search(string ident)
	{
		if(!scop)
		{
			scop = new Scope;
			scop.mod = this;

			expandNonScopeMembers(scop);
			addMemberSymbols(scop);
		}
		return scop.search(ident);
	}
	
	void semantic(Scope sc)
	{
		if(imported) // no full semantic on imports
			return;
		
		// the order in which lazy semantic analysis takes place:
		// - evaluate/expand version/debug and static if conditionals
		// - analyze declarations:
		//   - instantiate templates
		//   - evaluate compile time expression
		//   to resolve identifiers:
		//     look in current scope, module
		//     if not found, search all imports
		if(!scop)
		{
			scop = sc.push(new Scope);
			scop.mod = this;
		}
		scope(exit) scop.pop();
		
		expandNonScopeMembers(scop);
		addMemberSymbols(scop);
		
		foreach(m; members)
		{
			m.semantic(scop);
		}
	}
	
	public /* debug & version handling */ {
	VersionDebug debugIds;
	VersionDebug versionIds;
	
	void specifyVersion(string ident, TextPos pos)
	{
		if(Options.versionPredefined(ident) != 0)
			semanticError("cannot define predifined version identifier " ~ ident);
		versionIds.define(ident, pos);
	}

	void specifyVersion(int level)
	{
		versionIds.level = max(level, versionIds.level);
	}

	bool versionEnabled(string ident, TextPos pos)
	{
		if(auto prj = getProject())
			if(prj.options.versionEnabled(ident))
				return true;
		if(versionIds.defined(ident, pos))
			return true;
		return false;
	}
	
	bool versionEnabled(int level)
	{
		if(auto prj = getProject())
			if(prj.options.versionEnabled(level))
				return true;
		return level <= versionIds.level;
	}

	void specifyDebug(string ident, TextPos pos)
	{
		debugIds.define(ident, pos);
	}

	void specifyDebug(int level)
	{
		debugIds.level = max(level, debugIds.level);
	}

	bool debugEnabled(string ident, TextPos pos)
	{
		if(auto prj = getProject())
			if(prj.options.debugEnabled(ident))
				return true;
		if(debugIds.defined(ident, pos))
			return true;
		return false;
	}
	
	bool debugEnabled(int level)
	{
		if(auto prj = getProject())
			if(prj.options.debugEnabled(level))
				return true;
		return level <= debugIds.level;
	}
	bool debugEnabled()
	{
		if(auto prj = getProject())
			return prj.options.debugOn;
		return false;
	}
	
	}
}

//ModuleDeclaration:
//    [ModuleFullyQualifiedName]
class ModuleDeclaration : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("module ", getMember(0), ";");
		writer.nl;
	}
}

//ModuleFullyQualifiedName:
//    [Identifier...]
class ModuleFullyQualifiedName : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer.writeArray(members, ".");
	}

	string getName()
	{
		string name = getMember!Identifier(0).ident;
		foreach(m; 1..members.length)
			name ~= "." ~ getMember!Identifier(m).ident;
		return name;
	}
}

//EmptyDeclDef:
//    []
class EmptyDeclDef : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(";");
		writer.nl;
	}
}

//AttributeSpecifier:
//    attributes annotations [DeclarationBlock_opt]
class AttributeSpecifier : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer.writeAttributes(attr);
		writer.writeAnnotations(annotation);
		
		switch(id)
		{
			case TOK_colon:
				assert(members.length == 0);
				writer(":");
				writer.nl;
				break;
			case TOK_lcurly:
				writer.nl;
				//writer("{");
				//writer.nl;
				//{
				//	CodeIndenter indent = CodeIndenter(writer);
					writer(getMember(0));
				//}
				//writer("}");
				//writer.nl;
				break;
			default:
				writer(getMember(0));
				break;
		}
	}

	void applyAttributes(Node m)
	{
		m.attr = combineAttributes(attr, m.attr);
		m.annotation = combineAnnotations(annotation, m.annotation);
	}
	
	Node[] expandNonScope(Scope sc, Node[] athis)
	{
		switch(id)
		{
			case TOK_colon:
				combineAttributes(sc.attributes, attr);
				combineAnnotations(sc.attributes, annotation);
				return [];
			case TOK_lcurly:
				auto db = getMember!DeclarationBlock(0);
				foreach(m; db.members)
					applyAttributes(m);
				return db.members;
			default:
				applyAttributes(getMember(0));
				return members;
		}
	}
}

//DeclarationBlock:
//    [DeclDef...]
class DeclarationBlock : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		if(id == TOK_lcurly)
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
		else
			foreach(m; members)
				writer(m);
	}
	
	Node[] expandNonScope(Scope sc, Node[] athis)
	{
		return members;
	}
}

//LinkageAttribute:
//    attribute
class LinkageAttribute : AttributeSpecifier
{
	mixin ForwardCtor!();
}
	
//AlignAttribute:
//    attribute
class AlignAttribute : AttributeSpecifier
{
	mixin ForwardCtor!();
}

//Pragma:
//    ident [TemplateArgumentList]
class Pragma : Node
{
	mixin ForwardCtor!();

	string ident;

	Pragma clone()
	{
		Pragma n = static_cast!Pragma(super.clone());
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
		writer("pragma(", ident);
		foreach(m; members)
			writer(", ", m);
		writer(")");
	}
}


//ImportDeclaration:
//    [ImportList]
class ImportDeclaration : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("import ", getMember(0), ";");
		writer.nl();
	}
	void toC(CodeWriter writer)
	{
	}
	
	void semantic(Scope sc)
	{
		getMember(0).semantic(sc);
	}
}

//ImportList:
//    [Import...]
class ImportList : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer.writeArray(members);
	}

	void semantic(Scope sc)
	{
		foreach(m; members)
			m.semantic(sc);
	}
}

//Import:
//    aliasIdent_opt [ModuleFullyQualifiedName 
//    ModuleAliasIdentifier = ModuleFullyQualifiedName
//
//ModuleAliasIdentifier:
//    Identifier
class Import : Node
{
	mixin ForwardCtor!();

	string aliasIdent;
	ImportBindList getImportBindList() { return members.length > 1 ? getMember!ImportBindList(1) : null; }
	
	// semantic data
	Module mod;
	int countLookups;
	int countFound;
		
	Import clone()
	{
		Import n = static_cast!Import(super.clone());
		n.aliasIdent = aliasIdent;
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.aliasIdent == aliasIdent;
	}
	
	void toD(CodeWriter writer)
	{
		if(aliasIdent.length)
			writer(aliasIdent, " = ");
		writer(getMember(0));
		if(auto bindList = getImportBindList())
			writer(" : ", bindList);
	}

	void semantic(Scope sc)
	{
		sc.addImport(this);
	}

	void addSymbols(Scope sc)
	{
		if(aliasIdent.length > 0)
			sc.addSymbol(aliasIdent, this);
	}

	Node[] search(Scope sc, string ident)
	{
		if(!mod)
			if(auto prj = sc.mod.getProject())
				mod = prj.importModule(getModuleName());
		
		if(!mod)
			return [];
		
		return mod.search(ident);
	}

	string getModuleName()
	{
		auto mfqn = getMember!ModuleFullyQualifiedName(0);
		return mfqn.getName();
	}
}

unittest
{
	verifyParseWrite(q{ import test; });
	verifyParseWrite(q{ import ntest = pkg.test; });
	verifyParseWrite(q{ import io = std.stdio : writeln, write; });
}
			
						   
//ImportBindList:
//    ImportBind
//    ImportBind , ImportBindList
class ImportBindList : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer.writeArray(members);
	}
}


//ImportBind:
//    Identifier
//    Identifier = Identifier
class ImportBind : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer(getMember(0));
		if(members.length > 1)
			writer(" = ", getMember(1));
	}
}

//MixinDeclaration:
//    mixin ( AssignExpression ) ;
class MixinDeclaration : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("mixin(", getMember(0), ");");
		writer.nl;
	}
}

//Unittest:
//    unittest BlockStatement
class Unittest : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("unittest");
		writer.nl;
		writer(getMember(0));
	}

	void toC(CodeWriter writer)
	{
	}
}
