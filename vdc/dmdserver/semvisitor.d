// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.semvisitor;

import vdc.ivdserver : TypeReferenceKind;

import dmd.access;
import dmd.aggregate;
import dmd.apply;
import dmd.arraytypes;
import dmd.attrib;
import dmd.ast_node;
import dmd.builtin;
import dmd.cond;
import dmd.console;
import dmd.dclass;
import dmd.declaration;
import dmd.denum;
import dmd.dimport;
import dmd.dinterpret;
import dmd.dmodule;
import dmd.dscope;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dsymbolsem;
import dmd.dtemplate;
import dmd.errors;
import dmd.expression;
import dmd.func;
import dmd.globals;
import dmd.hdrgen;
import dmd.id;
import dmd.identifier;
import dmd.init;
import dmd.mtype;
import dmd.objc;
import dmd.sapply;
import dmd.semantic2;
import dmd.semantic3;
import dmd.statement;
import dmd.target;
import dmd.tokens;
import dmd.visitor;

import dmd.root.outbuffer;
import dmd.root.file;
import dmd.root.filename;
import dmd.root.rmem;
import dmd.root.rootobject;

import std.algorithm;
import std.string;
import std.conv;
import stdext.array;
import core.stdc.string;

// walk the complete AST (declarations, statement and expressions)
// assumes being started on module/declaration level
extern(C++) class ASTVisitor : StoppableVisitor
{
	bool unconditional; // take both branches in conditional declarations/statements

	alias visit = StoppableVisitor.visit;

	ASTNode[] visiting;
	size_t currentVisiting;

	void visitExpression(Expression expr)
	{
		if (stop || !expr)
			return;

		if (currentVisiting >= visiting.length)
			visiting ~= expr;
		else
			visiting[currentVisiting] = expr;
		currentVisiting++;

		if (walkPostorder(expr, this))
			stop = true;

		visiting[--currentVisiting] = null;
	}

	void visitStatement(Statement stmt)
	{
		if (stop || !stmt)
			return;

		if (currentVisiting >= visiting.length)
			visiting ~= stmt;
		else
			visiting[currentVisiting] = stmt;
		currentVisiting++;

		if (walkPostorder(stmt, this))
			stop = true;

		visiting[--currentVisiting] = null;
	}

	void visitDeclaration(Dsymbol sym)
	{
		if (stop || !sym)
			return;

		sym.accept(this);
	}

	// default to being permissive
	override void visit(Parameter) {}
	override void visit(TemplateParameter) {}

	// expressions
	override void visit(Expression expr)
	{
		if (expr.original && expr.original != expr)
			if (!visiting.contains(expr.original))
				visitExpression(expr.original);
	}

	override void visit(ErrorExp errexp)
	{
		visit(cast(Expression)errexp);
	}

	override void visit(IsExp ie)
	{
		// TODO: has ident
		if (ie.targ)
			ie.targ.accept(this);
		if (ie.originaltarg && ie.originaltarg !is ie.targ)
			ie.originaltarg.accept(this);

		visit(cast(Expression)ie);
	}

	override void visit(DeclarationExp expr)
	{
		visitDeclaration(expr.declaration);
		visit(cast(Expression)expr);
	}

	override void visit(TypeExp expr)
	{
		if (expr.type)
			expr.type.accept(this);
		visit(cast(Expression)expr);
	}

	override void visit(FuncExp expr)
	{
		visitDeclaration(expr.fd);
		visitDeclaration(expr.td);

		visit(cast(Expression)expr);
	}

	// types
	override void visit(Type) {}

	override void visit(TypeTypeof t)
	{
		visitExpression(t.exp);
	}

	// symbols
	override void visit(Dsymbol) {}

	override void visit(ScopeDsymbol scopesym)
	{
		// optimize to only visit members in approriate source range
		size_t mcnt = scopesym.members ? scopesym.members.dim : 0;
		for (size_t m = 0; !stop && m < mcnt; m++)
		{
			Dsymbol s = (*scopesym.members)[m];
			s.accept(this);
		}
	}

	// declarations
	override void visit(VarDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (!stop && decl._init)
			decl._init.accept(this);
	}

	override void visit(AttribDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (!stop)
			if (unconditional)
			{
				if (decl.decl)
					foreach(d; *decl.decl)
						if (!stop)
							d.accept(this);
			}
			else if (auto inc = decl.include(null))
				foreach(d; *inc)
					if (!stop)
						d.accept(this);
	}

	override void visit(ConditionalDeclaration decl)
	{
		if (!stop && decl.condition)
			decl.condition.accept(this);

		visit(cast(AttribDeclaration)decl);

		if (!stop && unconditional && decl.elsedecl)
			foreach(d; *decl.elsedecl)
				if (!stop)
					d.accept(this);
	}

	override void visit(FuncDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (decl.parameters)
			foreach(p; *decl.parameters)
				if (!stop)
					p.accept(this);

		if (decl.frequires)
			foreach(s; *decl.frequires)
				visitStatement(s);
		if (decl.fensures)
			foreach(e; *decl.fensures)
				visitStatement(e.ensure); // TODO: check result ident

		visitStatement(decl.frequire);
		visitStatement(decl.fensure);
		visitStatement(decl.fbody);
	}

	// condition
	override void visit(Condition) {}

	override void visit(StaticIfCondition cond)
	{
		visitExpression(cond.exp);
		visit(cast(Condition)cond);
	}

	// initializer
	override void visit(Initializer) {}

	override void visit(ExpInitializer einit)
	{
		visitExpression(einit.exp);
	}

	override void visit(VoidInitializer vinit)
	{
	}

	override void visit(ErrorInitializer einit)
	{
		if (einit.original)
			einit.original.accept(this);
	}

	override void visit(StructInitializer sinit)
	{
		foreach (i, const id; sinit.field)
			if (auto iz = sinit.value[i])
				iz.accept(this);
	}

	override void visit(ArrayInitializer ainit)
	{
		foreach (i, ex; ainit.index)
		{
			if (ex)
				ex.accept(this);
			if (auto iz = ainit.value[i])
				iz.accept(this);
		}
	}

	// statements
	override void visit(Statement stmt)
	{
		if (stmt.original)
			if (!visiting.contains(stmt.original))
				visitStatement(stmt.original);
	}

	override void visit(ExpStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(ConditionalStatement stmt)
	{
		if (!stop && stmt.condition)
		{
			stmt.condition.accept(this);

			if (unconditional)
			{
				visitStatement(stmt.ifbody);
				visitStatement(stmt.elsebody);
			}
			else if (stmt.condition.include(null))
				visitStatement(stmt.ifbody);
			else
				visitStatement(stmt.elsebody);
		}
		visit(cast(Statement)stmt);
	}

	override void visit(CompileStatement stmt)
	{
		if (stmt.exps)
			foreach(e; *stmt.exps)
				if (!stop)
					e.accept(this);
		visit(cast(Statement)stmt);
	}

	override void visit(WhileStatement stmt)
	{
		visitExpression(stmt.condition);
		visit(cast(Statement)stmt);
	}

	override void visit(DoStatement stmt)
	{
		visitExpression(stmt.condition);
		visit(cast(Statement)stmt);
	}

	override void visit(ForStatement stmt)
	{
		visitExpression(stmt.condition);
		visitExpression(stmt.increment);
		visit(cast(Statement)stmt);
	}

	override void visit(ForeachStatement stmt)
	{
		if (stmt.parameters)
			foreach(p; *stmt.parameters)
				if (!stop)
					p.accept(this);
		visitExpression(stmt.aggr);
		visit(cast(Statement)stmt);
	}

	override void visit(ForeachRangeStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.lwr);
		visitExpression(stmt.upr);
		visit(cast(Statement)stmt);
	}

	override void visit(IfStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.condition);
		visit(cast(Statement)stmt);
	}

	override void visit(PragmaStatement stmt)
	{
		if (!stop && stmt.args)
			foreach(a; *stmt.args)
				if (!stop)
					a.accept(this);
		visit(cast(Statement)stmt);
	}

	override void visit(StaticAssertStatement stmt)
	{
		visitExpression(stmt.sa.exp);
		visitExpression(stmt.sa.msg);
		visit(cast(Statement)stmt);
	}

	override void visit(SwitchStatement stmt)
	{
		visitExpression(stmt.condition);
		visit(cast(Statement)stmt);
	}

	override void visit(CaseStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(CaseRangeStatement stmt)
	{
		visitExpression(stmt.first);
		visitExpression(stmt.last);
		visit(cast(Statement)stmt);
	}

	override void visit(GotoCaseStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(ReturnStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(SynchronizedStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(WithStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(TryCatchStatement stmt)
	{
		// variables not looked at by PostorderStatementVisitor
		if (!stop && stmt.catches)
			foreach(c; *stmt.catches)
				visitDeclaration(c.var);
		visit(cast(Statement)stmt);
	}

	override void visit(ThrowStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(ImportStatement stmt)
	{
		if (!stop && stmt.imports)
			foreach(i; *stmt.imports)
				visitDeclaration(i);
		visit(cast(Statement)stmt);
	}
}

extern(C++) class FindASTVisitor : ASTVisitor
{
	const(char*) filename;
	int startLine;
	int startIndex;
	int endLine;
	int endIndex;

	alias visit = ASTVisitor.visit;
	RootObject found;
	ScopeDsymbol foundScope;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		this.filename = filename;
		this.startLine = startLine;
		this.startIndex = startIndex;
		this.endLine = endLine;
		this.endIndex = endIndex;
	}

	bool foundNode(RootObject obj)
	{
		if (obj)
		{
			found = obj;
			stop = true;
		}
		return stop;
	}

	bool matchIdentifier(ref const Loc loc, Identifier ident)
	{
		if (ident)
			if (loc.filename is filename)
				if (loc.linnum == startLine && loc.linnum == endLine)
					if (loc.charnum <= startIndex && loc.charnum + ident.toString().length >= endIndex)
						return true;
		return false;
	}

	bool visitPackages(IdentifiersAtLoc* packages)
	{
		if (packages)
			for (size_t p; p < packages.dim; p++)
				if (!found && matchIdentifier((*packages)[p].loc, (*packages)[p].ident))
				{
					Package pkg;
					auto pkgs = new IdentifiersAtLoc();
					for (size_t q = 0; q <= p; q++)
						pkgs.push((*packages)[p]);
					Package.resolve(pkgs, null, &pkg);
					if (pkg)
						foundNode(pkg);
					return true;
				}
		return false;
	}

	bool matchLoc(ref const(Loc) loc, int len)
	{
		if (loc.filename is filename)
			if (loc.linnum == startLine && loc.linnum == endLine)
				if (loc.charnum <= startIndex && loc.charnum + len >= endIndex)
					return true;
		return false;
	}

	override void visit(Dsymbol sym)
	{
		if (!found && matchIdentifier(sym.loc, sym.ident))
			foundNode(sym);
	}

	override void visit(Parameter sym)
	{
		if (!found && matchIdentifier(sym.ident.loc, sym.ident))
			foundNode(sym);
	}

	override void visit(Module mod)
	{
		if (mod.md)
		{
			visitPackages(mod.md.packages);

			if (!found && matchIdentifier(mod.md.loc, mod.md.id))
				foundNode(mod);
		}
		visit(cast(Package)mod);
	}

	override void visit(Import imp)
	{
		visitPackages(imp.packages);

		if (!found && matchIdentifier(imp.loc, imp.id))
			foundNode(imp.mod);

		for (int n = 0; !found && n < imp.names.dim; n++)
			if (matchIdentifier(imp.names[n].loc, imp.names[n].ident) ||
				matchIdentifier(imp.aliases[n].loc, imp.aliases[n].ident))
				if (n < imp.aliasdecls.dim)
					foundNode(imp.aliasdecls[n]);

		// symbol has ident of first package, so don't forward
	}

	override void visit(DVCondition cond)
	{
		if (!found && matchIdentifier(cond.loc, cond.ident))
			foundNode(cond);
	}

	override void visit(TypeIdentifier t)
	{
		visitTypeIdentifier(t, t);
		visit(cast(TypeQualified)t);
	}

	override void visit(Expression expr)
	{
		super.visit(expr);
	}

	override void visit(CastExp expr)
	{
		visitTypeIdentifier(expr.parsedTo, expr.to, true);
		if (expr.parsedTo != expr.to)
			visitTypeIdentifier(expr.to, expr.to);
		super.visit(expr);
	}

	override void visit(CompoundStatement cs)
	{
		// optimize to only visit members in approriate source range
		size_t scnt = cs.statements ? cs.statements.dim : 0;
		for (size_t i = 0; i < scnt && !stop; i++)
		{
			Statement s = (*cs.statements)[i];
			if (!s)
				continue;
			if (visiting.contains(s))
				continue;

			if (s.loc.filename)
			{
				if (s.loc.filename !is filename || s.loc.linnum > endLine)
					continue;
				Loc endloc;
				if (auto ss = s.isScopeStatement())
					endloc = ss.endloc;
				else if (auto ws = s.isWhileStatement())
					endloc = ws.endloc;
				else if (auto ds = s.isDoStatement())
					endloc = ds.endloc;
				else if (auto fs = s.isForStatement())
					endloc = fs.endloc;
				else if (auto fs = s.isForeachStatement())
					endloc = fs.endloc;
				else if (auto fs = s.isForeachRangeStatement())
					endloc = fs.endloc;
				else if (auto ifs = s.isIfStatement())
					endloc = ifs.endloc;
				else if (auto ws = s.isWithStatement())
					endloc = ws.endloc;
				if (endloc.filename && endloc.linnum < startLine)
					continue;
			}
			s.accept(this);
		}
		visit(cast(Statement)cs);
	}

	override void visit(ScopeDsymbol scopesym)
	{
		// optimize to only visit members in approriate source range
		// unfortunately, some members don't have valid locations
		size_t mcnt = scopesym.members ? scopesym.members.dim : 0;
		for (size_t m = 0; m < mcnt && !stop; m++)
		{
			Dsymbol s = (*scopesym.members)[m];
			if (s.isTemplateInstance)
				continue;
			if (s.loc.filename)
			{
				if (s.loc.filename !is filename || s.loc.linnum > endLine)
					continue;
				Loc endloc;
				if (auto fd = s.isFuncDeclaration())
					endloc = fd.endloc;
				if (endloc.filename && endloc.linnum < startLine)
					continue;
			}
			s.accept(this);
		}
		if (found && !foundScope)
			foundScope = scopesym;
	}

	override void visit(ScopeStatement ss)
	{
		visit(cast(Statement)ss);
		if (found && !foundScope)
			foundScope = ss.scopesym;
	}

	override void visit(TemplateInstance ti)
	{
		// skip members added by semantic
		visit(cast(ScopeDsymbol)ti);
	}

	override void visit(TemplateDeclaration td)
	{
		foreach(ti; td.instances)
			if (!stop)
				visit(ti);

		visit(cast(ScopeDsymbol)td);
	}

	override void visit(CallExp expr)
	{
		super.visit(expr);
	}

	override void visit(ScopeExp expr)
	{
		if (auto ti = expr.sds.isTemplateInstance())
		{
			if (ti.tiargs && ti.parsedArgs)
			{
				size_t args = min(ti.tiargs.dim, ti.parsedArgs.dim);
				for (size_t a = 0; a < args; a++)
					if (Type tip = (*ti.parsedArgs)[a].isType())
						if (Type tir = (*ti.tiargs)[a].isType())
							visitTypeIdentifier(tip, tir);
			}
		}
		super.visit(expr);
	}

	override void visit(SymbolExp expr)
	{
		if (!found && expr.var)
			if (matchIdentifier(expr.loc, expr.var.ident))
				foundNode(expr);
		super.visit(expr);
	}
	override void visit(NewExp ne)
	{
		if (!found && matchLoc(ne.loc, 99))
			if (ne.member)
				foundNode(ne.member);
			else
				foundNode(ne.newtype);
	}

	override void visit(IdentifierExp expr)
	{
		if (!found && expr.ident)
		{
			if (matchIdentifier(expr.loc, expr.ident))
			{
				if (expr.type)
					foundNode(expr.type);
				else if (expr.original)
				{
					if (auto se = expr.original.isScopeExp())
						foundNode(se.sds);
					else
						foundNode(expr.original.type);
				}
			}
		}
		visit(cast(Expression)expr);
	}

	override void visit(DotIdExp de)
	{
		if (!found)
			if (de.ident)
				if (matchIdentifier(de.identloc, de.ident))
				{
					if (de.type)
						foundNode(de);
					else if (de.original)
					{
						if (auto se = de.original.isScopeExp())
							foundNode(se.sds);
						else
							foundNode(de.original.type);
					}
					else
						foundNode(de);
				}
	}

	override void visit(DotExp de)
	{
		if (!found)
		{
			// '.' of erroneous DotIdExp
			if (matchLoc(de.loc, 2))
				foundNode(de);
		}
	}

	override void visit(DotTemplateExp dte)
	{
		if (!found && dte.td && dte.td.ident)
			if (matchIdentifier(dte.identloc, dte.td.ident))
				foundNode(dte);
	}

	override void visit(TemplateExp te)
	{
		if (!found && te.td && te.td.ident)
			if (matchIdentifier(te.identloc, te.td.ident))
				foundNode(te);
	}

	override void visit(DotVarExp dve)
	{
		if (!found && dve.var && dve.var.ident)
			if (matchIdentifier(dve.varloc.filename ? dve.varloc : dve.loc, dve.var.ident))
				foundNode(dve);
	}

	override void visit(VarDeclaration decl)
	{
		visitTypeIdentifier(decl.parsedType, decl.type, true);
		if (!found && decl.originalType != decl.parsedType)
			visitTypeIdentifier(decl.originalType, decl.type);
		if (!found && decl.type != decl.originalType && decl.type != decl.parsedType)
			visitTypeIdentifier(decl.type, decl.type); // not yet semantically analyzed (or a template declaration)
		super.visit(decl);
	}

	override void visit(EnumDeclaration ed)
	{
		if (!found && ed.ident)
			if (matchIdentifier(ed.loc, ed.ident))
				foundNode(ed);

		visit(cast(ScopeDsymbol)ed);
	}

	override void visit(AggregateDeclaration ad)
	{
		if (!found && ad.ident)
			if (matchIdentifier(ad.loc, ad.ident))
				foundNode(ad);

		visit(cast(ScopeDsymbol)ad);
	}

	override void visit(ClassDeclaration cd)
	{
		if (cd.baseclasses)
		{
			foreach (bc; *(cd.baseclasses))
			{
				visitTypeIdentifier(bc.parsedType, bc.type);
			}
		}
		visit(cast(AggregateDeclaration)cd);
	}

	override void visit(FuncDeclaration decl)
	{
		super.visit(decl);

		if (found && !foundScope)
			foundScope = decl.scopesym;

		visitTypeIdentifier(decl.originalType, decl.type);
	}

	void visitTypeIdentifier(Type originalType, Type resolvedType, bool syntaxCopiedOriginal = false)
	{
		if (found || !originalType || !resolvedType)
			return;
		while (originalType.ty != Tident)
		{
			// val[max] is parsed as an AA, but can be resolved to a static array
			if (originalType.ty != resolvedType.ty &&
				!(originalType.ty == Taarray && resolvedType.ty == Tsarray))
				return;
			switch (resolvedType.ty)
			{
				case Tsarray:
				{
					auto resolvedSA = cast(TypeSArray) resolvedType;
					visitExpression(resolvedSA.dim);
					goto case Tarray;
				}
				case Taarray:
				{
					auto originalAA = cast(TypeAArray) originalType;
					auto resolvedAA = cast(TypeAArray) resolvedType;
					visitTypeIdentifier(originalAA.index, resolvedAA.index);
					if (found)
						return;
					goto case;
				}
				case Tarray:
				case Tpointer:
				case Treference:
				case Tvector:
				case Tfunction:
					originalType = (cast(TypeNext) originalType).next;
					resolvedType = (cast(TypeNext) resolvedType).next;
					if (!originalType || !resolvedType)
						return;
					break;
				default:
					return;
			}
		}
		auto otype = cast(TypeIdentifier) originalType;
		if (otype.copiedFrom && syntaxCopiedOriginal)
			otype = otype.copiedFrom;
		Loc loc = otype.loc;
		if (matchIdentifier(loc, otype.ident))
		{
			if (otype.parentScopes.dim > 0)
				foundNode(otype.parentScopes[0]);
			else
				foundNode(resolvedType);
		}
		else
		{
			// guess qualified name to be without spaces
			foreach (i, id; otype.idents)
			{
				RootObject obj = id;
				if (obj.dyncast() == DYNCAST.identifier)
				{
					auto ident = cast(Identifier)obj;
					if (matchIdentifier(id.loc, ident))
						if (otype.parentScopes.dim > i + 1)
							foundNode(otype.parentScopes[i + 1]);
						else
							foundNode(resolvedType);
				}
			}
		}
	}
}

RootObject _findAST(Dsymbol sym, const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
{
	scope FindASTVisitor fav = new FindASTVisitor(filename, startLine, startIndex, endLine, endIndex);
	sym.accept(fav);

	return fav.found;
}

RootObject findAST(Module mod, int startLine, int startIndex, int endLine, int endIndex)
{
	auto filename = mod.srcfile.toChars();
	return _findAST(mod, filename, startLine, startIndex, endLine, endIndex);
}

////////////////////////////////////////////////////////////////////////////////

extern(C++) class FindTipVisitor : FindASTVisitor
{
	string tip;

	alias visit = FindASTVisitor.visit;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		super(filename, startLine, startIndex, endLine, endIndex);
	}

	void visitCallExpression(CallExp expr)
	{
		if (!found)
		{
			// replace function type with actual
			visitExpression(expr);
			if (found is expr.e1)
			{
				foundNode(expr);
			}
		}
	}

	override bool foundNode(RootObject obj)
	{
		found = obj;
		if (obj)
		{
			tip = tipForObject(obj, true);
			stop = true;
		}
		return stop;
	}
}

string quoteCode(bool quote, string s)
{
	if (!quote || s.empty)
		return s;
	return "`" ~ s ~ "`";
}

string tipForObject(RootObject obj, bool quote)
{
	string tipForDeclaration(Declaration decl)
	{
		if (auto func = decl.isFuncDeclaration())
		{
			OutBuffer buf;
			if (decl.type)
				functionToBufferWithIdent(decl.type.toTypeFunction(), &buf, decl.toPrettyChars());
			else
				buf.writestring(decl.toPrettyChars());
			auto res = buf.peekSlice();
			buf.extractSlice(); // take ownership
			return quoteCode(quote, cast(string)res);
		}

		bool fqn = true;
		string txt;
		string kind;
		if (decl.isParameter())
		{
			if (decl.parent)
				if (auto fd = decl.parent.isFuncDeclaration())
					if (fd.ident.toString().startsWith("__foreachbody"))
						kind = "(foreach variable) ";
			if (kind.empty)
				kind = "(parameter) ";
			fqn = false;
		}
		else if (auto em = decl.isEnumMember())
		{
			kind = "(enum value) ";
			txt = decl.toPrettyChars(fqn).to!string;
			if (em.origValue)
				txt ~= " = " ~ cast(string)em.origValue.toString();
			return kind ~ quoteCode(quote, txt);
		}
		else if (decl.storage_class & STC.manifest)
			kind = "(constant) ";
		else if (decl.isAliasDeclaration())
			kind = "(alias) ";
		else if (decl.isField())
			kind = "(field) ";
		else if (decl.semanticRun >= PASS.semanticdone) // avoid lazy semantic analysis
		{
			if (!decl.isDataseg() && !decl.isCodeseg())
			{
				kind = "(local variable) ";
				fqn = false;
			}
			else if (decl.isThreadlocal())
				kind = "(thread local variable) ";
			else if (decl.type && decl.type.isShared())
				kind = "(shared variable) ";
			else if (decl.type && decl.type.ty != Terror)
				kind = "(__gshared variable) ";
		}

		if (decl.type)
			txt ~= to!string(decl.type.toPrettyChars(true)) ~ " ";
		txt ~= to!string(fqn ? decl.toPrettyChars(fqn) : decl.toChars());
		if (decl.storage_class & STC.manifest)
			if (auto var = decl.isVarDeclaration())
				if (var._init)
					txt ~= " = " ~ var._init.toString();
		if (auto ad = decl.isAliasDeclaration())
			if (ad.aliassym)
				txt ~= " = " ~ tipForObject(ad.aliassym, false);
		return kind ~ quoteCode(quote, txt);
	}

	string tip;
	string toc;
	const(char)* doc;

	string tipForType(Type t)
	{
		string kind;
		if (t.isTypeIdentifier())
			kind = "unresolved type";
		else if (auto tc = t.isTypeClass())
			kind = tc.sym.isInterfaceDeclaration() ? "interface" : "class";
		else if (auto ts = t.isTypeStruct())
			kind = ts.sym.isUnionDeclaration() ? "union" : "struct";
		else
			kind = t.kind().to!string;
		string txt = "(" ~ kind ~ ") " ~ quoteCode(quote, t.toPrettyChars(true).to!string);
		if (auto sym = typeSymbol(t))
			if (sym.comment)
				doc = sym.comment;
		return txt;
	}
	string tipForDotIdExp(DotIdExp die)
	{
		bool isConstant = die.original.isConstantExpr();
		Expression e1;
		if (!isConstant && !die.original.isArrayLengthExp() && die.type)
		{
			e1 = isAALenCall(die.original);
			if (!e1 && die.ident == Id.ptr && die.original.isCastExp())
				e1 = die.original;
			if (!e1)
				return tipForType(die.type);
		}
		if (!e1)
			e1 = die.e1;
		string tip = isConstant ? "(constant) `" : "(field) `";
		tip ~= die.original.type.toPrettyChars(true).to!string ~ " ";
		tip ~= e1.type ? die.e1.type.toPrettyChars(true).to!string : e1.toString();
		tip ~= "." ~ die.ident.toString();
		if (isConstant)
			tip ~= " = " ~ die.original.toString();
		tip ~= "`";
		return tip;
	}

	if (auto t = obj.isType())
	{
		toc = tipForType(t.mutableOf().unSharedOf());
	}
	else if (auto e = obj.isExpression())
	{
		switch(e.op)
		{
			case TOK.variable:
			case TOK.symbolOffset:
				tip = tipForDeclaration((cast(SymbolExp)e).var);
				doc = (cast(SymbolExp)e).var.comment;
				break;
			case TOK.dotVariable:
				tip = tipForDeclaration((cast(DotVarExp)e).var);
				doc = (cast(DotVarExp)e).var.comment;
				break;
			case TOK.dotIdentifier:
				if (e.original && e.original.type)
				{
					tip = tipForDotIdExp(e.isDotIdExp());
					break;
				}
				goto default;
			default:
				if (e.type)
					toc = tipForType(e.type);
				break;
		}
	}
	else if (auto s = obj.isDsymbol())
	{
		if (auto imp = s.isImport())
			if (imp.mod)
				s = imp.mod;
		if (auto decl = s.isDeclaration())
			tip = tipForDeclaration(decl);
		else
			toc = "(" ~ s.kind().to!string ~ ") " ~ quoteCode(quote, s.toPrettyChars(true).to!string);

		if (s.comment)
			doc = s.comment;
	}
	if (!tip.length)
	{
		if (!toc)
			toc = quoteCode(quote, obj.toString().dup);
		tip = toc;
	}
	// append doc
	if (doc)
		tip = tip ~ "\n\n" ~ strip(cast(string)doc[0..strlen(doc)]);
	return tip;
}

string findTip(Module mod, int startLine, int startIndex, int endLine, int endIndex)
{
	auto filename = mod.srcfile.toChars();
	scope FindTipVisitor ftv = new FindTipVisitor(filename, startLine, startIndex, endLine, endIndex);
	mod.accept(ftv);

	return ftv.tip;
}
////////////////////////////////////////////////////////////////

extern(C++) class FindDefinitionVisitor : FindASTVisitor
{
	Loc loc;

	alias visit = FindASTVisitor.visit;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		super(filename, startLine, startIndex, endLine, endIndex);
	}

	override bool foundNode(RootObject obj)
	{
		found = obj;
		if (obj)
		{
			if (auto t = obj.isType())
			{
				if (auto sym = typeSymbol(t))
					loc = sym.loc;
			}
			else if (auto e = obj.isExpression())
			{
				switch(e.op)
				{
					case TOK.variable:
					case TOK.symbolOffset:
						loc = (cast(SymbolExp)e).var.loc;
						break;
					case TOK.dotVariable:
						loc = (cast(DotVarExp)e).var.loc;
						break;
					default:
						loc = e.loc;
						break;
				}
			}
			else if (auto s = obj.isDsymbol())
			{
				loc = s.loc;
			}
			stop = true;
		}
		return stop;
	}
}

string findDefinition(Module mod, ref int line, ref int index)
{
	auto filename = mod.srcfile.toChars();
	scope FindDefinitionVisitor fdv = new FindDefinitionVisitor(filename, line, index, line, index + 1);
	mod.accept(fdv);

	if (!fdv.loc.filename)
		return null;
	line = fdv.loc.linnum;
	index = fdv.loc.charnum;
	return to!string(fdv.loc.filename);
}

////////////////////////////////////////////////////////////////////////////////

Loc[] findBinaryIsInLocations(Module mod)
{
	extern(C++) class BinaryIsInVisitor : ASTVisitor
	{
		Loc[] locdata;
		const(char)* filename;

		alias visit = ASTVisitor.visit;

		final void addLocation(const ref Loc loc)
		{
			if (loc.filename is filename)
				locdata ~= loc;
		}

		override void visit(InExp e)
		{
			addLocation(e.oploc);
			super.visit(e);
		}
		override void visit(IdentityExp e)
		{
			addLocation(e.oploc);
			super.visit(e);
		}
	}

	scope BinaryIsInVisitor biiv = new BinaryIsInVisitor;
	biiv.filename = mod.srcfile.toChars();
	biiv.unconditional = true;
	mod.accept(biiv);

	return biiv.locdata;
}

////////////////////////////////////////////////////////////////////////////////
struct IdTypePos
{
	int type;
	int line;
	int col;
}

alias FindIdentifierTypesResult = IdTypePos[][const(char)[]];

FindIdentifierTypesResult findIdentifierTypes(Module mod)
{
	extern(C++) class IdentifierTypesVisitor : ASTVisitor
	{
		FindIdentifierTypesResult idTypes;
		const(char)* filename;

		alias visit = ASTVisitor.visit;

		extern(D)
		final void addTypePos(const(char)[] ident, int type, int line, int col)
		{
			if (auto pid = ident in idTypes)
			{
				// merge sorted
				import std.range;
				auto a = assumeSorted!"a.line < b.line || (a.line == b.line && a.col < b.col)"(*pid);
				auto itp = IdTypePos(type, line, col);
				auto sections = a.trisect(itp);
				if (!sections[1].empty && sections[1][0].type == type) // upperbound
					sections[1][0] = itp;
				else if (sections[0].empty || sections[0][$-1].type != type) // lowerbound
					*pid = (*pid)[0..sections[0].length] ~ itp ~ (*pid)[sections[0].length..$];
			}
			else
				idTypes[ident] = [IdTypePos(type, line, col)];
		}

		void addIdent(ref const Loc loc, Identifier ident, int type)
		{
			if (ident && loc.filename is filename)
				addTypePos(ident.toString(), type, loc.linnum, loc.charnum);
		}

		void addIdentByType(ref const Loc loc, Identifier ident, Type t)
		{
			if (ident && t && loc.filename is filename)
			{
				int type = TypeReferenceKind.Unknown;
				switch (t.ty)
				{
					case Tstruct:   type = TypeReferenceKind.Struct; break;
					//case Tunion:  type = TypeReferenceKind.Union; break;
					case Tclass:    type = TypeReferenceKind.Class; break;
					case Tenum:     type = TypeReferenceKind.Enum; break;
					default: break;
				}
				if (type != TypeReferenceKind.Unknown)
					addTypePos(ident.toString(), type, loc.linnum, loc.charnum);
			}
		}

		void addPackages(IdentifiersAtLoc* packages)
		{
			if (packages)
				for (size_t p; p < packages.dim; p++)
					addIdent((*packages)[p].loc, (*packages)[p].ident, TypeReferenceKind.Package);
		}

		void addDeclaration(ref const Loc loc, Declaration decl)
		{
			auto ident = decl.ident;
			if (auto func = decl.isFuncDeclaration())
			{
				auto p = decl.toParent2;
				if (p && p.isAggregateDeclaration)
					addIdent(loc, ident, TypeReferenceKind.Method);
				else
					addIdent(loc, ident, TypeReferenceKind.Function);
			}
			else if (decl.isParameter())
				addIdent(loc, ident, TypeReferenceKind.ParameterVariable);
			else if (decl.isEnumMember())
				addIdent(loc, ident, TypeReferenceKind.EnumValue);
			else if (decl.storage_class & STC.manifest)
				addIdent(loc, ident, TypeReferenceKind.Constant);
			else if (decl.isAliasDeclaration())
				addIdent(loc, ident, TypeReferenceKind.Alias);
			else if (decl.isField())
				addIdent(loc, ident, TypeReferenceKind.MemberVariable);
			else if (!decl.isDataseg() && !decl.isCodeseg())
				addIdent(loc, ident, TypeReferenceKind.LocalVariable);
			else if (decl.isThreadlocal())
				addIdent(loc, ident, TypeReferenceKind.TLSVariable);
			else if (decl.type && decl.type.isShared())
				addIdent(loc, ident, TypeReferenceKind.SharedVariable);
			else
				addIdent(loc, ident, TypeReferenceKind.GSharedVariable);
		}

		void addType(Type type, Type originalType, bool syntaxCopiedOriginal = false)
		{
			while (type && originalType && (type.ty == originalType.ty || 
				   (originalType.ty == Taarray && type.ty == Tsarray)))
			{
				switch (type.ty)
				{
					case Tsarray:
					{
						auto resolvedSA = cast(TypeSArray) type;
						visitExpression(resolvedSA.dim);
						goto case Tarray;
					}
					case Taarray:
					{
						auto originalAA = cast(TypeAArray) originalType;
						auto resolvedAA = cast(TypeAArray) type;
						addType(resolvedAA.index, originalAA.index, syntaxCopiedOriginal);
						goto case Tarray;
					}
					case Tarray:
					case Tpointer:
					case Treference:
					case Tvector:
						originalType = (cast(TypeNext) originalType).next;
						type         = (cast(TypeNext) type        ).next;
						continue;
					default:
						break;
				}
				break;
			}
			static TypeReferenceKind refkind(Type t)
			{
				switch (t.ty)
				{
					case Tident:  return TypeReferenceKind.TemplateTypeParameter;
					case Tclass:  return (cast(TypeClass)t).sym.isInterfaceDeclaration() ? TypeReferenceKind.Interface
					                                                                     : TypeReferenceKind.Class;
					case Tstruct: return (cast(TypeStruct)t).sym.isUnionDeclaration() ? TypeReferenceKind.Union
					                                                                  : TypeReferenceKind.Struct;
					case Tenum:   return TypeReferenceKind.Enum;
					default:      return TypeReferenceKind.BasicType;
				}
			}
			void addTypeIdentifier(TypeIdentifier tid, Type resolvedType)
			{
				if (tid.copiedFrom && syntaxCopiedOriginal)
					tid = tid.copiedFrom;
				if (tid.parentScopes.dim > 0)
					addObject(tid.loc, tid.parentScopes[0]);
				else
					addIdent(tid.loc, tid.ident, refkind(resolvedType));

				foreach (i, id; tid.idents)
				{
					RootObject obj = id;
					if (obj.dyncast() == DYNCAST.identifier)
					{
						auto ident = cast(Identifier)obj;
						if (tid.parentScopes.dim > i + 1)
							addObject(id.loc, tid.parentScopes[i + 1]);
						else
							addIdent(id.loc, id, refkind(resolvedType));
					}
				}
			}

			if (originalType && originalType.ty == Tident && type)
				addTypeIdentifier(cast(TypeIdentifier) originalType, type);
			else if (type && type.ty == Tident) // not yet semantically analyzed (or a template declaration)
				addTypeIdentifier(cast(TypeIdentifier) type, type);
		}

		void addObject(ref const Loc loc, RootObject obj)
		{
			if (auto t = obj.isType())
				addType(t, t);
			else if (auto s = obj.isDsymbol())
			{
				if (auto imp = s.isImport())
					if (imp.mod)
						s = imp.mod;
				addSymbol(loc, s);
			}
			else if (auto e = obj.isExpression())
				e.accept(this);
		}

		void addSymbol(ref const Loc loc, Dsymbol sym)
		{
			if (auto decl = sym.isDeclaration())
				addDeclaration(loc, decl);
			else if (sym.isModule())
				addIdent(loc, sym.ident, TypeReferenceKind.Module);
			else if (sym.isPackage())
				addIdent(loc, sym.ident, TypeReferenceKind.Package);
			else
				addIdent(loc, sym.ident, TypeReferenceKind.Variable);
		}

		override void visit(Dsymbol sym)
		{
			addSymbol(sym.loc, sym);
		}

		override void visit(Parameter sym)
		{
			addIdent(sym.ident.loc, sym.ident, TypeReferenceKind.ParameterVariable);
		}

		override void visit(Module mod)
		{
			if (mod.md)
			{
				addPackages(mod.md.packages);
				addIdent(mod.md.loc, mod.md.id, TypeReferenceKind.Module);
			}
			visit(cast(Package)mod);
		}

		override void visit(Import imp)
		{
			addPackages(imp.packages);

			addIdent(imp.loc, imp.id, TypeReferenceKind.Module);

			for (int n = 0; n < imp.names.dim; n++)
			{
				addIdent(imp.names[n].loc, imp.names[n].ident, TypeReferenceKind.Alias);
				if (imp.aliases[n].ident && n < imp.aliasdecls.dim)
					addDeclaration(imp.aliases[n].loc, imp.aliasdecls[n]);
			}
			// symbol has ident of first package, so don't forward
		}

		override void visit(DebugCondition cond)
		{
			addIdent(cond.loc, cond.ident, TypeReferenceKind.VersionIdentifier);
		}

		override void visit(VersionCondition cond)
		{
			addIdent(cond.loc, cond.ident, TypeReferenceKind.VersionIdentifier);
		}

		override void visit(VarDeclaration decl)
		{
			addType(decl.type, decl.originalType);
			if (decl.parsedType != decl.originalType)
				addType(decl.type, decl.parsedType, true);
			super.visit(decl);
		}

		override void visit(SymbolExp expr)
		{
			if (expr.var && expr.var.ident)
				addDeclaration(expr.loc, expr.var);
			super.visit(expr);
		}

		override void visit(NewExp ne)
		{
			if (ne.member)
				ne.member.accept(this);

			addType(ne.newtype, ne.parsedType, true);
			if (ne.newtype != ne.parsedType)
				addType(ne.newtype, ne.newtype);

			super.visit(ne);
		}

		override void visit(TypeExp expr)
		{
			if (expr.original && expr.type)
			{
				if (auto ie = expr.original.isIdentifierExp())
				{
					addIdentByType(ie.loc, ie.ident, expr.type);
				}
				else if (auto die = expr.original.isDotIdExp())
				{
					addIdentByType(die.ident.loc, die.ident, expr.type);
				}
			}
			super.visit(expr);
		}

		override void visit(IdentifierExp expr)
		{
			if (expr.original)
				if (auto se = expr.original.isScopeExp())
					addSymbol(expr.loc, se.sds);

//			if (expr.type)
//				addIdentByType(expr.loc, expr.ident, expr.type);
//			else if (expr.original && expr.original.type)
//				addIdentByType(expr.loc, expr.ident, expr.original.type);
//			else
				super.visit(expr);
		}

		override void visit(DotIdExp expr)
		{
			auto orig = expr.original;
			if (orig && orig.type && orig.isConstantExpr())
				addIdent(expr.identloc, expr.ident, TypeReferenceKind.Constant);
			else if (orig && orig.type &&
					 (orig.isArrayLengthExp() || orig.isAALenCall() || (expr.ident == Id.ptr && orig.isCastExp())))
				addIdent(expr.identloc, expr.ident, TypeReferenceKind.MemberVariable);
			else
				super.visit(expr);
		}

		override void visit(DotVarExp dve)
		{
			if (dve.var && dve.var.ident)
				addDeclaration(dve.varloc.filename ? dve.varloc : dve.loc, dve.var);
			super.visit(dve);
		}

		override void visit(ScopeExp expr)
		{
			if (auto ti = expr.sds.isTemplateInstance())
			{
				if (ti.tiargs && ti.parsedArgs)
				{
					size_t args = min(ti.tiargs.dim, ti.parsedArgs.dim);
					for (size_t a = 0; a < args; a++)
						if (Type tip = (*ti.parsedArgs)[a].isType())
							if (Type tir = (*ti.tiargs)[a].isType())
								addType(tir, tip);
				}
			}
			super.visit(expr);
		}

		override void visit(CastExp expr)
		{
			addType(expr.to, expr.parsedTo, true);
			super.visit(expr);
		}

		override void visit(EnumDeclaration ed)
		{
			addIdent(ed.loc, ed.ident, TypeReferenceKind.Enum);
			super.visit(ed);
		}

		override void visit(FuncDeclaration decl)
		{
			super.visit(decl);

			if (decl.type)
			{
				auto ft = decl.type.isTypeFunction();
				auto ot = decl.originalType ? decl.originalType.isTypeFunction() : null;
				addType(ft ? ft.nextOf() : null, ot ? ot.nextOf() : null); // the return type
			}
		}

		override void visit(AggregateDeclaration ad)
		{
			if (ad.isInterfaceDeclaration)
				addIdent(ad.loc, ad.ident, TypeReferenceKind.Interface);
			else if (ad.isClassDeclaration)
				addIdent(ad.loc, ad.ident, TypeReferenceKind.Class);
			else if (ad.isUnionDeclaration)
				addIdent(ad.loc, ad.ident, TypeReferenceKind.Union);
			else
				addIdent(ad.loc, ad.ident, TypeReferenceKind.Struct);
			super.visit(ad);
		}

		override void visit(ClassDeclaration cd)
		{
			if (cd.baseclasses)
				foreach (bc; *(cd.baseclasses))
					addType(bc.type, bc.parsedType);

			return super.visit(cd);
		}
	}

	scope IdentifierTypesVisitor itv = new IdentifierTypesVisitor;
	itv.filename = mod.srcfile.toChars();
	mod.accept(itv);

	return itv.idTypes;
}

////////////////////////////////////////////////////////////////////////////////
struct Reference
{
	Loc loc;
	Identifier ident;
}

Reference[] findReferencesInModule(Module mod, int line, int index)
{
	auto filename = mod.srcfile.toChars();
	scope FindDefinitionVisitor fdv = new FindDefinitionVisitor(filename, line, index, line, index + 1);
	mod.accept(fdv);

	if (!fdv.found)
		return null;

	extern(C++) class FindReferencesVisitor : ASTVisitor
	{
		RootObject search;
		Reference[] references;

		alias visit = ASTVisitor.visit;

		extern(D)
		void addReference(ref const Loc loc, Identifier ident)
		{
			if (loc.filename && ident)
				if (!references.contains(Reference(loc, ident)))
					references ~= Reference(loc, ident);
		}

		override void visit(Dsymbol sym)
		{
			if (sym is search)
				addReference(sym.loc, sym.ident);
		}
		override void visit(SymbolExp expr)
		{
			if (expr.var is search)
				addReference(expr.loc, expr.var.ident);
		}
		override void visit(DotVarExp dve)
		{
			if (dve.var is search)
				addReference(dve.varloc.filename ? dve.varloc : dve.loc, dve.var.ident);
		}
	}

	scope FindReferencesVisitor frv = new FindReferencesVisitor();

	if (auto t = fdv.found.isType())
	{
		if (t.ty == Tstruct)
			fdv.found = (cast(TypeStruct)t).sym;
	}
	else if (auto e = fdv.found.isExpression())
	{
		switch(e.op)
		{
			case TOK.variable:
			case TOK.symbolOffset:
				fdv.found = (cast(SymbolExp)e).var;
				break;
			case TOK.dotVariable:
				fdv.found = (cast(DotVarExp)e).var;
				break;
			default:
				break;
		}
	}
	frv.search = fdv.found;
	mod.accept(frv);

	return frv.references;
}

////////////////////////////////////////////////////////////////////////////////
string[] findExpansions(Module mod, int line, int index, string tok)
{
	auto filename = mod.srcfile.toChars();
	scope FindDefinitionVisitor fdv = new FindDefinitionVisitor(filename, line, index, line, index + 1);
	mod.accept(fdv);

	if (!fdv.found)
		return null;

	int flags = 0;
	Type type = fdv.found.isType();
	if (auto e = fdv.found.isExpression())
	{
		switch(e.op)
		{
			case TOK.variable:
			case TOK.symbolOffset:
				//type = (cast(SymbolExp)e).var.type;
				break;
			case TOK.dotVariable:
			case TOK.dotIdentifier:
				type = (cast(UnaExp)e).e1.type;
				flags |= SearchLocalsOnly;
				break;
			case TOK.dot:
				type = (cast(DotExp)e).e1.type;
				flags |= SearchLocalsOnly;
				break;
			default:
				break;
		}
	}

	auto sds = fdv.foundScope;
	if (type)
		if (auto sym = typeSymbol(type))
			sds = sym;

	string[void*] idmap; // doesn't work with extern(C++) classes
	void searchScope(ScopeDsymbol sds, int flags)
	{
		static Dsymbol uplevel(Dsymbol s)
		{
			if (auto ad = s.isAggregateDeclaration())
				return ad.enclosing;
			return s.toParent;
		}
		// TODO: properties
		// TODO: base classes
		// TODO: struct/class not going to parent if accessed from elsewhere (but does if nested)
		for (Dsymbol ds = sds; ds; ds = uplevel(ds))
		{
			ScopeDsymbol sd = ds.isScopeDsymbol();
			if (!sd)
				continue;

			//foreach (pair; sd.symtab.tab.asRange)
			if (sd.symtab)
			{
				foreach (key, s; sd.symtab.tab.aa)
				{
					//Dsymbol s = pair.value;
					if (!symbolIsVisible(mod, s))
						continue;
					auto ident = /*pair.*/(cast(Dsymbol)key).toString();
					if (ident.startsWith(tok))
						idmap[cast(void*)s] = ident.idup;
				}
			}

			// TODO: alias this

			// imported modules
			size_t cnt = sd.importedScopes ? sd.importedScopes.dim : 0;
			for (size_t i = 0; i < cnt; i++)
			{
				if ((flags & IgnorePrivateImports) && sd.prots[i] == Prot.Kind.private_)
					continue;
				auto ss = (*sd.importedScopes)[i].isScopeDsymbol();
				if (!ss)
					continue;

				int sflags = 0;
				if (ss.isModule())
				{
					if (flags & SearchLocalsOnly)
						continue;
					sflags |= IgnorePrivateImports;
				}
				else // mixin template
				{
					if (flags & SearchImportsOnly)
						continue;
					sflags |= SearchLocalsOnly;
				}
				searchScope(ss, sflags | IgnorePrivateImports);
			}
		}
	}
	searchScope(sds, flags);

	string[] idlist;
	foreach(sym, id; idmap)
		idlist ~= id ~ ":" ~ cast(string) (cast(Dsymbol)sym).toString();
	return idlist;
}

////////////////////////////////////////////////////////////////////////////////

bool isConstantExpr(Expression expr)
{
	switch(expr.op)
	{
		case TOK.int64, TOK.float64, TOK.char_, TOK.complex80:
		case TOK.null_, TOK.void_:
		case TOK.string_:
		case TOK.arrayLiteral, TOK.assocArrayLiteral, TOK.structLiteral:
		case TOK.classReference:
			//case TOK.type:
		case TOK.vector:
		case TOK.function_, TOK.delegate_:
		case TOK.symbolOffset, TOK.address:
		case TOK.typeid_:
		case TOK.slice:
			return true;
		default:
			return false;
	}
}

// return first argument to aaLen()
Expression isAALenCall(Expression expr)
{
	// unpack first argument of _aaLen(aa)
	if (auto ce = expr.isCallExp())
		if (auto ve = ce.e1.isVarExp())
			if (ve.var.ident is Id.aaLen)
				if (ce.arguments && ce.arguments.dim > 0)
					return (*ce.arguments)[0];
	return null;
}

////////////////////////////////////////////////////////////////////////////////

ScopeDsymbol typeSymbol(Type type)
{
	if (auto ts = type.isTypeStruct())
		return ts.sym;
	if (auto tc = type.isTypeClass())
		return tc.sym;
	if (auto te = type.isTypeEnum())
		return te.sym;
	return null;
}

Module cloneModule(Module mo)
{
	if (!mo)
		return null;
	Module m = new Module(mo.srcfile.toString(), mo.ident, mo.isDocFile, mo.isHdrFile);
	*cast(FileName*)&(m.srcfile) = mo.srcfile; // keep identical source file name pointer
	m.isPackageFile = mo.isPackageFile;
	m.md = mo.md;
	mo.syntaxCopy(m);

	extern(C++) class AdjustModuleVisitor : ASTVisitor
	{
		// avoid allocating capture
		Module m;
		this (Module m)
		{
			this.m = m;
		}

		alias visit = ASTVisitor.visit;

		override void visit(ConditionalStatement cond)
		{
			if (auto dbg = cond.condition.isDebugCondition())
				cond.condition = new DebugCondition(dbg.loc, m, dbg.level, dbg.ident);
			else if (auto ver = cond.condition.isVersionCondition())
				cond.condition = new VersionCondition(ver.loc, m, ver.level, ver.ident);
		}

		override void visit(ConditionalDeclaration cond)
		{
			if (auto dbg = cond.condition.isDebugCondition())
				cond.condition = new DebugCondition(dbg.loc, m, dbg.level, dbg.ident);
			else if (auto ver = cond.condition.isVersionCondition())
				cond.condition = new VersionCondition(ver.loc, m, ver.level, ver.ident);
		}
	}

	import dmd.permissivevisitor;
	scope v = new AdjustModuleVisitor(m);
	m.accept(v);
	return m;
}

Module createModuleFromText(string filename, string text)
{
	import std.path;

	text ~= "\0\0"; // parser needs 2 trailing zeroes
	string name = stripExtension(baseName(filename));
	auto id = Identifier.idPool(name);
	auto mod = new Module(filename, id, true, false);
	mod.srcBuffer = new FileBuffer(cast(ubyte[])text);
	mod.read(Loc.initial);
	mod.parse();
	return mod;
}

////////////////////////////////////////////////////////////////////////////////

