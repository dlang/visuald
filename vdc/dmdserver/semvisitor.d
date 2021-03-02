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
import dmd.aliasthis;
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
import dmd.staticassert;
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
import std.functional;
import stdext.array;
import stdext.denseset;
import core.stdc.string;

// walk the complete AST (declarations, statement and expressions)
// assumes being started on module/declaration level
extern(C++) class ASTVisitor : StoppableVisitor
{
	bool unconditional; // take both branches in conditional declarations/statements

	alias visit = StoppableVisitor.visit;

	DenseSet!ASTNode visited;

	void visitRecursive(T)(T node)
	{
		if (stop || !node || visited.contains(node))
			return;

		visited.insert(node);

		if (walkPostorder(node, this))
			stop = true;
	}

	void visitExpression(Expression expr)
	{
		visitRecursive(expr);
	}

	void visitStatement(Statement stmt)
	{
		visitRecursive(stmt);
	}

	void visitDeclaration(Dsymbol sym)
	{
		if (stop || !sym)
			return;

		sym.accept(this);
	}

	void visitParameter(Parameter p, Declaration decl)
	{
		visitType(p.parsedType);
		visitExpression(p.defaultArg);
		if (p.userAttribDecl)
			visit(p.userAttribDecl);
	}

	// default to being permissive
	override void visit(Parameter p)
	{
		visitParameter(p, null);
	}
	override void visit(TemplateParameter) {}

	// expressions
	override void visit(Expression expr)
	{
		if (expr.original && expr.original != expr)
			visitExpression(expr.original);
	}

	override void visit(ErrorExp errexp)
	{
		visit(cast(Expression)errexp);
	}

	override void visit(CastExp expr)
	{
		visitType(expr.parsedTo);
		if (expr.parsedTo != expr.to)
			visitType(expr.to);
		super.visit(expr);
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
		visitType(expr.type);
		visit(cast(Expression)expr);
	}

	override void visit(FuncExp expr)
	{
		visitDeclaration(expr.fd);
		visitDeclaration(expr.td);

		visit(cast(Expression)expr);
	}

	override void visit(NewExp ne)
	{
		if (ne.member)
			ne.member.accept(this);

		visitType(ne.parsedType);
		if (ne.newtype != ne.parsedType)
			visitType(ne.newtype);

		super.visit(ne);
	}

	override void visit(ScopeExp expr)
	{
		if (auto ti = expr.sds.isTemplateInstance())
			visitTemplateInstance(ti);
		super.visit(expr);
	}

	override void visit(TraitsExp te)
	{
		if (te.args)
		{
			foreach(a; (*te.args))
				if (auto t = a.isType())
					visitType(t);
				else if (auto e = a.isExpression())
					visitExpression(e);
				//else if (auto s = a.isSymbol())
				//	visitSymbol(s);
		}

		super.visit(te);
	}

	void visitTemplateInstance(TemplateInstance ti)
	{
		if (ti.tiargs && ti.parsedArgs)
		{
			size_t args = min(ti.tiargs.dim, ti.parsedArgs.dim);
			for (size_t a = 0; a < args; a++)
				if (Type tip = (*ti.parsedArgs)[a].isType())
					visitType(tip);
		}
	}

	// types
	void visitType(Type type)
	{
		if (type)
			type.accept(this);
	}

	override void visit(Type t)
	{
	}

	override void visit(TypeSArray tsa)
	{
		visitExpression(tsa.dim);
		super.visit(tsa);
	}

	override void visit(TypeAArray taa)
	{
		if (taa.resolvedTo)
			visitType(taa.resolvedTo);
		else
		{
			visitType(taa.index);
			super.visit(taa);
		}
	}

	override void visit(TypeNext tn)
	{
		visitType(tn.next);
		super.visit(tn);
	}

	override void visit(TypeTypeof t)
	{
		visitExpression(t.exp);
		super.visit(t);
	}

	// symbols
	override void visit(Dsymbol) {}

	override void visit(ScopeDsymbol scopesym)
	{
		super.visit(scopesym);

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
		visitType(decl.parsedType);
		if (decl.originalType != decl.parsedType)
			visitType(decl.originalType);
		if (decl.type != decl.originalType && decl.type != decl.parsedType)
			visitType(decl.type); // not yet semantically analyzed (or a template declaration)

		visit(cast(Declaration)decl);

		if (!stop && decl._init)
			decl._init.accept(this);
	}

	override void visit(AliasDeclaration ad)
	{
		visitType(ad.originalType);
		super.visit(ad);
	}

	override void visit(AttribDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (!stop)
		{
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
	}

	override void visit(UserAttributeDeclaration decl)
	{
		if (decl.atts)
			foreach(e; *decl.atts)
				visitExpression(e);

		super.visit(decl);
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

		// function declaration only
		if (auto tf = decl.type ? decl.type.isTypeFunction() : null)
		{
			if (tf.parameterList.parameters)
				foreach(i, p; *tf.parameterList.parameters)
					if (!stop)
					{
						if (decl.parameters && i < decl.parameters.dim)
							visitParameter(p, (*decl.parameters)[i]);
						else
							p.accept(this);
					}
		}
		else if (decl.parameters)
		{
			foreach(p; *decl.parameters)
				if (!stop)
					p.accept(this);
		}

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

	override void visit(ClassDeclaration cd)
	{
		if (cd.baseclasses)
			foreach (bc; *(cd.baseclasses))
				visitType(bc.parsedType);

		super.visit(cd);
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
		// prm converted to DeclarationExp as part of condition
		//if (!stop && stmt.prm)
		//	stmt.prm.accept(this);
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
			{
				if (c.var)
					visitDeclaration(c.var);
				else
					visitType(c.parsedType);
			}

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

Loc endLocation(Statement s)
{
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
	return endloc;
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

	void foundNode(RootObject obj)
	{
		if (obj)
		{
			found = obj;
			// do not stop until the scope is also set
		}
	}

	void checkScope(ScopeDsymbol sc)
	{
		if (found && sc && !foundScope)
		{
			foundScope = sc;
			stop = true;
		}
	}

	bool foundExpr(Expression expr)
	{
		if (auto se = expr.isScopeExp())
			foundNode(se.sds);
		else if (auto ve = expr.isVarExp())
			foundNode(ve.var);
		else if (auto te = expr.isTypeExp())
			foundNode(te.type);
		else
			return false;
		return true;
	}

	bool foundResolved(Expression expr)
	{
		if (!expr)
			return false;
		CommaExp ce;
		while ((ce = expr.isCommaExp()) !is null)
		{
			if (foundExpr(ce.e1))
				return true;
			expr = ce.e2;
		}
		return foundExpr(expr);
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

	bool visitPackages(Module mod, IdentifiersAtLoc* packages)
	{
		if (!mod || !packages)
			return false;

		Package pkg = mod.parent ? mod.parent.isPackage() : null;
		for (size_t p; pkg && p < packages.dim; p++)
		{
			size_t q = packages.dim - 1 - p;
			if (!found && matchIdentifier((*packages)[q].loc, (*packages)[q].ident))
			{
				foundNode(pkg);
				return true;
			}
			pkg = pkg.parent ? pkg.parent.isPackage() : null;
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
		if (sym.isFuncLiteralDeclaration())
			return;
		if (!found && matchIdentifier(sym.loc, sym.ident))
			foundNode(sym);
	}

	override void visit(StaticAssert sa)
	{
		visitExpression(sa.exp);
		visitExpression(sa.msg);
		super.visit(sa);
	}

	override void visitParameter(Parameter sym, Declaration decl)
	{
		super.visitParameter(sym, decl);
		if (!found && matchIdentifier(sym.ident.loc, sym.ident))
			foundNode(decl ? decl : sym);
	}

	override void visit(Module mod)
	{
		if (mod.md)
		{
			visitPackages(mod, mod.md.packages);

			if (!found && matchIdentifier(mod.md.loc, mod.md.id))
				foundNode(mod);
		}
		visit(cast(Package)mod);
	}

	override void visit(Import imp)
	{
		visitPackages(imp.mod, imp.packages);

		if (!found && matchIdentifier(imp.loc, imp.id))
			foundNode(imp.mod);

		for (int n = 0; !found && n < imp.names.dim && n < imp.aliasdecls.dim; n++)
			if (matchIdentifier(imp.names[n].loc, imp.names[n].ident) ||
				matchIdentifier(imp.aliases[n].loc, imp.aliases[n].ident))
				foundNode(imp.aliasdecls[n]);

		// symbol has ident of first package, so don't forward
	}

	override void visit(DVCondition cond)
	{
		if (!found && matchIdentifier(cond.loc, cond.ident))
			foundNode(cond);
	}

	override void visit(Expression expr)
	{
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
			if (visited.contains(s))
				continue;

			if (s.loc.filename)
			{
				if (s.loc.filename !is filename || s.loc.linnum > endLine)
					continue;
				Loc endloc = endLocation(s);
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
		checkScope(scopesym);
	}

	override void visit(ScopeStatement ss)
	{
		visit(cast(Statement)ss);
		checkScope(ss.scopesym);
	}

	override void visit(ForStatement fs)
	{
		visit(cast(Statement)fs);
		checkScope(fs.scopesym);
	}

	override void visit(TemplateInstance ti)
	{
		// skip members added by semantic
		visit(cast(ScopeDsymbol)ti);
	}

	override void visit(TemplateDeclaration td)
	{
		if (!found && td.ident)
			if (matchIdentifier(td.loc, td.ident))
				foundNode(td);

		foreach(ti; td.instances)
			if (!stop)
				visit(ti);

		visit(cast(ScopeDsymbol)td);
	}

	override void visitTemplateInstance(TemplateInstance ti)
	{
		if (!found && ti.name)
			if (matchIdentifier(ti.loc, ti.name))
				foundNode(ti);

		super.visitTemplateInstance(ti);
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

	override void visit(IdentifierExp expr)
	{
		if (!found && expr.ident)
		{
			if (matchIdentifier(expr.loc, expr.ident))
			{
				if (expr.type)
					foundNode(expr.type);
				else if (expr.resolvedTo)
					foundResolved(expr.resolvedTo);
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
					if (!de.type && de.resolvedTo && !de.resolvedTo.isErrorExp())
						foundResolved(de.resolvedTo);
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
		super.visit(de);
	}

	override void visit(DotTemplateExp dte)
	{
		if (!found && dte.td && dte.td.ident)
			if (matchIdentifier(dte.identloc, dte.td.ident))
				foundNode(dte);
		super.visit(dte);
	}

	override void visit(TemplateExp te)
	{
		if (!found && te.td && te.td.ident)
			if (matchIdentifier(te.identloc, te.td.ident))
				foundNode(te);
		super.visit(te);
	}

	override void visit(DotVarExp dve)
	{
		if (!found && dve.var && dve.var.ident)
			if (matchIdentifier(dve.varloc.filename ? dve.varloc : dve.loc, dve.var.ident))
				foundNode(dve);
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

	override void visit(FuncDeclaration decl)
	{
		super.visit(decl);

		checkScope(decl.scopesym);

		visitType(decl.originalType);
	}

	override void visit(TypeQualified tq)
	{
		foreach (i, id; tq.idents)
		{
			RootObject obj = id;
			if (obj.dyncast() == DYNCAST.identifier)
			{
				auto ident = cast(Identifier)obj;
				if (matchIdentifier(id.loc, ident))
					if (tq.parentScopes.dim > i + 1)
						foundNode(tq.parentScopes[i + 1]);
			}
		}
		super.visit(tq);
	}

	override void visit(TypeIdentifier otype)
	{
		if (found)
			return;

		for (TypeIdentifier ti = otype; ti; ti = ti.copiedFrom)
			if (ti.parentScopes.dim)
			{
				otype = ti;
				break;
			}

		if (matchIdentifier(otype.loc, otype.ident))
		{
			if (otype.parentScopes.dim > 0)
				foundNode(otype.parentScopes[0]);
			else
				foundNode(otype);
		}
		super.visit(otype);
	}

	override void visit(TypeInstance ti)
	{
		if (found)
			return;

		for (TypeInstance cti = ti; cti; cti = cti.copiedFrom)
			if (cti.parentScopes.dim)
			{
				ti = cti;
				break;
			}

		if (ti.tempinst && matchIdentifier(ti.loc, ti.tempinst.name))
		{
			if (ti.parentScopes.dim > 0)
				foundNode(ti.parentScopes[0]);
			return;
		}
		visitTemplateInstance(ti.tempinst);
		super.visit(ti);
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

bool isUnnamedSelectiveImportAlias(AliasDeclaration ad)
{
	if (!ad || !ad._import)
		return false;
	auto imp = ad._import.isImport();
	if (!imp)
		return false;

	for (int n = 0; n < imp.aliasdecls.dim && n < imp.aliases.dim; n++)
		if (ad == imp.aliasdecls[n])
			return !imp.aliases[n].ident;
	return false;
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

	override void foundNode(RootObject obj)
	{
		found = obj;
		if (obj)
		{
			tip = tipForObject(obj);
			stop = true;
		}
	}
}

string quoteCode(bool quote, string s)
{
	if (!quote || s.empty)
		return s;
	return "`" ~ s ~ "`";
}

struct TipData
{
	string kind;
	string code;
	string doc;
}

string tipForObject(RootObject obj)
{
	TipData tip = tipDataForObject(obj);

	string txt;
	if (tip.kind.length)
		txt = "(" ~ tip.kind ~ ")";
	if (tip.code.length && txt.length)
		txt ~= " ";
	txt ~= quoteCode(true, tip.code);
	if (tip.doc.length && txt.length)
		txt ~= "\n\n";
	if (tip.doc.length)
		txt ~= strip(tip.doc);
	return txt;
}

TipData tipForDeclaration(Declaration decl)
{
	if (auto func = decl.isFuncDeclaration())
	{
		HdrGenState hgs = { ddoc: true, fullQual: true };
		OutBuffer buf;

		auto fntype = decl.type ? decl.type.isTypeFunction() : null;

		if (auto td = fntype && decl.parent ? decl.parent.isTemplateDeclaration() : null)
			functionToBufferFull(fntype, &buf, decl.getIdent(), &hgs, td);
		else if (fntype)
			functionToBufferWithIdent(fntype, &buf, decl.toPrettyChars(true), &hgs, func.isStatic);
		else
			buf.writestring(decl.toPrettyChars(true));
		auto res = buf.extractSlice(); // take ownership
		return TipData("", cast(string)res);
	}

	bool fqn = true;
	string txt;
	string kind;
	if (decl.isParameter())
	{
		if (decl.parent)
			if (auto fd = decl.parent.isFuncDeclaration())
				if (fd.ident.toString().startsWith("__foreachbody"))
					kind = "foreach variable";
		if (kind.empty)
			kind = "parameter";
		fqn = false;
	}
	else if (auto em = decl.isEnumMember())
	{
		kind = "enum value";
		txt = decl.toPrettyChars(fqn).to!string;
		if (em.origValue)
			txt ~= " = " ~ cast(string)em.origValue.toString();
		return TipData(kind, txt);
	}
	else if (decl.storage_class & STC.manifest)
		kind = "constant";
	else if (decl.isAliasDeclaration())
		kind = "alias";
	else if (decl.isField())
		kind = "field";
	else if (decl.semanticRun >= PASS.semanticdone) // avoid lazy semantic analysis
	{
		if (!decl.isDataseg() && !decl.isCodeseg())
		{
			kind = "local variable";
			fqn = false;
		}
		else if (decl.isThreadlocal())
			kind = "thread local global";
		else if (decl.type && decl.type.isShared())
			kind = "shared global";
		else if (decl.type && decl.type.isConst())
			kind = "constant global";
		else if (decl.type && decl.type.isImmutable())
			kind = "immutable global";
		else if (decl.type && decl.type.ty != Terror)
			kind = "__gshared global";
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
		{
			TipData tip = tipDataForObject(ad.aliassym);
			if (tip.kind.length)
				kind = "alias " ~ tip.kind;
			if (tip.code.length)
				txt ~= " = " ~ tip.code;
		}
	return TipData(kind, txt);
}

TipData tipForType(Type t)
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
	string txt = t.toPrettyChars(true).to!string;
	string doc;
	if (auto sym = typeSymbol(t))
		if (sym.comment)
			doc = sym.comment.to!string;
	return TipData(kind, txt, doc);
}

TipData tipForDotIdExp(DotIdExp die)
{
	auto resolvedTo = die.resolvedTo;
	bool isConstant = resolvedTo.isConstantExpr();
	bool isEnumValue = false;
	if (auto ve = resolvedTo.isVarExp())
		if (auto em = ve.var ? ve.var.isEnumMember() : null)
		{
			isConstant = isEnumValue = true;
			resolvedTo = em.origValue;
		}

	Expression e1;
	if (!isConstant && !resolvedTo.isArrayLengthExp() && die.type)
	{
		e1 = isAALenCall(resolvedTo);
		if (!e1 && die.ident == Id.ptr && resolvedTo.isCastExp())
			e1 = resolvedTo;
		if (!e1 && resolvedTo.isTypeExp())
			return tipForType(die.type);
	}
	if (!e1)
		e1 = die.e1;
	string kind = isEnumValue ? "enum value" : isConstant ? "constant" : "field";
	string tip = isEnumValue ? "" : resolvedTo.type.toPrettyChars(true).to!string ~ " ";
	tip ~= e1.type && !e1.isConstantExpr() ? die.e1.type.toPrettyChars(true).to!string : e1.toString();
	tip ~= "." ~ die.ident.toString();
	if (isConstant)
		tip ~= " = " ~ resolvedTo.toString();
	return TipData(kind, tip);
}

TipData tipForTemplate(TemplateExp te)
{
	Dsymbol ds = te.fd;
	if (!ds)
		ds = te.td.onemember ? te.td.onemember : te.td;
	string kind = ds.isFuncDeclaration() ? "template function" : "template";
	string tip = ds.toPrettyChars(true).to!string;
	return TipData(kind, tip);
}

const(char)* docForSymbol(Dsymbol var)
{
	if (var.comment)
		return var.comment;
	if (var.parent)
	{
		const(char)* docForTemplateDeclaration(Dsymbol s)
		{
			if (s)
				if (auto td = s.isTemplateDeclaration())
					if (td.comment && td.onemember)
						return td.comment;
			return null;
		}

		if (auto doc = docForTemplateDeclaration(var.parent))
			return doc;

		if (auto ti = var.parent.isTemplateInstance())
			if (auto doc = docForTemplateDeclaration(ti.tempdecl))
				return doc;
	}
	return null;
}

TipData tipDataForObject(RootObject obj)
{
	TipData tip;
	const(char)* doc;

	if (auto t = obj.isType())
	{
		tip = tipForType(t.mutableOf().unSharedOf());
	}
	else if (auto e = obj.isExpression())
	{
		switch(e.op)
		{
			case TOK.variable:
			case TOK.symbolOffset:
				tip = tipForDeclaration((cast(SymbolExp)e).var);
				doc = docForSymbol((cast(SymbolExp)e).var);
				break;
			case TOK.dotVariable:
				tip = tipForDeclaration((cast(DotVarExp)e).var);
				doc = docForSymbol((cast(DotVarExp)e).var);
				break;
			case TOK.dotIdentifier:
				auto die = e.isDotIdExp();
				if (die.resolvedTo && die.resolvedTo.type)
				{
					tip = tipForDotIdExp(die);
					break;
				}
				goto default;
			case TOK.template_:
				tip = tipForTemplate((cast(TemplateExp)e));
				break;
			default:
				if (e.type)
					tip = tipForType(e.type);
				break;
		}
	}
	else if (auto s = obj.isDsymbol())
	{
		if (auto imp = s.isImport())
			if (imp.mod)
				s = imp.mod;
		auto ad = s.isAliasDeclaration();
		if (isUnnamedSelectiveImportAlias(ad) && !ad.aliassym && ad.type) // selective import of type
		{
			tip = tipForType(ad.type.mutableOf().unSharedOf());
		}
		else if (auto decl = s.isDeclaration())
		{
			tip = tipForDeclaration(decl);
			doc = docForSymbol(s);
		}
		else
		{
			tip.kind = s.kind().to!string;
			tip.code = s.toPrettyChars(true).to!string;
			doc = docForSymbol(s);
		}
	}
	else if (auto p = obj.isParameter())
	{
		if (auto t = p.type ? p.type : p.parsedType)
			tip.code = t.toPrettyChars(true).to!string;
		if (p.ident && tip.code.length)
			tip.code ~= " ";
		if (p.ident)
			tip.code ~= p.ident.toString;
		tip.kind = "parameter";
	}
	if (!tip.code.length)
	{
		tip.code = obj.toString().dup;
	}
	// append doc
	if (doc)
		tip.doc = cast(string)doc[0..strlen(doc)];
	return tip;
}

static const(char)* printSymbolWithLink(Dsymbol sym, bool qualifyTypes)
{
	const(char)* s = qualifyTypes ? sym.toPrettyCharsHelper() : sym.toChars();

	if (auto ti = sym.isTemplateInstance())
		if (ti.tempdecl)
			if (auto td = ti.tempdecl.isTemplateDeclaration())
				sym = td.onemember ? td.onemember : td;

	if (!sym.loc.filename)
		return s;

    import dmd.root.string : toDString;
    import dmd.utf;
	auto str = s.toDString();
	size_t p = 0;
	while (p < str.length)
	{
		char c = str[p];
		if (c < 0x80)
		{
			if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'))
				break;
			p++;
		}
		else
		{
			dchar dch;
			size_t pos = p;
			if (utf_decodeChar(str, pos, dch) !is null)
				break;
			if (!isUniAlpha(dch))
				break;
			p = pos;
		}
	}
	OutBuffer lnkbuf;
	lnkbuf.writestring("#<");
	lnkbuf.writestring(str[0..p]);
	lnkbuf.writeByte('#');
	lnkbuf.writestring(sym.loc.filename);
	if (sym.loc.linnum > 0) // no lineno for modules
	{
		lnkbuf.writeByte(',');
		lnkbuf.print(sym.loc.linnum);
		lnkbuf.writeByte(',');
		lnkbuf.print(sym.loc.charnum);
	}
	lnkbuf.writestring("#>");
	lnkbuf.writestring(str[p..$]);
	return lnkbuf.extractChars();
}

string findTip(Module mod, int startLine, int startIndex, int endLine, int endIndex, bool addlinks)
{
	auto old = Dsymbol.prettyPrintSymbolHandler;
	if (addlinks)
		Dsymbol.prettyPrintSymbolHandler = toDelegate(&printSymbolWithLink);
	scope(exit) Dsymbol.prettyPrintSymbolHandler = old;

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

	override void foundNode(RootObject obj)
	{
		found = obj;
		while (obj) // resolving aliases
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
				auto ad = s.isAliasDeclaration();
				if (ad && ad._import) // selective import
				{
					if (ad.aliassym)
					{
						found = obj = ad.aliassym;
						continue;
					}
					else if (ad.type)
					{
						found = obj = ad.type;
						continue;
					}
				}
				if (!s.loc.isValid())
				{
					if (auto td = s.isTemplateDeclaration())
					{
						if (td.onemember)
						{
							found = obj = td.onemember;
							continue;
						}
					}
				}
				loc = s.loc;
			}
			break;
		}
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
				if (!sections[1].empty)
				{} // do not overwrite identical location
				else if (!sections[2].empty && sections[2][0].type == type) // upperbound
					sections[2][0] = itp; // extend lowest location
				else if (sections[0].empty || sections[0][$-1].type != type) // lowerbound
					// insert new entry if last lower location is different type
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
				if (func.isFuncLiteralDeclaration())
					return; // ignore generated identifiers
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
			else if (auto ad = decl.isAliasDeclaration())
			{
				if (isUnnamedSelectiveImportAlias(ad) && !ad.aliassym && ad.type)
					addIdentByType(loc, ident, ad.type);
				else
					addIdent(loc, ident, TypeReferenceKind.Alias);
			}
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

		override void visit(TypeQualified tid)
		{
			foreach (i, id; tid.idents)
			{
				RootObject obj = id;
				if (obj.dyncast() == DYNCAST.identifier)
				{
					auto ident = cast(Identifier)obj;
					if (tid.parentScopes.dim > i + 1)
						addObject(id.loc, tid.parentScopes[i + 1]);
				}
			}
			super.visit(tid);
		}

		override void visit(TypeIdentifier tid)
		{
			while (tid.copiedFrom)
			{
				if (tid.parentScopes.dim > 0)
					break;
				tid = tid.copiedFrom;
			}
			if (tid.parentScopes.dim > 0)
				addObject(tid.loc, tid.parentScopes[0]);
			super.visit(tid);
		}

		override void visit(TypeInstance tid)
		{
			if (!tid.tempinst)
				return;
			if (tid.parentScopes.dim > 0)
				addObject(tid.loc, tid.parentScopes[0]);
			super.visit(tid);
		}

		void addObject(ref const Loc loc, RootObject obj)
		{
			if (auto t = obj.isType())
				visitType(t);
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
			else if (sym.isUnionDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Union);
			else if (sym.isStructDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Struct);
			else if (sym.isInterfaceDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Interface);
			else if (sym.isClassDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Class);
			else if (sym.isEnumDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Enum);
			else if (sym.isModule())
				addIdent(loc, sym.ident, TypeReferenceKind.Module);
			else if (sym.isPackage())
				addIdent(loc, sym.ident, TypeReferenceKind.Package);
			else if (sym.isTemplateDeclaration())
				addIdent(loc, sym.ident, TypeReferenceKind.Template);
			else
				addIdent(loc, sym.ident, TypeReferenceKind.Variable);
		}

		override void visit(Dsymbol sym)
		{
			addSymbol(sym.loc, sym);
		}

		override void visitParameter(Parameter sym, Declaration decl)
		{
			super.visitParameter(sym, decl);
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
				if (n < imp.aliasdecls.dim && imp.aliasdecls[n].aliassym)
					addSymbol(imp.names[n].loc, imp.aliasdecls[n].aliassym);
				else if (n < imp.aliasdecls.dim && imp.aliasdecls[n].type)
					addIdentByType(imp.names[n].loc, imp.names[n].ident, imp.aliasdecls[n].type);
				else
					addIdent(imp.names[n].loc, imp.names[n].ident, TypeReferenceKind.Alias);
				if (imp.aliases[n].ident && n < imp.aliasdecls.dim)
					addIdent(imp.aliases[n].loc, imp.aliases[n].ident, TypeReferenceKind.Alias);
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

		override void visit(SymbolExp expr)
		{
			if (expr.var && expr.var.ident)
				addDeclaration(expr.loc, expr.var);
			super.visit(expr);
		}

		void addIdentExp(Expression expr, Type t)
		{
			if (auto ie = expr.isIdentifierExp())
			{
				addIdentByType(ie.loc, ie.ident, t);
			}
			else if (auto die = expr.isDotIdExp())
			{
				addIdentByType(die.ident.loc, die.ident, t);
			}
		}

		void addOriginal(Expression expr, Type t)
		{
			for (auto ce = expr.isCommaExp(); ce; ce = expr.isCommaExp())
			{
				addIdentExp(ce.e1, t);
				expr = ce.e2;
			}
			addIdentExp(expr, t);
		}

		override void visit(TypeExp expr)
		{
			if (expr.original && expr.type)
				addOriginal(expr.original, expr.type);

			super.visit(expr);
		}

		override void visit(IdentifierExp expr)
		{
			if (expr.resolvedTo)
				if (auto se = expr.resolvedTo.isScopeExp())
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
			auto orig = expr.resolvedTo;
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

		override void visit(EnumDeclaration ed)
		{
			addIdent(ed.loc, ed.ident, TypeReferenceKind.Enum);
			super.visit(ed);
		}

		override void visit(FuncDeclaration decl)
		{
			super.visit(decl);

			if (decl.originalType)
			{
				auto ot = decl.originalType ? decl.originalType.isTypeFunction() : null;
				visitType(ot ? ot.nextOf() : null); // the return type
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

		override void visit(AliasDeclaration ad)
		{
			// the alias identifier can be both before and after the aliased type,
			//  but we rely on so ascending locations in addTypePos
			// as a work around, add the declared identifier before and after
			//  by processing it twice
			super.visit(ad);
			super.visit(ad);
		}
	}

	scope IdentifierTypesVisitor itv = new IdentifierTypesVisitor;
	itv.filename = mod.srcfile.toChars();
	mod.accept(itv);

	return itv.idTypes;
}

////////////////////////////////////////////////////////////////////////////////
struct ParameterStorageClassPos
{
	int type; // ref, out, lazy
	int line;
	int col;
}

ParameterStorageClassPos[] findParameterStorageClass(Module mod)
{
	extern(C++) class ParameterStorageClassVisitor : ASTVisitor
	{
		ParameterStorageClassPos[] stcPos;
		const(char)* filename;

		alias visit = ASTVisitor.visit;

		final void addParamPos(int type, int line, int col)
		{
			auto psp = ParameterStorageClassPos(type, line, col);
			stcPos ~= psp;
		}
		final void addParamPos(int type, Expression expr)
		{
			if (expr.loc.filename is filename)
				addParamPos(type, expr.loc.linnum, expr.loc.charnum);
		}
		final void addLazyParamPos(int type, Expression expr)
		{
			if (!expr.loc.filename)
				// drill into generated function for lazy parameter
				if (expr.op == TOK.function_)
					if (auto fd = (cast(FuncExp)expr).fd)
						if (fd.fbody)
							if (auto cs = fd.fbody.isCompoundStatement())
								if (cs.statements && cs.statements.length)
									if (auto rs = (*cs.statements)[0].isReturnStatement())
										expr = rs.exp;

			if (expr.loc.filename is filename)
				addParamPos(type, expr.loc.linnum, expr.loc.charnum);
		}

		override void visit(CallExp expr)
		{
			if (expr.arguments && expr.arguments.length)
			{
				if (auto tf = expr.f ? expr.f.type.isTypeFunction() : null)
				{
					if (auto params = tf.parameterList.parameters)
					{
						size_t cnt = min(expr.arguments.length, params.length);
						for (size_t p = 0; p < cnt; p++)
						{
							auto stc = (*params)[p].storageClass;
							if (stc & STC.ref_)
							{
								if (stc & (STC.in_ | STC.const_))
									continue;
								if((*params)[p].type && !(*params)[p].type.isMutable())
									continue;
								addParamPos(0, (*expr.arguments)[p]);
							}
							else if (stc & STC.out_)
								addParamPos(1, (*expr.arguments)[p]);
							else if (stc & STC.lazy_)
								addLazyParamPos(2, (*expr.arguments)[p]);
						}
					}
				}
			}
			super.visit(expr);
		}
	}

	scope psv = new ParameterStorageClassVisitor;
	psv.filename = mod.srcfile.toChars();
	mod.accept(psv);

	return psv.stcPos;
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
		const(char)* filename;

		alias visit = ASTVisitor.visit;

		extern(D)
		void addReference(ref const Loc loc, Identifier ident)
		{
			if (loc.filename is filename && ident)
				if (!references.contains(Reference(loc, ident)))
					references ~= Reference(loc, ident);
		}

		void addResolved(ref const Loc loc, Expression resolved)
		{
			if (resolved)
				if (auto se = resolved.isScopeExp())
					if (se.sds is search)
						addReference(loc, se.sds.ident);
		}

		void addPackages(Module mod, IdentifiersAtLoc* packages)
		{
			if (!mod || !packages)
				return;

			Package pkg = mod.parent ? mod.parent.isPackage() : null;
			for (size_t p; pkg && p < packages.dim; p++)
			{
				size_t q = packages.dim - 1 - p;
				if (pkg is search)
					addReference((*packages)[q].loc, (*packages)[q].ident);
				if (auto parent = pkg.parent)
					pkg = parent.isPackage();
			}
		}

		override void visit(Dsymbol sym)
		{
			if (sym is search)
				addReference(sym.loc, sym.ident);
			super.visit(sym);
		}
		override void visit(Module mod)
		{
			if (mod.md)
			{
				addPackages(mod, mod.md.packages);
				if (mod is search)
					addReference(mod.md.loc, mod.md.id);
			}
			visit(cast(Package)mod);
		}

		override void visit(Import imp)
		{
			addPackages(imp.mod, imp.packages);

			if (imp.mod is search)
				addReference(imp.loc, imp.id);

			for (int n = 0; n < imp.names.dim; n++)
			{
				// names? (imp.names[n].loc, imp.names[n].ident)
				if (n < imp.aliasdecls.dim)
					if (imp.aliasdecls[n].aliassym is search)
						addReference(imp.names[n].loc, imp.names[n].ident);
			}
			// symbol has ident of first package, so don't forward
		}

		override void visit(SymbolExp expr)
		{
			if (expr.var is search)
				addReference(expr.loc, expr.var.ident);
			super.visit(expr);
		}
		override void visit(DotVarExp dve)
		{
			if (dve.var is search)
				addReference(dve.varloc.filename ? dve.varloc : dve.loc, dve.var.ident);
			super.visit(dve);
		}
		override void visit(TypeExp te)
		{
			if (auto ts = typeSymbol(te.type))
			    if (ts is search)
			        addReference(te.loc, ts.ident);
			super.visit(te);
		}

		override void visit(IdentifierExp expr)
		{
			addResolved(expr.loc, expr.resolvedTo);
			super.visit(expr);
		}

		override void visit(DotIdExp expr)
		{
			addResolved(expr.identloc, expr.resolvedTo);
			super.visit(expr);
		}

		override void visit(TypeQualified tid)
		{
			foreach (i, id; tid.idents)
			{
				RootObject obj = id;
				if (obj.dyncast() == DYNCAST.identifier)
				{
					auto ident = cast(Identifier)obj;
					if (tid.parentScopes.dim > i + 1)
						if (tid.parentScopes[i + 1] is search)
							addReference(id.loc, ident);
				}
			}
			super.visit(tid);
		}

		override void visit(TypeIdentifier tid)
		{
			while (tid.copiedFrom)
			{
				if (tid.parentScopes.dim > 0)
					break;
				tid = tid.copiedFrom;
			}
			if (tid.parentScopes.dim > 0)
				if (tid.parentScopes[0] is search)
					addReference(tid.loc, tid.ident);

			super.visit(tid);
		}

		override void visit(TypeInstance tid)
		{
			if (!tid.tempinst)
				return;
			if (tid.parentScopes.dim > 0)
				if (tid.parentScopes[0] is search)
					addReference(tid.loc, tid.tempinst.name);

			super.visit(tid);
		}

		override void visitParameter(Parameter p, Declaration decl)
		{
			if (decl is search)
				addReference(decl.loc, decl.ident);
			super.visitParameter(p, decl);
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
	frv.filename = filename;
	mod.accept(frv);

	return frv.references;
}

////////////////////////////////////////////////////////////////////////////////
string symbol2ExpansionType(Dsymbol sym)
{
	if (sym.isInterfaceDeclaration())
		return "IFAC";
	if (sym.isClassDeclaration())
		return "CLSS";
	if (sym.isUnionDeclaration())
		return "UNIO";
	if (sym.isStructDeclaration())
		return "STRU";
	if (sym.isEnumDeclaration())
		return "ENUM";
	if (sym.isEnumMember())
		return "EVAL";
	if (sym.isAliasDeclaration())
		return "ALIA";
	if (sym.isTemplateDeclaration())
		return "TMPL";
	if (sym.isTemplateMixin())
		return "NMIX";
	if (sym.isModule())
		return "MOD";
	if (sym.isPackage())
		return "PKG";
	if (sym.isFuncDeclaration())
	{
		auto p = sym.toParent2;
		return p && p.isAggregateDeclaration ? "MTHD" : "FUNC";
	}
	if (sym.isVarDeclaration())
	{
		auto p = sym.toParent2;
		return p && p.isAggregateDeclaration ? "PROP" : "VAR"; // "SPRP"?
	}
	if (sym.isOverloadSet())
		return "OVR";
	return "TEXT";
}

string symbol2ExpansionLine(Dsymbol sym)
{
	string type = symbol2ExpansionType(sym);
	string tip = tipForObject(sym);
	return type ~ ":" ~ tip.replace("\n", "\a");
}

string[string] initSymbolProperties(int kind)
{
	string[string] props;
	// generic
	props["init"] = "PROP:A type's or variable's static initializer expression";
	props["sizeof"] = "PROP:Size of a type or variable in bytes";
	props["alignof"] = "PROP:Variable alignment";
	props["mangleof"] = "PROP:String representing the ‘mangled’ representation of the type";
	props["stringof"] = "PROP:String representing the source representation of the type";

	switch (kind)
	{
		case 0:
			// numeric types
			props["max"] = "PROP:Maximum value";
			props["min"] = "PROP:Minimum value";
			break;
		case 1:
			// floating point
			props["infinity"] = "PROP:Infinity value";
			props["nan"] = "PROP:Not-a-Number value";
			props["dig"] = "PROP:Number of decimal digits of precision";
			props["epsilon"] = "PROP:Smallest increment to the value 1";
			props["mant_dig"] = "PROP:Number of bits in mantissa";
			props["max_10_exp"] = "PROP:Maximum int value such that 10^max_10_exp is representable";
			props["max_exp"] = "PROP:Maximum int value such that 2^max_exp-1 is representable";
			props["min_10_exp"] = "PROP:Minimum int value such that 10^max_10_exp is representable";
			props["min_exp"] = "PROP:Minimum int value such that 2^max_exp-1 is representable";
			props["min_normal"] = "PROP:Number of decimal digits of precision";
			// require this
			props["re"] = "PROP:Real part of a complex number";
			props["im"] = "PROP:Imaginary part of a complex number";
			break;
		case 2:
			// arrays (require this)
			props["length"] = "PROP:Array length";
			props["dup"] = "PROP:Create a dynamic array of the same size and copy the contents of the array into it.";
			props["idup"] = "PROP:Creates immutable copy of the array";
			props["reverse"] = "PROP:Reverses in place the order of the elements in the array. Returns the array.";
			props["sort"] = "PROP:Sorts in place the order of the elements in the array. Returns the array.";
			props["ptr"] = "PROP:Returns pointer to the array";
			break;
		case 3:
			// assoc array (require this)
			props["length"] = "PROP:Returns number of values in the associative array. Unlike for dynamic arrays, it is read-only.";
			props["keys"] = "PROP:Returns dynamic array, the elements of which are the keys in the associative array.";
			props["values"] = "PROP:Returns dynamic array, the elements of which are the values in the associative array.";
			props["rehash"] = "PROP:Reorganizes the associative array in place so that lookups are more efficient." ~
				" rehash is effective when, for example, the program is done loading up a symbol table and now needs fast lookups in it." ~
				" Returns a reference to the reorganized array.";
			props["byKey"] = "PROP:Returns a delegate suitable for use as an aggregate to a `foreach` which will iterate over the keys of the associative array.";
			props["byValue"] = "PROP:Returns a delegate suitable for use as an aggregate to a `foreach` which will iterate over the values of the associative array.";
			props["get"] = "Looks up key; if it exists returns corresponding value else evaluates and returns defaultValue.";
			props["remove"] = "remove(key) does nothing if the given key does not exist and returns false. If the given key does exist, it removes it from the AA and returns true.";
			break;
		case 4:
			// static array (require this)
			props["length"] = "PROP:Returns number of values in the type tuple.";
			break;
		case 5:
			// delegate (require this)
			props["ptr"] = "PROP:The .ptr property of a delegate will return the frame pointer value as a void*.";
			props["funcptr"] = "PROP:The .funcptr property of a delegate will return the function pointer value as a function type.";
			break;
		case 6:
			// class (require this)
			props["classinfo"] = "PROP:Information about the dynamic type of the class";
			break;
		case 7:
			// struct
			props["sizeof"] = "PROP:Size in bytes of struct";
			props["alignof"] = "PROP:Size boundary struct needs to be aligned on";
			props["tupleof"] = "PROP:Gets type tuple of fields";
			break;
		default:
			break;
	}
	return props;
}

const string[string] genericProps;
const string[string] integerProps;
const string[string] floatingProps;
const string[string] dynArrayProps;
const string[string] assocArrayProps;
const string[string] staticArrayProps;
const string[string] delegateProps;
const string[string] classProps;
const string[string] structProps;

shared static this()
{
	genericProps     = initSymbolProperties (-1);
	integerProps     = initSymbolProperties (0);
	floatingProps    = initSymbolProperties (1);
	dynArrayProps    = initSymbolProperties (2);
	assocArrayProps  = initSymbolProperties (3);
	staticArrayProps = initSymbolProperties (4);
	delegateProps    = initSymbolProperties (5);
	classProps       = initSymbolProperties (6);
	structProps      = initSymbolProperties (7);
}

void addSymbolProperties(ref string[] expansions, RootObject sym, string tok)
{
	bool hasThis = false;
	Type t = sym.isType();
	if (auto e = sym.isExpression())
	{
		t = e.type;
		hasThis = true;
	}
	if (!t)
		return;

	const string[string] props = t.isTypeClass()    && hasThis ? classProps
	                           : t.isTypeStruct()              ? structProps
	                           : t.isTypeDelegate() && hasThis ? delegateProps
	                           : t.isTypeSArray()   && hasThis ? staticArrayProps
	                           : t.isTypeAArray()   && hasThis ? assocArrayProps
	                           : t.isTypeDArray()   && hasThis ? dynArrayProps
	                           : t.isfloating()     ? floatingProps
	                           : t.isintegral()     ? integerProps
	                           : genericProps;
	foreach (id, p; props)
		if (id.startsWith(tok))
			expansions ~= id ~ ":" ~ p;
}

////////////////////////////////////////////////////////////////

extern(C++) class FindExpansionsVisitor : FindASTVisitor
{
	alias visit = FindASTVisitor.visit;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		super(filename, startLine, startIndex, endLine, endIndex);
	}

	override void visit(IdentifierExp expr)
	{
		if (!found && expr.ident)
		{
			if (matchIdentifier(expr.loc, expr.ident))
			{
				foundNode(expr);
			}
		}
		// skip base class to avoid matching resolved expression
		visit(cast(Expression)expr);
	}

	override void visit(SymbolExp expr)
	{
		if (!found && expr.var && !expr.original) // do not match lowered VarExp
			if (matchIdentifier(expr.loc, expr.var.ident))
				foundNode(expr);
		// skip base class to avoid matching lowered expression
		visit(cast(Expression)expr);
	}

	override void visit(DotVarExp dve)
	{
		if (!found && dve.var && dve.var.ident)
			if (matchIdentifier(dve.varloc.filename ? dve.varloc : dve.loc, dve.var.ident))
				foundNode(dve);
	}

	override void visit(DotIdExp de)
	{
		if (!found && de.ident)
		{
			if (matchIdentifier(de.identloc, de.ident))
			{
				if (!de.type && de.resolvedTo && !de.resolvedTo.isErrorExp())
					foundResolved(de.resolvedTo);
				else
					foundNode(de);
			}
		}
	}

	override void checkScope(ScopeDsymbol sc)
	{
		if (sc && !foundScope)
		{
			if (sc.loc.filename !is filename || sc.loc.linnum > endLine)
				return;
			if (sc.loc.linnum == endLine && sc.loc.charnum > endIndex)
				return;
			if (sc.endlinnum < startLine)
				return;
			if (sc.endlinnum == startLine && sc.endcharnum < startIndex)
				return;

			foundScope = sc;
			stop = true;
		}
	}
}

string[] findExpansions(Module mod, int line, int index, string tok)
{
	auto filename = mod.srcfile.toChars();
	scope FindExpansionsVisitor fdv = new FindExpansionsVisitor(filename, line, index, line, index + 1);
	mod.accept(fdv);

	if (!fdv.found && !fdv.foundScope)
		fdv.foundScope = mod;

	int flags = 0;
	Type type = fdv.found ? fdv.found.isType() : null;
	if (auto e = fdv.found ? fdv.found.isExpression() : null)
	{
		Type getType(Expression e, bool recursed)
		{
			switch(e.op)
			{
				case TOK.variable:
				case TOK.symbolOffset:
					if(recursed)
						return (cast(SymbolExp)e).var.type;
					return null;

				case TOK.dotVariable:
				case TOK.dotIdentifier:
					flags |= SearchLocalsOnly;
					if (recursed)
						if (auto dve = e.isDotVarExp())
							if (dve.varloc.filename)  // skip compiler generated idents (alias this)
								return dve.var.type;

					auto e1 = (cast(UnaExp)e).e1;
					return getType(e1, true);

				case TOK.dot:
					flags |= SearchLocalsOnly;
					return (cast(DotExp)e).e1.type;
				default:
					return recursed ? e.type : null;
			}
		}
		if (auto t = getType(e, false))
			type = t;
	}

	auto sds = fdv.foundScope;
	if (type)
		if (auto sym = typeSymbol(type))
			sds = sym;
	if (!sds)
		sds = mod;

	string[void*] idmap; // doesn't work with extern(C++) classes
	DenseSet!ScopeDsymbol searched;

	void searchScope(ScopeDsymbol sds, int flags)
	{
		if (searched.contains(sds))
			return;
		searched.insert(sds);

		static Dsymbol uplevel(Dsymbol s)
		{
			if (auto ad = s.isAggregateDeclaration())
				if (ad.enclosing)
					return ad.enclosing;
			return s.toParent;
		}
		// TODO: struct/class not going to parent if accessed from elsewhere (but does if nested)
		// TODO: UFCS
		for (Dsymbol ds = sds; ds; ds = uplevel(ds))
		{
			ScopeDsymbol sd = ds.isScopeDsymbol();
			if (!sd)
				continue;

			//foreach (pair; sd.symtab.tab.asRange)
			if (sd.symtab)
			{
				foreach (kv; sd.symtab.tab.asRange)
				{
					//Dsymbol s = pair.value;
					if (!symbolIsVisible(mod, kv.value))
						continue;
					auto ident = /*pair.*/(cast(Identifier)kv.key).toString();
					if (ident.startsWith(tok))
						idmap[cast(void*)kv.value] = ident.idup;
				}
			}

			void searchScopeSymbol(ScopeDsymbol sym)
			{
				if (!sym)
					return;
				int sflags = SearchLocalsOnly;
				if (sym.getModule() == mod)
					sflags |= IgnoreSymbolVisibility;
				searchScope(sym, sflags);
			}
			// base classes
			if (auto cd = ds.isClassDeclaration())
			{
				if (auto bcs = cd.baseclasses)
					foreach (bc; *bcs)
						searchScopeSymbol(bc.sym);
			}
			// with statement
			if (auto ws = ds.isWithScopeSymbol())
			{
				Expression eold = null;
				for (Expression e = ws.withstate.exp; e != eold; e = resolveAliasThis(ws._scope, e))
				{
					if (auto se = e.isScopeExp())
						searchScopeSymbol(se.sds);
					else if (auto te = e.isTypeExp())
						searchScopeSymbol(te.type.toDsymbol(null).isScopeDsymbol());
					else
						searchScopeSymbol(e.type.toBasetype().toDsymbol(null).isScopeDsymbol());
					eold = e;
				}
			}
			// alias this
			if (auto ad = ds.isAggregateDeclaration())
			{
				Declaration decl = ad.aliasthis && ad.aliasthis.sym ? ad.aliasthis.sym.isDeclaration() : null;
				if (decl)
				{
					Type t = decl.type;
					if (auto ts = t.isTypeStruct())
						searchScopeSymbol(ts.sym);
					else if (auto tc = t.isTypeClass())
						searchScopeSymbol(tc.sym);
					else if (auto ti = t.isTypeInstance())
						searchScopeSymbol(ti.tempinst);
					else if (auto te = t.isTypeEnum())
						searchScopeSymbol(te.sym);
				}
			}

			if (flags & SearchLocalsOnly)
				break;

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
		if (!id.startsWith("__"))
			idlist ~= id ~ ":" ~ symbol2ExpansionLine(cast(Dsymbol)sym);

	if (type)
		addSymbolProperties(idlist, type, tok);

	return idlist;
}

////////////////////////////////////////////////////////////////////////////////
string[] getModuleOutline(Module mod, int maxdepth)
{
	extern(C++) class OutlineVisitor : ASTVisitor
	{
		string[] lines;
		int maxdepth;
		int depth = 1;

		alias visit = ASTVisitor.visit;

		extern(D)
		void addOutline(ref const Loc loc, int endln, Dsymbol decl)
		{
			if (!loc.filename) // ignore compiler added symbols
				return;

			import dmd.root.string : toDString;
			auto desc = toDString(decl.toPrettyChars());
			if (auto fd = decl.isFuncDeclaration())
				if (auto tf = fd.type ? fd.type.isTypeFunction() : null)
				{
					auto td = decl.parent ? decl.parent.isTemplateDeclaration() : null;
					if (!td || fd != td.onemember) // parameters already printed in function templates
						desc ~= toDString(parametersTypeToChars(tf.parameterList));
				}

			string txt = depth.to!string ~ ":" ~ loc.linnum.to!string ~ ":" ~ endln.to!string ~ ":";
			string cat = symbol2ExpansionType(decl);
			txt ~= cat ~ ":" ~ desc;
			lines ~= txt;
		}

		override void visit(FuncDeclaration fd)
		{
			addOutline(fd.loc, fd.endloc.linnum, fd);
			if (depth < maxdepth)
			{
				depth++;
				super.visit(fd);
				depth--;
			}
		}

		override void visit(EnumDeclaration ed)
		{
			if (ed.ident)
				addOutline(ed.loc, ed.endlinnum, ed);
			if (depth < maxdepth)
			{
				depth++;
				super.visit(ed);
				depth--;
			}
		}

		override void visit(AggregateDeclaration ad)
		{
			addOutline(ad.loc, ad.endlinnum, ad);
			if (depth < maxdepth)
			{
				depth++;
				super.visit(ad);
				depth--;
			}
		}

		override void visit(TemplateDeclaration td)
		{
			addOutline(td.loc, td.endlinnum, td);
			if (!td.loc.filename)
				super.visit(td);
			else if (depth < maxdepth)
			{
				depth++;
				super.visit(td);
				depth--;
			}
		}

	}

	scope ov = new OutlineVisitor();
	ov.maxdepth = maxdepth;
	mod.accept(ov);

	return ov.lines;
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
			unconditional = true;
		}

		alias visit = ASTVisitor.visit;

		override void visit(ConditionalStatement cond)
		{
			if (auto dbg = cond.condition.isDebugCondition())
				cond.condition = new DebugCondition(dbg.loc, m, dbg.level, dbg.ident);
			else if (auto ver = cond.condition.isVersionCondition())
				cond.condition = new VersionCondition(ver.loc, m, ver.level, ver.ident);
			super.visit(cond);
		}

		override void visit(ConditionalDeclaration cond)
		{
			if (auto dbg = cond.condition.isDebugCondition())
				cond.condition = new DebugCondition(dbg.loc, m, dbg.level, dbg.ident);
			else if (auto ver = cond.condition.isVersionCondition())
				cond.condition = new VersionCondition(ver.loc, m, ver.level, ver.ident);
			super.visit(cond);
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

