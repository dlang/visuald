// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.vdserver;

version(MAIN) {} else version = noServer;

version(noServer):
import vdc.ivdserver;
import vdc.semantic;
import vdc.interpret;
import vdc.logger;
import vdc.util;
import vdc.lexer;
import vdc.parser.engine;
import vdc.parser.expr;
import ast = vdc.ast.all;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import stdext.com;
import stdext.string;
import stdext.array;

version = SingleThread;

//import std.stdio;
import std.parallelism;
import std.string;
import std.conv;
import std.array;

import std.concurrency;
import std.datetime;
import core.thread;
import core.time;

debug version = DebugServer;
//debug version = vdlog; // log through visual D logging (needs version = InProc in vdserverclient)

///////////////////////////////////////////////////////////////////////
version(DebugServer)
{
	import std.windows.charset;
	import std.datetime;
	version(vdlog) debug import visuald.logutil;
	import core.stdc.stdio : fprintf, fopen, fputc, fflush, FILE;
	__gshared FILE* dbgfh;

	void dbglog(string s)
	{
		debug
		{
			version(vdlog)
				logCall("VDServer: ", s);
			else
				sdk.win32.winbase.OutputDebugStringA(toMBSz("VDServer: " ~ s ~ "\n"));
		}
		else
		{
			if(!dbgfh)
				dbgfh = fopen("c:/tmp/vdserver.log", "w");

			SysTime now = Clock.currTime();
			uint tid = sdk.win32.winbase.GetCurrentThreadId();
			auto len = fprintf(dbgfh, "%02d:%02d:%02d - %04x - ",
							   now.hour, now.minute, now.second, tid);
			fprintf(dbgfh, "%.*s", s.length, s.ptr);
			fputc('\n', dbgfh);
			fflush(dbgfh);
		}
	}
}

alias object.AssociativeArray!(string, std.concurrency.Tid) _wa1; // fully instantiate type info for string[Tid]
alias object.AssociativeArray!(std.concurrency.Tid, string[]) _wa2; // fully instantiate type info for string[Tid]

///////////////////////////////////////////////////////////////

struct delegate_fake
{
	ptrdiff_t ptr;
	ptrdiff_t context;
}

class VDServer : ComObject, IVDServer
{
	this()
	{
		mSemanticProject = new vdc.semantic.Project;
		mSemanticProject.saveErrors = true;
		fnSemanticWriteError = &semanticWriteError;
		version(SingleThread) mTid = spawn(&taskLoop, thisTid);
	}

	override ULONG Release()
	{
		if(count == 1 && mTid != mTid.init)
		{
			// avoid recursive calls if the object is temporarily ref-counted
			// while executing Dispose()
			count = 0x12345678;

			send(mTid, "stop");
			receive((string val) { assert(val == "done"); });

			assert(count == 0x12345678);
			count = 1;
		}
		return super.Release();
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
//		MessageBoxW(null, "Object1.QueryInterface"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
		if(queryInterface!(IVDServer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	extern(D) static void taskLoop(Tid tid)
	{
		bool cont = true;
		while(cont)
		{
			try
			{
				receiveTimeout(dur!"msecs"(50),
							   (delegate_fake dg_fake)
							   {
								   void delegate() dg = *(cast(void delegate()*)&dg_fake);
								   dg();
							   },
							   (string cmd)
							   {
									if(cmd == "stop")
										cont = false;
							   },
							   (Variant var)
							   {
								   var = var;
							   }
							   );
			}
			catch(Throwable e)
			{
				version(DebugCmd) dbglog ("taskLoop exception: " ~ e.msg);
			}
		}
		prioritySend(tid, "done");
	}

	extern(D) void schedule(void delegate() dg)
	{
		version(SingleThread)
			send(mTid, *cast(delegate_fake*)&dg);
		else
			runTask(dg);
	}

	override HRESULT ConfigureSemanticProject(in BSTR filename, in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags)
	{
		string fname = to_string(filename);

		synchronized(mSemanticProject)
		{
			auto opts = mSemanticProject.options;
			if(fname.length)
				if(auto sm = fname in mSemanticProject.mSourcesByFileName)
					if(sm.analyzed)
						opts = sm.analyzed.getOptions();

			string imports = to_string(imp);
			string strImports = to_string(stringImp);

			uint oldflags = ConfigureFlags!()(opts.unittestOn, opts.debugOn, opts.x64,
											  opts.coverage, opts.doDoc, opts.noBoundsCheck, opts.gdcCompiler,
											  0, 0, // no need to compare version levels, done in setVersionIds
											  opts.noDeprecated, opts.ldcCompiler, opts.msvcrt,
											  opts.mixinAnalysis, opts.UFCSExpansions);

			opts.unittestOn     = (flags & 1) != 0;
			opts.debugOn        = (flags & 2) != 0;
			opts.x64            = (flags & 4) != 0;
			opts.coverage       = (flags & 8) != 0;
			opts.doDoc          = (flags & 16) != 0;
			opts.noBoundsCheck  = (flags & 32) != 0;
			opts.gdcCompiler    = (flags & 64) != 0;
			opts.noDeprecated   = (flags & 128) != 0;
			opts.mixinAnalysis  = (flags & 0x1_00_00_00) != 0;
			opts.UFCSExpansions = (flags & 0x2_00_00_00) != 0;
			opts.ldcCompiler    = (flags & 0x4_00_00_00) != 0;
			opts.msvcrt         = (flags & 0x8_00_00_00) != 0;

			int versionlevel = (flags >> 8)  & 0xff;
			int debuglevel   = (flags >> 16) & 0xff;

			string verids = to_string(versionids);
			string dbgids = to_string(debugids);

			int changed = (oldflags != (flags & 0xff0000ff));
			changed += opts.setImportDirs(splitLines(imports));
			changed += opts.setStringImportDirs(splitLines(strImports));
			changed += opts.setVersionIds(versionlevel, splitLines(verids));
			changed += opts.setDebugIds(debuglevel, splitLines(dbgids));
		}
		return S_OK;
	}

	override HRESULT ClearSemanticProject()
	{
		synchronized(mSemanticProject)
			mSemanticProject.disconnectAll();

		mSemanticProject = new vdc.semantic.Project;
		mSemanticProject.saveErrors = true;
		return S_OK;
	}

	override HRESULT UpdateModule(in BSTR filename, in BSTR srcText, in DWORD flags)
	{
		string fname = to_string(filename);
		string text  = to_string(srcText);

		auto parser = new Parser;
		parser.saveErrors = true;

		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
			{
				if(src.parser)
					src.parser.abort = true;
				src.parser = parser;
			}

		void doParse()
		{
			version(DebugServer) dbglog("    doParse: " ~ firstLine(text));

			if (flags & 1)
				semanticWriteError(MessageType.Message, fname ~ ": parsing...");

			ast.Node n;
			try
			{
				n = parser.parseModule(text);
			}
			catch(Throwable t)
			{
				version(DebugServer) dbglog("UpdateModule.doParse: exception " ~ t.msg);
				logInfo(t.msg);
			}

			if(flags & 1)
				writeReadyMessage();

			synchronized(mSemanticProject)
				if(auto src = mSemanticProject.getModuleByFilename(fname))
					if(src.parser is parser)
						src.parser = null;

			if(auto mod = cast(ast.Module) n)
				synchronized(mSemanticProject)
					mSemanticProject.addSource(fname, mod, parser.errors);
		}
		version(DebugServer) dbglog("  scheduleParse: " ~ firstLine(text));
		schedule(&doParse);
		return S_OK;
	}

	override HRESULT GetTip(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex, int flags)
	{
		string fname = to_string(filename);
		ast.Module mod;
		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				mod = src.analyzed;

		if(!mod)
			return S_FALSE;

		void _getTip()
		{
			string txt;
			fnSemanticWriteError = &semanticWriteError;
			try
			{
				TextSpan span = TextSpan(TextPos(startIndex, startLine), TextPos(endIndex, endLine));
				ast.Node n = ast.getTextPosNode(mod, &span, null);
				if(n && n !is mod)
				{
					ast.Type t = n.calcType();
					if(!cast(ast.ErrorType) t)
					{
						ast.DCodeWriter writer = new ast.DCodeWriter(ast.getStringSink(txt));
						writer.writeImplementations = false;
						writer.writeClassImplementations = false;
						writer(n, "\ntype: ", t);

						if(cast(ast.EnumDeclaration) t) // version(none)
							if(!cast(ast.Statement) n && !cast(ast.Type) n)
							{
								Value v = n.interpret(globalContext);
								if(!cast(ErrorValue) v && !cast(TypeValue) v)
									txt ~= "\nvalue: " ~ v.toStr();
							}
						mTipSpan = n.fulspan;
					}
					if(auto res = n.resolve())
					{
						string fname = res.getModuleFilename();
						if(auto mod = res.getModule())
							fname = mod.getModuleName();
						if(fname.length)
							txt ~= "\ndecl: " ~ fname ~ "(" ~ to!string(res.span.start.line) ~ ")";
					}
				}
			}
			catch(Throwable t)
			{
				version(DebugServer) dbglog("GetTip._getTip: exception " ~ t.msg);
				logInfo(t.msg);
			}
			mLastTip = txt;
			mSemanticTipRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetTip: " ~ fname);
		mSemanticTipRunning = true;
		schedule(&_getTip);
		return S_OK;
	}

	override HRESULT GetTipResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer)
	{
		if(mSemanticTipRunning)
			return S_FALSE;

		version(DebugServer) dbglog("GetTipResult: " ~ mLastTip);
		writeReadyMessage();
		startLine  = mTipSpan.start.line;
		startIndex = mTipSpan.start.index;
		endLine    = mTipSpan.end.line;
		endIndex   = mTipSpan.end.index;
		*answer = allocBSTR(mLastTip);
		return S_OK;
	}

	override HRESULT GetDefinition(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		string fname = to_string(filename);
		ast.Module mod;
		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				mod = src.analyzed;

		if(!mod)
			return S_FALSE;

		void _getDefinition()
		{
			string txt;
			fnSemanticWriteError = &semanticWriteError;
			string deffilename;
			try
			{
				TextSpan span = TextSpan(TextPos(startIndex, startLine), TextPos(endIndex, endLine));
				ast.Node n = ast.getTextPosNode(mod, &span, null);
				if(n && n !is mod)
				{
					if(auto res = n.resolve())
					{
						deffilename = res.getModuleFilename();
						mDefSpan = res.span;
					}
				}
			}
			catch(Throwable t)
			{
				version(DebugServer) dbglog("GetDefinition._getDefinition: exception " ~ t.msg);
				logInfo(t.msg);
			}
			mLastDefFile = deffilename;
			mSemanticDefinitionRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetDefinition: " ~ fname);
		mSemanticDefinitionRunning = true;
		schedule(&_getDefinition);
		return S_OK;
	}

	override HRESULT GetDefinitionResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer)
	{
		if(mSemanticDefinitionRunning)
			return S_FALSE;

		version(DebugServer) dbglog("GetDefinitionResult: " ~ mLastDefFile);
		writeReadyMessage();
		startLine  = mDefSpan.start.line;
		startIndex = mDefSpan.start.index;
		endLine    = mDefSpan.end.line;
		endIndex   = mDefSpan.end.index;
		*answer = allocBSTR(mLastDefFile);
		return S_OK;
	}

	string[] _GetSemanticExpansions(SourceModule src, string tok, uint line, uint idx, string expr)
	{
		ast.Module mod = src.analyzed;
		if(!mod)
			return null;

		mSemanticProject.initScope();

		bool inDotExpr;
		vdc.util.TextSpan span;
		span.start.line = line;
		span.start.index = idx;
		span.end = span.start;

		ast.Node n = ast.getTextPosNode(mod, &span, &inDotExpr);
		if(!n)
			return null;

		ast.Type t;
		if(auto r = cast(ast.ParseRecoverNode)n)
		{
			if(expr.length)
			{
				Parser parser = new Parser;
				parser.saveErrors = true;
				ast.Node inserted = parser.parseExpression(expr, r.fulspan);
				if(!inserted)
					return null;
				r.addMember(inserted);
				t = inserted.calcType();
				r.removeMember(inserted);
				inDotExpr = true;
			}
		}
		else
			t = n.calcType();

		vdc.semantic.Scope sc;
		if(t)
			sc = t.getScope();
		if(!sc)
			sc = n.getScope();
		if(!sc)
			return null;
		auto syms = sc.search(tok ~ "*", !inDotExpr, true, true);

		Set!string symbols;

		foreach(s, b; syms)
			if(auto decl = cast(ast.Declarator) s)
				symbols.addunique(decl.ident);
			else if(auto em = cast(ast.EnumMember) s)
				symbols.addunique(em.ident);
			else if(auto aggr = cast(ast.Aggregate) s)
				symbols.addunique(aggr.ident);
			else if(auto builtin = cast(ast.BuiltinPropertyBase) s)
				symbols.addunique(builtin.ident);

		return symbols.keys();
	}

	override HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr)
	{
		string[] symbols;
		string fname = to_string(filename);
		auto src = mSemanticProject.getModuleByFilename(fname);
		if(!src)
			return S_FALSE;

		string stok = to_string(tok);
		string sexpr = to_string(expr);
		void calcExpansions()
		{
			fnSemanticWriteError = &semanticWriteError;
			try
			{
				mLastSymbols = _GetSemanticExpansions(src, stok, line, idx, sexpr);
			}
			catch(Throwable t)
			{
				version(DebugServer) dbglog("GetSemanticExpansions.calcExpansions: exception " ~ t.msg);
				logInfo(t.msg);
			}
			mSemanticExpansionsRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetSemanticExpansions: " ~ fname);
		mLastSymbols = null;
		mSemanticExpansionsRunning = true;
		schedule(&calcExpansions);
		return S_OK;
	}

	override HRESULT GetSemanticExpansionsResult(BSTR* stringList)
	{
		if(mSemanticExpansionsRunning)
			return S_FALSE;

		Appender!string slist;
		foreach(sym; mLastSymbols)
		{
			slist.put(sym);
			slist.put('\n');
		}
		*stringList = allocBSTR(slist.data);

		version(DebugServer) dbglog("GetSemanticExpansionsResult: " ~ slist.data);
		writeReadyMessage();
		return S_OK;
	}

	override HRESULT IsBinaryOperator(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp)
	{
		if(!pIsOp)
			return E_POINTER;
		string fname = to_string(filename);

		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				if(src.parsed)
				{
					*pIsOp = ast.isBinaryOperator(src.parsed, startLine, startIndex, endLine, endIndex);
					return S_OK;
				}
		return S_FALSE;
	}

	override HRESULT GetParseErrors(in BSTR filename, BSTR* errors)
	{
		string fname = to_string(filename);

		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				if(src.parsed && !src.parsing)
				{
					string err;
					foreach(e; src.parseErrors)
						err ~= format("%d,%d,%d,%d:%s\n", e.span.start.line, e.span.start.index, e.span.end.line, e.span.end.index, e.msg);

					version(DebugServer)
						dbglog("GetParseErrors: " ~ err);

					*errors = allocBSTR(err);
					return S_OK;
				}
		return S_FALSE;
	}

	override HRESULT GetIdentifierTypes(in BSTR filename, int startLine, int endLine, int flags)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetIdentifierTypesResult(BSTR* errors)
	{
		return E_NOTIMPL;
	}

	override HRESULT ConfigureCommentTasks(in BSTR tasks)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetCommentTasks(in BSTR filename, BSTR* tasks)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetBinaryIsInLocations(in BSTR filename, VARIANT* locs)
	{
		// array of pairs of DWORD
		int[] locData;
		string fname = to_string(filename);

		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				if(auto mod = src.parsed)
				{
					mod.visit(delegate bool (ast.Node n) {
						if(n.id == TOK_in || n.id == TOK_is)
							if(cast(ast.BinaryExpression) n)
							{
								locData ~= n.span.start.line;
								locData ~= n.span.start.index;
							}
						return true;
					});
				}

		SAFEARRAY *sa = SafeArrayCreateVector(VT_INT, 0, cast(ULONG) locData.length);
		if(!sa)
			return E_OUTOFMEMORY;

		for(LONG index = 0; index < locData.length; index++)
			SafeArrayPutElement(sa, &index, &locData[index]);

		locs.vt = VT_ARRAY;
		locs.parray = sa;
		return S_OK;
	}

	override HRESULT GetLastMessage(BSTR* message)
	{
		if(!mLastMessage.length)
		{
			if(mNextReadyMessage > Clock.currTime())
				return S_FALSE;

			mLastMessage = "Ready";
			mNextReadyMessage = Clock.currTime().add!"years"(1);
		}
		*message = allocBSTR(mLastMessage);
		mLastMessage = null;
		return S_OK;
	}

	override HRESULT GetReferences(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr, in BOOL moduleOnly)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetReferencesResult(BSTR* stringList)
	{
		return E_NOTIMPL;
	}

	///////////////////////////////////////////////////////////////
	// create our own task pool to be able to destroy it (it keeps a the
	//  arguments to the last task, so they are never collected)
	__gshared TaskPool parseTaskPool;

	void runTask(T)(T dg)
	{
		if(!parseTaskPool)
		{
			int threads = defaultPoolThreads;
			if(threads < 1)
				threads = 1;
			parseTaskPool = new TaskPool(threads);
			parseTaskPool.isDaemon = true;
			parseTaskPool.priority(core.thread.Thread.PRIORITY_MIN);
		}
		auto task = task(dg);
		parseTaskPool.put(task);
	}

	extern(D) void semanticWriteError(vdc.semantic.MessageType type, string msg)
	{
		if(type == MessageType.Message)
		{
			mLastMessage = msg;
			mHadMessage = true;
		}
		else
			mLastError = msg;
	}

	void writeReadyMessage()
	{
		if(mHadMessage)
		{
			mNextReadyMessage = Clock.currTime() + dur!"seconds"(2);
			mHadMessage = false;
		}
	}

private:
	version(SingleThread) Tid mTid;

	vdc.semantic.Project mSemanticProject;
	bool mSemanticExpansionsRunning;
	bool mSemanticTipRunning;
	bool mSemanticDefinitionRunning;
	string mLastTip;
	TextSpan mTipSpan;
	string mLastDefFile;
	TextSpan mDefSpan;
	string[] mLastSymbols;
	string mLastMessage;
	string mLastError;
	bool mHadMessage;
	SysTime mNextReadyMessage;
}

