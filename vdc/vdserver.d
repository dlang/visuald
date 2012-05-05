// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.vdserver;

import vdc.ivdserver;
import vdc.semantic;
import vdc.logger;
import vdc.util;
import vdc.parser.engine;
import ast = vdc.ast.all;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import stdext.com;
import stdext.string;

//import std.stdio;
import std.parallelism;
import std.string;

///////////////////////////////////////////////////////////////

// server object: 002a2de9-8bb6-484d-9901-7e4ad4084715
// class factory: 002a2de9-8bb6-484d-9902-7e4ad4084715
// type library : 002a2de9-8bb6-484d-9903-7e4ad4084715

///////////////////////////////////////////////////////////////

static this()
{
	CoInitialize(null);
}

static ~this()
{
	CoUninitialize();
}

///////////////////////////////////////////////////////////////

class VDServer : ComObject, IVDServer
{
	this()
	{
		mSemanticProject = new vdc.semantic.Project;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
//		MessageBoxW(null, "Object1.QueryInterface"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
		if(queryInterface!(IVDServer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT ExecCommand(in BSTR cmd, BSTR* answer)
	{
		*answer = SysAllocString("Answer"w.ptr);
		return S_OK;
	}

	override HRESULT ExecCommandAsync(in BSTR cmd, ULONG* cmdID)
	{
		return E_NOTIMPL;
	}

	override HRESULT ConfigureSemanticProject(in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags)
	{
		synchronized(mSemanticProject)
		{
			auto opts = mSemanticProject.options;

			string imports = to_string(imp);
			string strImports = to_string(stringImp);

			opts.unittestOn = (flags & 1) != 0;
			opts.debugOn    = (flags & 2) != 0;
			opts.x64        = (flags & 4) != 0;
			int versionlevel = (flags >> 8)  & 0xff;
			int debuglevel   = (flags >> 16) & 0xff;

			string verids = to_string(versionids);
			string dbgids = to_string(debugids);

			opts.setVersionIds(versionlevel, tokenizeArgs(verids)); 
			opts.setDebugIds(debuglevel, tokenizeArgs(dbgids)); 
		}
		return S_OK;
	}

	override HRESULT ClearSemanticProject()
	{
		synchronized(mSemanticProject)
			mSemanticProject.disconnectAll();
		
		mSemanticProject = new vdc.semantic.Project;
		return S_OK;
	}

	override HRESULT UpdateModule(in BSTR filename, in BSTR srcText)
	{
		string fname = to_string(filename);
		string text  = to_string(srcText);
		
		void doParse()
		{
			auto parser = new Parser;
			parser.saveErrors = true;

			synchronized(mSemanticProject)
				if(auto src = mSemanticProject.getModuleByFilename(fname))
					src.parsing = true;

			ast.Node n;
			try
			{
				n = parser.parseModule(text);
			}
			catch(ParseException e)
			{
				logInfo(e.msg);
			}
			catch(Throwable t)
			{
				logInfo(t.msg);
			}

			if(auto mod = cast(ast.Module) n)
				synchronized(mSemanticProject)
					mSemanticProject.addSource(fname, mod, parser.errors);
		}
		runTask(&doParse);
		return S_OK;
	}
	override HRESULT GetType(in BSTR filename, ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer)
	{
		string txt;
		try
		{
			string fname = to_string(filename);
			auto src = mSemanticProject.getModuleByFilename(fname);
			if(!src)
				return S_FALSE;

			ast.Module mod = src.analyzed;
			if(!mod)
				return S_FALSE;

			TextSpan span = TextSpan(TextPos(startIndex, startLine), TextPos(endIndex, endLine));
			ast.Node n = ast.getTextPosNode(mod, &span, null);
			if(n && n !is mod)
			{
				ast.Type t = n.calcType();
				if(!cast(ast.ErrorType) t)
				{
					vdc.util.DCodeWriter writer = new vdc.util.DCodeWriter(vdc.util.getStringSink(txt));
					writer.writeImplementations = false;
					writer.writeClassImplementations = false;
					writer(n, "\ntype: ", t);

					version(none)
						if(!cast(ast.Statement) n && !cast(ast.Type) n)
						{
							Value v = n.interpret(globalContext);
							if(!cast(ErrorValue) v && !cast(TypeValue) v)
								txt ~= "\nvalue: " ~ v.toStr();
						}
					startLine  = span.start.line;
					startIndex = span.start.index;
					endLine    = span.end.line;
					endIndex   = span.end.index;
				}
			}
		}
		catch(Error e)
		{
			txt = e.msg;
		}
		*answer = allocBSTR(txt);
		return S_OK;
	}

	override HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, BSTR* stringList)
	{
		return E_NOTIMPL;
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
					*pIsOp = vdc.ast.node.isBinaryOperator(src.parsed, startLine, startIndex, endLine, endIndex);
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
					*errors = allocBSTR(err);
					return S_OK;
				}
		return S_FALSE;
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

private:
	vdc.semantic.Project mSemanticProject;
}

///////////////////////////////////////////////////////////////

class VDServerClassFactory : ComObject, IClassFactory
{
	static GUID iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IClassFactory) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		if(*riid == IVDServer.iid)
		{
			//MessageBoxW(null, "CreateInstance IVDServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			assert(!UnkOuter);
			VDServer srv = new VDServer;
			return srv.QueryInterface(riid, pvObject);
		}
		return E_NOINTERFACE;
	}
	override HRESULT LockServer(in BOOL fLock)
	{
		if(fLock)
		{
			//MessageBoxW(null, "LockServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			lockCount++;
		}
		else
		{
			//MessageBoxW(null, "UnlockServer"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
			lockCount--;
		}
		if(lockCount == 0)
			PostQuitMessage(0);
		return S_OK;
	}

	int lockCount;
}

///////////////////////////////////////////////////////////////

int main(string[] argv)
{
	HRESULT hr;

	// Create the MyCar class object.
	VDServerClassFactory cf = new VDServerClassFactory;

	// Register the Factory.
	DWORD regID = 0;
	hr = CoRegisterClassObject(VDServerClassFactory.iid, cf, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &regID);
	if(FAILED(hr))
	{
		ShowErrorMessage("CoRegisterClassObject()", hr);
		return 1;
	}

	//MessageBoxW(null, "comserverd registered"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);

	// Now just run until a quit message is sent,
	// in responce to the final release.
	MSG ms;
	while(GetMessage(&ms, null, 0, 0))
	{
		TranslateMessage(&ms);
		DispatchMessage(&ms);
	}

	// All done, so remove class object.
	CoRevokeClassObject(regID);	
	return 0;
}

int MAKELANGID(int p, int s) { return ((cast(WORD)s) << 10) | cast(WORD)p; }

void ShowErrorMessage(LPCTSTR header, HRESULT hr)
{
	wchar* pMsg;

	FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,null,hr,
		           MAKELANGID(LANG_NEUTRAL,SUBLANG_DEFAULT),cast(LPTSTR)&pMsg,0,null);

	MessageBoxW(null, pMsg, "[LOCAL] error", MB_OK|MB_SETFOREGROUND);

	LocalFree(pMsg);
}

