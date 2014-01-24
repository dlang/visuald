// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.vdserverclient;

import visuald.pkgutil;
import visuald.logutil;

import vdc.ivdserver;
//import vdc.semantic;
import vdc.util;

import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.vsi.sdk_shared;

import sdk.port.base;

import stdext.com;
import stdext.container;
import stdext.string;

import std.concurrency;
import std.string;
import std.conv;
import std.path;
import std.windows.charset;
import core.thread;

alias object.AssociativeArray!(string, std.concurrency.Tid) _wa1; // fully instantiate type info for string[Tid]
alias object.AssociativeArray!(std.concurrency.Tid, string[]) _wa2; // fully instantiate type info for string[Tid]

version(TESTMAIN) version = InProc;
debug version = DebugCmd;
// debug version = InProc;

version(InProc) import vdc.vdserver;

///////////////////////////////////////////////////////////////////////
version(DebugCmd)
{
import std.datetime;
import core.stdc.stdio : fprintf, fopen, fflush, fputc, FILE;
__gshared FILE* dbgfh;

private void dbglog(string s) 
{
	debug
	{
		version(all) 
			logCall("VDClient: ", s);
		else
			OutputDebugStringA(toMBSz("VDClient: " ~ s ~ "\n"));
	}
	else
	{
		if(!dbgfh) 
			dbgfh = fopen("c:/tmp/vdclient.log", "w");
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

///////////////////////////////////////////////////////////////////////
// can be changed through registry entry
debug(debugServer)
const GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9A02-7e4ad4084715");
else
const GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");
const GUID DParserClassFactory_iid  = uuid("002a2de9-8bb6-484d-AA05-7e4ad4084715"); // needs VDServer, not factory

__gshared GUID gServerClassFactory_iid = VDServerClassFactory_iid;
__gshared GUID IVDServer_iid = IVDServer.iid;

__gshared IClassFactory gVDClassFactory;
__gshared IVDServer gVDServer;

bool startVDServer()
{
	if(gVDServer)
		return false;

	CoInitialize(null);

	version(InProc) 
		gVDServer = addref(newCom!VDServer);
	else
	{
		GUID factory_iid = IID_IClassFactory;
		HRESULT hr = CoGetClassObject(gServerClassFactory_iid, CLSCTX_LOCAL_SERVER|CLSCTX_INPROC_SERVER, null, factory_iid, cast(void**)&gVDClassFactory);
		if(FAILED(hr))
			return false;

		hr = gVDClassFactory.CreateInstance(null, &IVDServer_iid, cast(void**)&gVDServer);
		if (FAILED(hr))
		{
			gVDClassFactory = release(gVDClassFactory);
			return false;
		}
	}
	version(DebugCmd) dbglog ("VDServer startet successfully");
	return true;
}

bool stopVDServer()
{
	if(!gVDServer)
		return false;

	version(DebugCmd) dbglog ("stopping VDServer");
	gVDServer = release(gVDServer);
	gVDClassFactory = release(gVDClassFactory);

	CoUninitialize();
	return true;
}

///////////////////////////////////////////////////////////////////////
struct FileCacheData
{
	TextPos[] binaryIsIn;

	int mParseRequestCount;
	int mParseDoneCount;
}

class ServerCache
{
	FileCacheData[string] mCache;
}

///////////////////////////////////////////////////////////////////////
template _shared(T)
{
	alias T _shared;
	// alias shared(T) _shared;
}

/*shared*/ class Command
{
	this(string cmd)
	{
		mCommand = cmd;
		mRequest = sLastRequest++;
	}

	// called from clientLoop (might block due to server garbage collecting)
	HRESULT exec() const
	{
		assert(false);
	}
	// polled from clientLoop (might block due to server garbage collecting)
	HRESULT answer()
	{
		return S_OK;
	}
	// called from onIdle
	bool forward()
	{
		return true;
	}

	void send(Tid id)
	{
//		.send(id, cast(size_t) cast(void*) this);
		.send(id, cast(shared)this);
//		.send(id, this);
	}

	static uint sLastRequest;

	uint mRequest;
	string mCommand;
}

class ExitCommand : Command
{
	this()
	{
		super("exit");
	}

	override HRESULT exec() const
	{
		stopVDServer();
		return S_OK;
	}
}

class ClearProjectCommand : Command
{
	this()
	{
		super("ClearProject");
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;
		return gVDServer.ClearSemanticProject();
	}
}

class FileCommand : Command
{
	this(string cmd, string filename)
	{
		version(DebugCmd) cmd ~= ":" ~ baseName(filename);
		super(cmd);
		mFilename = filename;
	}

	string mFilename;
}

//////////////////////////////////////

class ConfigureProjectCommand : FileCommand
{
	this(string filename, immutable(string[]) imp, immutable(string[]) stringImp, 
		 immutable(string[]) versionids, immutable(string[]) debugids, uint flags)
	{
		super("ConfigureProject", filename);
		mImp = imp;
		mStringImp = stringImp;
		mVersionids = versionids;
		mDebugids = debugids;
		mFlags = flags;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		string jimp        = std.string.join(cast(string[])(mImp[]), "\n");
		string jstringImp  = std.string.join(cast(string[])(mStringImp[]), "\n");
		string jversionids = std.string.join(cast(string[])(mVersionids[]), "\n");
		string jdebugids   = std.string.join(cast(string[])(mDebugids[]), "\n");

		auto bfilename = allocBSTR(mFilename);
		auto bimp = allocBSTR(jimp);
		auto bstringImp = allocBSTR(jstringImp);
		auto bversionids = allocBSTR(jversionids);
		auto bdebugids = allocBSTR(jdebugids);

		HRESULT hr = gVDServer.ConfigureSemanticProject(bfilename, bimp, bstringImp, bversionids, bdebugids, mFlags);

		freeBSTR(bfilename);
		freeBSTR(bimp);
		freeBSTR(bstringImp);
		freeBSTR(bversionids);
		freeBSTR(bdebugids);
		
		return hr;
	}

	immutable(string[]) mImp;
	immutable(string[]) mStringImp;
	immutable(string[]) mVersionids;
	immutable(string[]) mDebugids;
	uint mFlags;
}

//////////////////////////////////////

alias void delegate(uint request, string fname, string type, sdk.vsi.sdk_shared.TextSpan span) GetTipCallBack;

class GetTipCommand : FileCommand
{
	this(string filename, sdk.vsi.sdk_shared.TextSpan span, GetTipCallBack cb)
	{
		super("GetTip", filename);
		version(DebugCmd) mCommand ~= " {" ~ to!string(span.iStartLine) ~ "," ~ to!string(span.iStartIndex) 
			~ " - " ~ to!string(span.iEndLine) ~ "," ~ to!string(span.iEndIndex) ~ "}";
		mSpan = span;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		int iStartLine = mSpan.iStartLine + 1;
		int iStartIndex = mSpan.iStartIndex;
		int iEndLine = mSpan.iEndLine + 1;
		int iEndIndex = mSpan.iEndIndex;
		HRESULT rc = gVDServer.GetTip(fname, iStartLine, iStartIndex, iEndLine, iEndIndex);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR btype;
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		HRESULT rc = gVDServer.GetTipResult(iStartLine, iStartIndex, iEndLine, iEndIndex, &btype);
		if(rc != S_OK)
			return rc;

		mType = detachBSTR(btype);
		mSpan = sdk.vsi.sdk_shared.TextSpan(iStartIndex, iStartLine - 1, iEndIndex, iEndLine - 1);

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mFilename, mType, mSpan);
		return true;
	}

	GetTipCallBack mCallback;
	sdk.vsi.sdk_shared.TextSpan mSpan;
	string mType;
}

//////////////////////////////////////

alias void delegate(uint request, string fname, sdk.vsi.sdk_shared.TextSpan span) GetDefinitionCallBack;

class GetDefinitionCommand : FileCommand
{
	this(string filename, sdk.vsi.sdk_shared.TextSpan span, GetDefinitionCallBack cb)
	{
		super("GetDefinition", filename);
		version(DebugCmd) mCommand ~= " {" ~ to!string(span.iStartLine) ~ "," ~ to!string(span.iStartIndex) 
			~ " - " ~ to!string(span.iEndLine) ~ "," ~ to!string(span.iEndIndex) ~ "}";
		mSpan = span;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		int iStartLine = mSpan.iStartLine + 1;
		int iStartIndex = mSpan.iStartIndex;
		int iEndLine = mSpan.iEndLine + 1;
		int iEndIndex = mSpan.iEndIndex;
		HRESULT rc = gVDServer.GetDefinition(fname, iStartLine, iStartIndex, iEndLine, iEndIndex);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname;
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		HRESULT rc = gVDServer.GetDefinitionResult(iStartLine, iStartIndex, iEndLine, iEndIndex, &fname);
		if(rc != S_OK)
			return rc;

		mDefFile = detachBSTR(fname);
		mSpan = sdk.vsi.sdk_shared.TextSpan(iStartIndex, iStartLine - 1, iEndIndex, iEndLine - 1);

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mDefFile, mSpan);
		return true;
	}

	GetDefinitionCallBack mCallback;
	sdk.vsi.sdk_shared.TextSpan mSpan;
	string mDefFile;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string parseErrors, TextPos[] binaryIsIn) UpdateModuleCallBack;

class UpdateModuleCommand : FileCommand
{
	this(string filename, wstring text, bool verbose, UpdateModuleCallBack cb)
	{
		super("UpdateModule", filename);
		version(DebugCmd) mCommand ~= " " ~ to!string(firstLine(text));
		mText = text;
		mCallback = cb;
		mVerbose = verbose;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR bfname = allocBSTR(mFilename);

		BSTR btxt = allocwBSTR(mText);
		HRESULT hr = gVDServer.UpdateModule(bfname, btxt, mVerbose);
		freeBSTR(btxt);
		freeBSTR(bfname);
		return hr;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		scope(exit) freeBSTR(fname);
		BSTR errors;
		if(auto hr = gVDServer.GetParseErrors(fname, &errors))
			return hr;

		mErrors = detachBSTR(errors);

		VARIANT locs;
		if(gVDServer.GetBinaryIsInLocations(fname, &locs) == S_OK && locs.vt == VT_ARRAY)
		{
			SAFEARRAY* sa = locs.parray;
			assert(SafeArrayGetDim(sa) == 1);
			LONG lbound, ubound;
			SafeArrayGetLBound(sa, 1, &lbound);
			SafeArrayGetUBound(sa, 1, &ubound);
			
			size_t cnt = (ubound - lbound + 1) / 2;
			mBinaryIsIn.length = cnt;
			for(size_t i = 0; i < cnt; i++)
			{
				LONG index = lbound + 2 * i;
				int line, col;
				SafeArrayGetElement(sa, &index, &line);
				mBinaryIsIn[i].line = line;
				index++;
				SafeArrayGetElement(sa, &index, &col);
				mBinaryIsIn[i].index = col;
			}
			SafeArrayDestroy(sa);
		}

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd)
			dbglog(to!string(mRequest) ~ " forward:  " ~ mCommand ~ " " ~ ": " ~ mErrors);
		if(mCallback)
			mCallback(mRequest, mFilename, mErrors, cast(TextPos[])mBinaryIsIn);
		return true;
	}

	UpdateModuleCallBack mCallback;
	wstring mText;
	string mErrors;
	bool mVerbose;
	TextPos[] mBinaryIsIn;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string tok, int line, int idx, string[] exps) GetExpansionsCallBack;

class GetExpansionsCommand : FileCommand
{
	this(string filename, string tok, int line, int idx, wstring expr, GetExpansionsCallBack cb)
	{
		super("GetExpansions", filename);
		mTok = tok;
		mLine = line;
		mIndex = idx;
		mExpr = expr;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		BSTR tok = allocBSTR(mTok);
		BSTR expr = allocwBSTR(mExpr);
		HRESULT rc = gVDServer.GetSemanticExpansions(fname, tok, mLine + 1, mIndex, expr);
		freeBSTR(expr);
		freeBSTR(tok);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		BSTR stringList;
		HRESULT rc = gVDServer.GetSemanticExpansionsResult(&stringList);
		if(rc != S_OK)
			return rc;

		string slist = detachBSTR(stringList);
		mExpansions = /*cast(shared(string[]))*/ splitLines(slist);
		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mFilename, mTok, mLine, mIndex, cast(string[])mExpansions);
		return true;
	}

	GetExpansionsCallBack mCallback;
	string mTok;
	wstring mExpr;
	int mLine;
	int mIndex;
	string[] mExpansions;
}

class GetMessageCommand : Command
{
	this(string message)
	{
		super("GetMessage");
		mMessage = message;
	}

	override bool forward()
	{
		showStatusBarText(mMessage);
		return true;
	}

	string mMessage;
}

///////////////////////////////////////////////////////////////////////
__gshared Tid gUITid;

class VDServerClient
{
	Tid mTid;

	this()
	{
	}
	
	~this()
	{
		shutDown();
	}

	void start()
	{
		gUITid = thisTid();
		mTid = spawn(&clientLoop);
	}

	//////////////////////////////////////
	void shutDown()
	{
		if(gVDServer)
		{
			(new _shared!(ExitCommand)).send(mTid);
			while(gVDServer)
			{
				Thread.sleep(dur!"msecs"(50));  // sleep for 50 milliseconds
			}
		}
	}

	//////////////////////////////////////
	uint ConfigureSemanticProject(string filename, immutable(string[]) imp, immutable(string[]) stringImp, 
								  immutable(string[]) versionids, immutable(string[]) debugids, uint flags)
	{
		auto cmd = new _shared!(ConfigureProjectCommand)(filename, imp, stringImp, versionids, debugids, flags);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint GetTip(string filename, sdk.vsi.sdk_shared.TextSpan* pSpan, GetTipCallBack cb)
	{
		auto cmd = new _shared!(GetTipCommand)(filename, *pSpan, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint GetDefinition(string filename, sdk.vsi.sdk_shared.TextSpan* pSpan, GetDefinitionCallBack cb)
	{
		auto cmd = new _shared!(GetDefinitionCommand)(filename, *pSpan, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	int GetSemanticExpansions(string filename, string tok, int line, int idx, wstring expr, GetExpansionsCallBack cb)
	{
		auto cmd = new _shared!(GetExpansionsCommand)(filename, tok, line, idx, expr, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint UpdateModule(string filename, wstring text, bool verbose, UpdateModuleCallBack cb)
	{
		auto cmd = new _shared!(UpdateModuleCommand)(filename, text, verbose, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}
	uint ClearSemanticProject()
	{
		auto cmd = new _shared!(ClearProjectCommand);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	//////////////////////////////////////
	// obsolete
	bool isBinaryOperator(string filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		return false;
	}
	bool _isBinaryOperator(string filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		if(!gVDServer)
			return false;

		BOOL res;
		BSTR fname = allocBSTR(filename);
		HRESULT rc = gVDServer.IsBinaryOperator(fname, startLine, startIndex, endLine, endIndex, &res);
		freeBSTR(fname);
		return rc == S_OK && res != 0;
	}

	bool GetParseErrors(string filename, ref string err)
	{
		return false;
	}
	bool _GetParseErrors(string filename, ref string err)
	{
		if(!gVDServer)
			return false;

		BSTR fname = allocBSTR(filename);
		scope(exit) freeBSTR(fname);
		BSTR errors;
		if(gVDServer.GetParseErrors(fname, &errors) != S_OK)
			return false;
		err = detachBSTR(errors);
		return true;
	}

	//////////////////////////////////////
	static shared bool restartServer = false;

	static void clientLoop()
	{
		startVDServer();

		try
		{
			Queue!(_shared!(Command)) toAnswer;
			while(gVDServer)
			{
				bool changed = false;
				receiveTimeout(dur!"msecs"(50),
					// as of dmd 2.060, fixes of const handling expose that std.variant is not capable of working sensibly with class objects
					(shared(Command) icmd)
				    //(size_t icmd)
					{
						auto cmd = cast(Command) cast(void*) icmd;
						version(DebugCmd) dbglog(to!string(cmd.mRequest) ~ " clientLp: " ~ cmd.mCommand);
						HRESULT hr = cmd.exec();
						if(hr == S_OK)
							toAnswer ~= cmd;
						else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
							restartServer = true;
						changed = true;
					},
					(Variant var)
					{
						var = var;
					}
				);
				for(int i = 0; i < toAnswer.length && !restartServer; )
				{
					auto cmd = toAnswer[i];
					HRESULT hr = cmd.answer();
					if(hr == S_OK)
					{
						toAnswer.remove(i);
						changed = true;
					}
					else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
						restartServer = true;
					else
						i++;
				}

				BSTR msg;
				if(gVDServer && !restartServer)
				{
					HRESULT hr = gVDServer.GetLastMessage(&msg);
					if(hr == S_OK)
					{
						string m = detachBSTR(msg);
						if(m != "__no_message__")
							(new _shared!(GetMessageCommand)(m)).send(gUITid);
					}
					else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
						restartServer = true;
				}

				version(DebugCmd) if (changed)
				{
					string s = "   answerQ = [";
					for(int i = 0; i < toAnswer.length; i++)
						s ~= (i > 0 ? " " : "") ~ to!string(toAnswer[i].mRequest);
					dbglog(s ~ "]");
				}
				if(restartServer)
				{
					restartServer = false;
					version(DebugCmd) dbglog("*** clientLoop: restarting server ***");
					stopVDServer();
					startVDServer();
				}
			}
		}
		catch(Throwable e)
		{
			version(DebugCmd) dbglog ("clientLoop exception: " ~ e.msg);
		}
		stopVDServer();
	}

	void onIdle()
	{
		try
		{
			while(receiveTimeout(dur!"msecs"(0),
				(shared(Command) icmd)
				//(size_t icmd)
				{
					auto cmd = cast(Command) cast(void*) icmd;
					version(DebugCmd) 
						if(cmd.mCommand != "GetMessage")
							dbglog(to!string(cmd.mRequest) ~ " " ~ "idleLoop: " ~ cmd.mCommand);
					cmd.forward();
				},
				(Variant var)
				{
					var = var;
				}
			))
			{
			}
		}
		catch(Throwable e)
		{
			version(DebugCmd) dbglog ("clientLoop exception: " ~ e.msg);
		}
	}
}
