// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.vdserverclient;

import visuald.pkgutil;

import vdc.ivdserver;
//import vdc.semantic;
import vdc.util;

import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.vsi.sdk_shared;

import sdk.port.base;

import stdext.com;

import std.concurrency;
import std.string;
import std.windows.charset;
import core.thread;

///////////////////////////////////////////////////////////////////////
uint ConfigureFlags()(bool unittestOn, bool debugOn, bool x64, int versionLevel, int debugLevel)
{
	return (unittestOn ? 1 : 0)
		|  (debugOn    ? 2 : 0)
		|  (x64        ? 4 : 0)
		| ((versionLevel & 0xff) << 8)
		| ((debugLevel & 0xff) << 8);
}

///////////////////////////////////////////////////////////////////////
static GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");

__gshared IClassFactory gVDClassFactory;
__gshared IVDServer gVDServer;

bool startVDServer()
{
	if(gVDServer)
		return false;

	CoInitialize(null);

	GUID factory_iid = IID_IClassFactory;
	HRESULT hr = CoGetClassObject(VDServerClassFactory_iid, CLSCTX_LOCAL_SERVER, null, factory_iid, cast(void**)&gVDClassFactory);
	if(FAILED(hr))
		return false;

	hr = gVDClassFactory.CreateInstance(null, &IVDServer.iid, cast(void**)&gVDServer);
	if (FAILED(hr))
	{
		gVDClassFactory = release(gVDClassFactory);
		return false;
	}
	return true;
}

bool stopVDServer()
{
	if(!gVDServer)
		return false;

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

__gshared ServerCache gServerCache;

///////////////////////////////////////////////////////////////////////
class Command
{
	this(string cmd)
	{
		mCommand = cmd;
		mRequest = mLastRequest++;
	}

	// called from clientLoop (might block due to server garbage collecting)
	bool exec()
	{
		assert(false);
	}
	// polled from clientLoop (might block due to server garbage collecting)
	bool answer()
	{
		return true;
	}
	// called from onIdle
	bool forward()
	{
		return true;
	}

	static uint mLastRequest;

	uint mRequest;
	string mCommand;
}

class ExitCommand : Command
{
	this()
	{
		super("exit");
	}

	override bool exec()
	{
		stopVDServer();
		return true;
	}
}

class ClearProjectCommand : Command
{
	this()
	{
		super("ClearProject");
	}

	override bool exec()
	{
		if(!gVDServer)
			return false;
		return gVDServer.ClearSemanticProject() == S_OK;
	}
}

class FileCommand : Command
{
	this(string cmd, string filename)
	{
		super(cmd);
		mFilename = filename;
	}

	string mFilename;
}

//////////////////////////////////////

class ConfigureProjectCommand : Command
{
	this(string[] imp, string[] stringImp, string[] versionids, string[] debugids, uint flags)
	{
		super("ConfigureProject");
		mImp = imp;
		mStringImp = stringImp;
		mVersionids = versionids;
		mDebugids = debugids;
		mFlags = flags;
	}

	override bool exec()
	{
		if(!gVDServer)
			return false;

		string jimp = join(mImp, "\n");
		string jstringImp = join(mStringImp, "\n");
		string jversionids = join(mVersionids, "\n");
		string jdebugids = join(mDebugids, "\n");

		auto bimp = allocBSTR(jimp);
		auto bstringImp = allocBSTR(jstringImp);
		auto bversionids = allocBSTR(jversionids);
		auto bdebugids = allocBSTR(jdebugids);

		HRESULT hr = gVDServer.ConfigureSemanticProject(bimp, bstringImp, bversionids, bdebugids, mFlags);
		return hr == S_OK;
	}

	string[] mImp;
	string[] mStringImp;
	string[] mVersionids;
	string[] mDebugids;
	uint mFlags;
}

//////////////////////////////////////

alias void delegate(uint request, string fname, string type, sdk.vsi.sdk_shared.TextSpan span) GetTypeCallBack;

class GetTypeCommand : FileCommand
{
	this(string filename, sdk.vsi.sdk_shared.TextSpan span, GetTypeCallBack cb)
	{
		super("GetType", filename);
		mSpan = span;
		mCallback = cb;
	}

	override bool exec()
	{
		if(!gVDServer)
			return false;

		BSTR fname = allocBSTR(mFilename);
		BSTR btype;
		int iStartLine = mSpan.iStartLine + 1;
		int iStartIndex = mSpan.iStartIndex;
		int iEndLine = mSpan.iEndLine + 1;
		int iEndIndex = mSpan.iEndIndex;
		HRESULT rc = gVDServer.GetType(fname, iStartLine, iStartIndex, iEndLine, iEndIndex, &btype);
		freeBSTR(fname);

		mType = detachBSTR(btype);
		mSpan = sdk.vsi.sdk_shared.TextSpan(iStartIndex, iStartLine - 1, iEndIndex, iEndLine - 1);
		return rc == S_OK;
	}

	override bool answer()
	{
		send(gUITid, cast(immutable)this);
		return true;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mFilename, mType, mSpan);
		return true;
	}

	GetTypeCallBack mCallback;
	sdk.vsi.sdk_shared.TextSpan mSpan;
	string mType;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string parseErrors, TextPos[] binaryIsIn) UpdateModuleCallBack;

class UpdateModuleCommand : FileCommand
{
	this(string filename, wstring text, UpdateModuleCallBack cb)
	{
		super("UpdateModule", filename);
		mText = text;
		mCallback = cb;
	}

	override bool exec()
	{
		if(!gVDServer)
			return false;

		BSTR bfname = allocBSTR(mFilename);

		BSTR btxt = allocwBSTR(mText);
		gVDServer.UpdateModule(bfname, btxt);
		freeBSTR(btxt);
		freeBSTR(bfname);
		return true;
	}

	override bool answer()
	{
		if(!gVDServer)
			return false;

		BSTR fname = allocBSTR(mFilename);
		scope(exit) freeBSTR(fname);
		BSTR errors;
		if(gVDServer.GetParseErrors(fname, &errors) != S_OK)
			return false;

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
				SafeArrayGetElement(sa, &index, &mBinaryIsIn[i].line);
				index++;
				SafeArrayGetElement(sa, &index, &mBinaryIsIn[i].index);
			}
			SafeArrayDestroy(sa);
		}

		send(gUITid, cast(immutable)this);
		return true;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mFilename, mErrors, mBinaryIsIn);
		return true;
	}

	UpdateModuleCallBack mCallback;
	wstring mText;
	string mErrors;
	TextPos[] mBinaryIsIn;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string tok, int line, int idx, string[] exps) GetExpansionsCallBack;

class GetExpansionsCommand : FileCommand
{
	this(string filename, string tok, int line, int idx, GetExpansionsCallBack cb)
	{
		super("GetType", filename);
		mTok = tok;
		mLine = line;
		mIndex = idx;
		mCallback = cb;
	}

	override bool exec()
	{
		if(!gVDServer)
			return false;

		BSTR fname = allocBSTR(mFilename);
		BSTR tok = allocBSTR(mTok);
		HRESULT rc = gVDServer.GetSemanticExpansions(fname, tok, mLine + 1, mIndex);
		freeBSTR(tok);
		freeBSTR(fname);
		return rc == S_OK;
	}

	override bool answer()
	{
		BSTR stringList;
		HRESULT rc = gVDServer.GetSemanticExpansionsResult(&stringList);
		if(rc != S_OK)
			return false;

		string slist = detachBSTR(stringList);
		mExpansions = splitLines(slist);
		send(gUITid, cast(immutable)this);
		return true;
	}

	override bool forward()
	{
		if(mCallback)
			mCallback(mRequest, mFilename, mTok, mLine, mIndex, mExpansions);
		return true;
	}

	GetExpansionsCallBack mCallback;
	string mTok;
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
		gServerCache = new ServerCache;
		gUITid = thisTid();
		mTid = spawn(&clientLoop);
	}
	
	~this()
	{
		shutDown();
	}

	//////////////////////////////////////
	void shutDown()
	{
		if(gVDServer)
		{
			send(mTid, new immutable(ExitCommand));
			while(gVDServer)
			{
				Thread.sleep(dur!"msecs"(50));  // sleep for 50 milliseconds
			}
		}
	}

	//////////////////////////////////////
	uint ConfigureSemanticProject(string[] imp, string[] stringImp, string[] versionids, string[] debugids, uint flags)
	{
		auto cmd = new immutable(ConfigureProjectCommand)(imp, stringImp, versionids, debugids, flags);
		send(mTid, cmd);
		return cmd.mRequest;
	}

	uint GetType(string filename, sdk.vsi.sdk_shared.TextSpan* pSpan, GetTypeCallBack cb)
	{
		auto cmd = new immutable(GetTypeCommand)(filename, *pSpan, cb);
		send(mTid, cmd);
		return cmd.mRequest;
	}

	int GetSemanticExpansions(string filename, string tok, int line, int idx, GetExpansionsCallBack cb)
	{
		auto cmd = new immutable(GetExpansionsCommand)(filename, tok, line, idx, cb);
		send(mTid, cmd);
		return cmd.mRequest;
	}

	uint UpdateModule(string filename, wstring text, UpdateModuleCallBack cb)
	{
		auto cmd = new immutable(UpdateModuleCommand)(filename, text, cb);
		send(mTid, cmd);
		return cmd.mRequest;
	}
	uint ClearSemanticProject()
	{
		auto cmd = new immutable(ClearProjectCommand);
		send(mTid, cmd);
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
	static void clientLoop()
	{
		startVDServer();

		try
		{
			Command[] toAnswer;
			while(gVDServer)
			{
				receiveTimeout(dur!"msecs"(50),
					(Command cmd)
					{
						OutputDebugStringA(toMBSz("clientLoop: " ~ cmd.mCommand ~ "\n"));
						if(cmd.exec())
							toAnswer ~= cmd;
					},
					(Variant var)
					{
						var = var;
					}
				);
				for(int i = 0; i < toAnswer.length; )
				{
					auto cmd = toAnswer[i];
					if(toAnswer[i].answer())
						toAnswer = toAnswer[0..i] ~ toAnswer[i+1..$];
					else
						i++;
				}

				BSTR msg;
				if(gVDServer && gVDServer.GetLastMessage(&msg) == S_OK)
					send(gUITid, new immutable(GetMessageCommand)(detachBSTR(msg)));
			}
		}
		catch(Throwable)
		{
		}
		stopVDServer();
	}

	void onIdle()
	{
		try
		{
			while(receiveTimeout(dur!"msecs"(0),
				(Command cmd)
				{
					OutputDebugStringA(toMBSz("idleLoop: " ~ cmd.mCommand ~ "\n"));
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
		catch(Throwable)
		{
		}
	}
}
