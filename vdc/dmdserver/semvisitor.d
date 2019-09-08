// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.semvisitor;

import vdc.ivdserver;

import dmd.access;
import dmd.aggregate;
import dmd.apply;
import dmd.arraytypes;
import dmd.attrib;
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

	Expression[] visiting;
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

		if (walkPostorder(stmt, this))
			stop = true;
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
	override void visit(Statement) {}

	override void visit(ErrorStatement stmt)
	{
		visitStatement(stmt.errStmt);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ExpStatement stmt)
	{
		visitExpression(stmt.exp);
		if (!stop)
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
	}

	override void visit(CompileStatement stmt)
	{
		if (stmt.exps)
			foreach(e; *stmt.exps)
				if (!stop)
					e.accept(this);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(WhileStatement stmt)
	{
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(DoStatement stmt)
	{
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ForStatement stmt)
	{
		visitExpression(stmt.condition);
		visitExpression(stmt.increment);
		if (!stop)
			visit(cast(Statement)stmt);

		if (!stop && stmt.loweredFrom)
			stmt.loweredFrom.accept(this);
	}

	override void visit(ForeachStatement stmt)
	{
		if (stmt.parameters)
			foreach(p; *stmt.parameters)
				if (!stop)
					p.accept(this);
		visitExpression(stmt.aggr);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ForeachRangeStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.lwr);
		visitExpression(stmt.upr);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(IfStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(PragmaStatement stmt)
	{
		if (!stop && stmt.args)
			foreach(a; *stmt.args)
				if (!stop)
					a.accept(this);
		if (!stop)
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
		if (!obj)
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

	override void visit(CastExp expr)
	{
		visitTypeIdentifier(expr.parsedTo, expr.to);
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

	override void visit(TemplateInstance)
	{
		// skip members added by semantic
	}

	override void visit(CallExp expr)
	{
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
		if (!found && expr.ident && expr.type)
			if (matchIdentifier(expr.loc, expr.ident))
				foundNode(expr.type);
		visit(cast(Expression)expr);
	}

	override void visit(DotIdExp de)
	{
		if (!found)
			if (de.ident)
				if (matchIdentifier(de.identloc, de.ident))
					foundNode(de);
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
		visitTypeIdentifier(decl.parsedType, decl.type);
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
	}

	void visitTypeIdentifier(Type originalType, Type resolvedType)
	{
		if (found || !originalType || !resolvedType)
			return;
		while (originalType.ty != Tident)
		{
			if (originalType.ty != resolvedType.ty)
				return;
			switch (originalType.ty)
			{
				case Tarray:
				case Tpointer:
				case Treference:
				case Tsarray:
				case Tvector:
					originalType = (cast(TypeNext) originalType).next;
					resolvedType = (cast(TypeNext) resolvedType).next;
					break;
				default:
					return;
			}
		}
		auto otype = cast(TypeIdentifier) originalType;
		Loc loc = otype.loc;
		if (matchIdentifier(loc, otype.ident))
		{
			foundNode(resolvedType);
		}
		else
		{
			// guess qualified name to be without spaces
			loc.charnum += otype.ident.toString().length + 1;
			foreach (id; otype.idents)
			{
				if (id.dyncast() == DYNCAST.identifier)
				{
					auto ident = cast(Identifier)id;
					if (matchIdentifier(loc, ident))
						foundNode(resolvedType);
					loc.charnum += ident.toString().length + 1;
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
			tip = tipForObject(obj);
			stop = true;
		}
		return stop;
	}
}

string tipForObject(RootObject obj)
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
			return cast(string)res;
		}

		bool fqn = true;
		string txt;
		if (decl.isParameter())
		{
			txt = "(parameter) ";
			fqn = false;
		}
		else if (auto em = decl.isEnumMember())
		{
			txt = "(enum value) " ~ decl.toPrettyChars(fqn).to!string;
			if (em.origValue)
				txt ~= " = " ~ cast(string)em.origValue.toString();
			return txt;
		}
		else if (decl.storage_class & STC.manifest)
			txt = "(constant) ";
		else if (decl.isAliasDeclaration())
			txt = "(alias) ";
		else if (decl.isField())
			txt = "(field) ";
		else if (decl.semanticRun >= PASS.semanticdone) // avoid lazy semantic analysis
		{
			if (!decl.isDataseg() && !decl.isCodeseg())
			{
				txt = "(local variable) ";
				fqn = false;
			}
			else if (decl.isThreadlocal())
				txt = "(thread local variable) ";
			else if (decl.type && decl.type.isShared())
				txt = "(shared variable) ";
			else if (decl.type && decl.type.ty != Terror)
				txt = "(__gshared variable) ";
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
				txt ~= " = " ~ tipForObject(ad.aliassym);
		return txt;
	}

	string tip;
	string toc;
	const(char)* doc;
	if (auto t = obj.isType())
	{
		string kind;
		if (t.isTypeIdentifier())
			kind = "unresolved type";
		else
			kind = t.kind().to!string;
		toc = "(" ~ kind ~ ") " ~ t.toPrettyChars(true).to!string;
		if (auto sym = typeSymbol(t))
			if (sym.comment)
				doc = sym.comment;
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
			default:
				if (e.type)
					toc = e.type.toPrettyChars(true).to!string;
				break;
		}
	}
	else if (auto s = obj.isDsymbol())
	{
		if (auto decl = s.isDeclaration())
			tip = tipForDeclaration(decl);
		else
			toc = "(" ~ s.kind().to!string ~ ") " ~ s.toPrettyChars(true).to!string;

		if (s.comment)
			doc = s.comment;
	}
	if (!tip.length)
	{
		if (!toc)
			toc = obj.toString().dup;
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
				if (type != (*pid)[$-1].type)
					*pid ~= IdTypePos(type, line, col);
			}
			else
				idTypes[ident] = [IdTypePos(type, line, col)];
		}

		void addIdent(ref const Loc loc, Identifier ident, int type)
		{
			if (ident && loc.filename is filename)
				addTypePos(ident.toString(), type, loc.linnum, loc.charnum);
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

		void addType(ref const Loc loc, Type type, Type originalType)
		{
			while (type && originalType && type.ty == originalType.ty)
			{
				switch (originalType.ty)
				{
					case Tarray:
					case Tpointer:
					case Treference:
					case Tsarray:
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
					case Tclass:  return TypeReferenceKind.Class;
					case Tstruct: return TypeReferenceKind.Struct;
					case Tenum:   return TypeReferenceKind.Enum;
					default:      return TypeReferenceKind.BasicType;
				}
			}
			if (originalType && originalType.ty == Tident && type)
				addIdent(loc, (cast(TypeIdentifier) originalType).ident, refkind(type));
			else if (type && type.ty == Tident) // not yet semantically analyzed (or a template declaration)
				addIdent(loc, (cast(TypeIdentifier) type).ident, TypeReferenceKind.TemplateTypeParameter);
		}

		override void visit(Dsymbol sym)
		{
			if (auto decl = sym.isDeclaration)
				addDeclaration(sym.loc, decl);
			else
				addIdent(sym.loc, sym.ident, TypeReferenceKind.Variable);
		}

		override void visit(VarDeclaration decl)
		{
			addType(decl.loc, decl.type, decl.originalType);
			if (decl.parsedType != decl.originalType)
				addType(decl.loc, decl.type, decl.parsedType);
			super.visit(decl);
		}

		override void visit(SymbolExp expr)
		{
			if (expr.var && expr.var.ident)
				addDeclaration(expr.loc, expr.var);
			super.visit(expr);
		}

		override void visit(DotVarExp dve)
		{
			if (dve.var && dve.var.ident)
				addDeclaration(dve.varloc.filename ? dve.varloc : dve.loc, dve.var);
			super.visit(dve);
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

		override void visit(Parameter sym)
		{
			addIdent(sym.ident.loc, sym.ident, TypeReferenceKind.ParameterVariable);
		}

		override void visit(EnumDeclaration ed)
		{
			addIdent(ed.loc, ed.ident, TypeReferenceKind.Enum);
			super.visit(ed);
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

	string name = stripExtension(baseName(filename));
	auto id = Identifier.idPool(name);
	auto mod = new Module(filename, id, true, false);
	mod.srcBuffer = new FileBuffer(cast(ubyte[])text);
	mod.read(Loc.initial);
	mod.parse();
	return mod;
}

////////////////////////////////////////////////////////////////////////////////

