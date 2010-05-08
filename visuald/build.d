// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module build;

import std.c.windows.windows;
import std.c.windows.com;
import std.c.stdlib;
import std.windows.charset;
import std.utf;
import std.string;
import std.regexp;
import std.file;
import std.path;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;

import comutil;
import chiernode;
import dproject;
import hierutil;
import hierarchy;
import fileutil;
import stringutil;
import config;

// builder thread class
class CBuilderThread // : public CVsThread<CMyProjBuildableCfg>
{
public:
	this()
	{
	}

	~this()
	{
	}

	void Dispose()
	{
		m_pIVsOutputWindowPane = release(m_pIVsOutputWindowPane);
		m_srpIVsLaunchPadFactory = release(m_srpIVsLaunchPadFactory);
		m_pIVsStatusbar = release(m_pIVsStatusbar);
	}

	enum Operation
	{
		eIdle,
		eBuild,
		eRebuild,
		eCheckUpToDate,
		eClean,
	};

	HRESULT Start(Config cfg, Operation op, IVsOutputWindowPane pIVsOutputWindowPane)
	{
		m_op = op;
		mConfig = cfg;

		m_pIVsOutputWindowPane = release(m_pIVsOutputWindowPane);
		m_pIVsOutputWindowPane = addref(pIVsOutputWindowPane);

		// get a pointer to IVsLaunchPadFactory
		if (!m_srpIVsLaunchPadFactory)
		{
			m_srpIVsLaunchPadFactory = queryService!(IVsLaunchPadFactory);
			if (!m_srpIVsLaunchPadFactory)
				return E_FAIL;
		}
		// Note that the QueryService for SID_SVsStatusbar will fail during command line build
		if(!m_pIVsStatusbar)
			m_pIVsStatusbar = queryService!(IVsStatusbar);

		bool rc = ThreadMain();
		m_op = Operation.eIdle;
		//return super::Start(pCMyProjBuildableCfg);
		return rc ? S_OK : S_FALSE;
	}

	void Stop(BOOL fSync)
	{
		m_fStopBuild = TRUE;
	}

	void QueryStatus(BOOL *pfDone)
	{
		if(pfDone)
			*pfDone = (m_op == Operation.eIdle);
	}

	bool ThreadMain()
	{
		BOOL fContinue = TRUE;
		BOOL fSuccessfulBuild = FALSE; // set up for Fire_BuildEnd() later on.

		Fire_BuildBegin(fContinue);

		switch (m_op)
		{
		default:
			assert(false);
			break;

		case Operation.eBuild:
			fSuccessfulBuild = DoBuild();
			break;

		case Operation.eRebuild:
			fSuccessfulBuild = DoClean();
			if(fSuccessfulBuild)
				fSuccessfulBuild = DoBuild();
			break;

		case Operation.eCheckUpToDate:
			fSuccessfulBuild = DoCheckIsUpToDate();
			break;

		case Operation.eClean:
			fSuccessfulBuild = DoClean();
			break;
		}

		Fire_BuildEnd(fSuccessfulBuild);
		return fSuccessfulBuild != 0;
	}

	bool doCustomBuilds()
	{
		string workdir = mConfig.GetProjectDir();

		CHierNode node = searchNode(mConfig.GetProjectNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					if(!mConfig.isUptodate(file))
					{
						string cmdline = mConfig.GetCompileCommand(file);
						if(cmdline.length)
						{
							string outfile = mConfig.GetOutputFile(file);
							string cmdfile = makeFilenameAbsolute(outfile ~ "." ~ kCmdLogFileExtension, workdir);
							HRESULT hr = RunCustomBuildBatchFile(outfile, cmdfile, cmdline, m_pIVsOutputWindowPane, this);
							if (hr != S_OK)
								return true; // stop compiling
						}
					}
				}
				return false;
			});

		return node is null;
	}

	bool DoBuild()
	{
		beginLog();
		HRESULT hr = S_FALSE;
		
		try
		{
			string target = mConfig.GetTargetPath();
			string msg = "Building " ~ target ~ "...\n";
			if(m_pIVsOutputWindowPane)
				m_pIVsOutputWindowPane.OutputString(_toUTF16z(msg));

			string workdir = mConfig.GetProjectDir();
			string outdir = makeFilenameAbsolute(mConfig.GetOutDir(), workdir);
			if(!exists(outdir))
				mkdirRecurse(outdir);
			string intermediatedir = makeFilenameAbsolute(mConfig.GetIntermediateDir(), workdir);
			if(!exists(intermediatedir))
				mkdirRecurse(intermediatedir);

			if(!doCustomBuilds())
				return false;

			string cmdline = mConfig.getCommandLine();
			string cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(), workdir);
			hr = RunCustomBuildBatchFile(target, cmdfile, cmdline, m_pIVsOutputWindowPane, this);
			return (hr == S_OK);
		}
		catch(FileException)
		{
			return false;
		}
		finally
		{
			endLog(hr == S_OK);
		}
	}

	bool DoCheckIsUpToDate()
	{
		if(!mConfig.customFilesUpToDate())
			return false;

		string workdir = mConfig.GetProjectDir();
		string cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(), workdir);

		string cmdline = mConfig.getCommandLine();
		if(!compareCommandFile(cmdfile, cmdline))
			return false;

		string target = makeFilenameAbsolute(mConfig.GetTargetPath(), workdir);
		long targettm = getOldestFileTime( [ target ] );
		
		string deppath = makeFilenameAbsolute(mConfig.GetDependenciesPath(), workdir);
		if(!std.file.exists(deppath))
			return false;
		string[] files = getFilenamesFromDepFile(deppath);
		string[] libs = mConfig.getLibsFromDependentProjects();
		files ~= libs;
		makeFilenamesAbsolute(files, workdir);
		long sourcetm = getNewestFileTime(files);

		return targettm > sourcetm;
	}

	bool DoClean()
	{
		string[] files = mConfig.GetBuildFiles();
		foreach(string file; files)
		{
			try
			{
				if(indexOf(file,'*') >= 0 || indexOf(file,'?') >= 0)
				{
					string dir = dirname(file);
					string pattern = basename(file);
					foreach(string f; dirEntries(dir, SpanMode.shallow))
						if(fnmatch(f, pattern))
							std.file.remove(f);
				}
				else if(std.file.exists(file))
					std.file.remove(file);
			}
			catch(FileException e)
			{
				OutputText("cannot delete " ~ file ~ ":" ~ e.msg);
			}
		}
		return true;
	}
	
	void OutputText(string msg)
	{
		wchar* wmsg = _toUTF16z(msg);
		if (m_pIVsStatusbar)
		{
			m_pIVsStatusbar.SetText(wmsg);
		}
		if (m_pIVsOutputWindowPane)
		{
			m_pIVsOutputWindowPane.OutputString(wmsg);
			m_pIVsOutputWindowPane.OutputString(cast(wchar*)"\n"w.ptr);
		}
	}
/+
	void InternalTick(ref BOOL rfContine);
+/

	void Fire_Tick(ref BOOL rfContinue) 
	{
		BOOL fContinue = mConfig.FFireTick();
	}

	void Fire_BuildBegin(ref BOOL rfContinue)
	{
		mConfig.FFireBuildBegin(rfContinue);
	}

	void Fire_BuildEnd(BOOL fSuccess)
	{
		mConfig.FFireBuildEnd(fSuccess);
	}

	void beginLog()
	{
		mBuildLog = `<html><head><META HTTP-EQUIV="Content-Type" content="text/html">
</head><body><pre>
<table width=100% bgcolor=#CFCFE5><tr><td>
	<font face=arial size=+3>Build Log</font>
</table>
`;
	}

	void addCommandLog(string target, string cmd, string output)
	{
		if(!mCreateLog)
			return;
		
		mBuildLog ~= "<table width=100% bgcolor=#DFDFE5><tr><td><font face=arial size=+2>\n";
		mBuildLog ~= xml.encode("Building " ~ target);
		mBuildLog ~= "\n</font></table>\n";
		
		mBuildLog ~= "<table width=100% bgcolor=#EFEFE5><tr><td><font face=arial size=+1>\n";
		mBuildLog ~= "Command Line";
		mBuildLog ~= "\n</font></table>\n";
		
		mBuildLog ~= xml.encode(cmd);

		mBuildLog ~= "<table width=100% bgcolor=#EFEFE5><tr><td><font face=arial size=+1>\n";
		mBuildLog ~= "Output";
		mBuildLog ~= "\n</font></table>\n";
		
		mBuildLog ~= xml.encode(output);
	}
	
	void endLog(bool success)
	{
		if(!mCreateLog)
			return;
		
		mBuildLog ~= "</body></html>";

		string workdir = mConfig.GetProjectDir();
		string intdir = makeFilenameAbsolute(mConfig.GetIntermediateDir(), workdir);
		string logfile = normalizeDir(intdir) ~ "buildlog.html";
		try
		{
			std.file.write(logfile, mBuildLog);
			if(!success)
				OutputText("Details saved as \"file://" ~ logfile ~ "\"");
		}
		catch(FileException e)
		{
			OutputText("cannot write " ~ logfile ~ ":" ~ e.msg);
		}
	}
	
/+
	virtual HRESULT PrepareInStartingThread(CMyProjBuildableCfg *pCMyProjBuildableCfg);
	virtual HRESULT InnerThreadMain(CMyProjBuildableCfg *pBuildableCfg);

	virtual void ReleaseThreadHandle();

+/

	Config mConfig;
	IVsLaunchPadFactory m_srpIVsLaunchPadFactory;

	IStream m_pIStream_IVsOutputWindowPane;
	IVsOutputWindowPane m_pIVsOutputWindowPane;

	IStream m_pIStream_IVsStatusbar;
	IVsStatusbar m_pIVsStatusbar;

	BOOL m_fIsUpToDate;
	Operation m_op;

	BOOL m_fStopBuild;
	HANDLE m_hEventStartSync;
	
	bool mCreateLog = true;
	string mBuildLog;
};

class CLaunchPadEvents : DComObject, IVsLaunchPadEvents
{
	this(CBuilderThread builder)
	{
		m_pBuilder = builder;
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsLaunchPadEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsLaunchPadEvents
	override HRESULT Tick(/* [out] */ BOOL * pfCancel)
	{
		BOOL fContinue = TRUE;
		m_pBuilder.Fire_Tick(fContinue);
		*pfCancel = !fContinue;
		return S_OK;
	}

public:
	CBuilderThread m_pBuilder;
};



// Runs the build commands, writing cmdfile if successful
HRESULT RunCustomBuildBatchFile(string              target,
                                string              buildfile,
                                string              cmdline, 
                                IVsOutputWindowPane pIVsOutputWindowPane, 
                                CBuilderThread      pBuilder)
{
	if (cmdline.length == 0)
		return S_OK;
	HRESULT hr = S_OK;

	// get the project root directory.
	string strProjectDir = pBuilder.mConfig.GetProjectDir();
	string batchFileText = insertCr(cmdline);
	string output;
	
	string cmdfile = buildfile ~ ".cmd";
	
	assert(pBuilder.m_srpIVsLaunchPadFactory);
	scope auto srpIVsLaunchPad = new ComPtr!(IVsLaunchPad);
	hr = pBuilder.m_srpIVsLaunchPadFactory.CreateLaunchPad(&srpIVsLaunchPad.ptr);
	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPadFactory.CreateLaunchPad failed with rc=%x", hr);
		goto failure;
	}
	assert(srpIVsLaunchPad.ptr);

	CLaunchPadEvents pCLaunchPadEvents = new CLaunchPadEvents(pBuilder);

	BSTR bstrOutput;
version(none)
{
	hr = srpIVsLaunchPad.ptr.ExecBatchScript(
		/* [in] LPCOLESTR pszBatchFileContents         */ _toUTF16z(batchFileText),
		/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(strProjectDir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
		/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow,
		/* [in] IVsOutputWindowPane *pOutputWindowPane */ pIVsOutputWindowPane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
		/* [in] ULONG nTaskItemCategory                */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // if LPF_PipeStdoutToTaskList is specified
		/* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ pCLaunchPadEvents,
		/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPad.ptr.ExecBatchScript failed with rc=%x", hr);
		goto failure;
	}
} else {
	try
	{
		std.file.write(cmdfile, cmdline);
	}
	catch(FileException e)
	{
		output = format("internal error: cannot write file " ~ cmdfile);
		hr = S_FALSE;
	}
	DWORD result;
	hr = srpIVsLaunchPad.ptr.ExecCommand(
		/* [in] LPCOLESTR pszApplicationName           */ _toUTF16z(getCmdPath()),
		/* [in] LPCOLESTR pszCommandLine               */ _toUTF16z("/Q /C " ~ quoteFilename(cmdfile)),
		/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(strProjectDir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
		/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow,
		/* [in] IVsOutputWindowPane *pOutputWindowPane */ pIVsOutputWindowPane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
		/* [in] ULONG nTaskItemCategory                */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // if LPF_PipeStdoutToTaskList is specified
		/* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ pCLaunchPadEvents,
		/* [out] DWORD *pdwProcessExitCode             */ &result,
		/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPad.ptr.ExecCommand failed with rc=%x", hr);
		goto failure;
	}
	else if(result != 0)
		hr = S_FALSE;
}
	// don't know how to get at the exit code, so check output string
	output = strip(detachBSTR(bstrOutput));
	if(hr == S_OK && _endsWith(output, "failed!"))
		hr = S_FALSE;

	if(hr == S_OK)
	{
		try
		{
			std.file.write(buildfile, cmdline);
		}
		catch(FileException e)
		{
			output = format("internal error: cannot write file " ~ buildfile);
			hr = S_FALSE;
		}
	}
failure:
	pBuilder.addCommandLog(target, cmdline, output);
	return hr;
}

string re_match_dep = r"^[A-Za-z0-9_\.]+ *\((.*)\) : p[a-z]* : [A-Za-z0-9_\.]+ \((.*)\)$";

string[] getFilenamesFromDepFile(string depfile)
{
	string[] files;
	try
	{
		string txt = cast(string)std.file.read(depfile);

		RegExp re = new RegExp(re_match_dep);
		string[] lines = splitlines(txt);
		foreach(line; lines)
		{
			string[] match = re.exec(line);
			if(match.length == 3)
			{
				string file1 = replace(match[1], "\\\\", "\\");
				string file2 = replace(match[2], "\\\\", "\\");
				addunique(files, file1);
				addunique(files, file2);
			}
		}
	}
	catch(Exception e)
	{
		// file read error
	}
	files.sort; // for faster file access?
	return files;
}


unittest
{
	string line = r"std.file (c:\\dmd\\phobos\\std\\file.d) : public : std.utf (c:\\dmd\\phobos\\std\\utf.d)";

	RegExp re = new RegExp(re_match_dep);
	string[] match = re.exec(line);

	assert(match.length == 3);
	assert(match[0] == line);
	assert(match[1] == r"c:\\dmd\\phobos\\std\\file.d");
	assert(match[2] == r"c:\\dmd\\phobos\\std\\utf.d");
}

