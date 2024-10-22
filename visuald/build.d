// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.build;

import visuald.comutil;
import visuald.logutil;
import visuald.chiernode;
import visuald.dproject;
import visuald.hierutil;
import visuald.hierarchy;
import visuald.fileutil;
import visuald.stringutil;
import visuald.config;
import visuald.dpackage;
import visuald.windows;
import visuald.pkgutil;

import stdext.path;
import stdext.file;
import stdext.string;
import stdext.array;

import core.stdc.stdlib;
import std.windows.charset;
import std.utf;
import std.string;
import std.file;
import std.path;
import std.conv;
import std.math;
import std.array;
import std.exception;
import std.algorithm;

static import core.demangle;
import core.thread;
import core.stdc.time;
import core.stdc.string;

import std.regex;
//import stdext.fred;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vsshell90;

import xml = visuald.xmlwrap;

// threaded builds cause Visual Studio to close the solution
// version = threadedBuild;
// version = taskedBuild;

version(taskedBuild)
{
	import std.parallelism;
}

// builder thread class
class CBuilderThread // : public CVsThread<CMyProjBuildableCfg>
{
public:
	this(Config cfg)
	{
		mConfig = cfg;

		// get a pointer to IVsLaunchPadFactory
		m_srpIVsLaunchPadFactory = queryService!(IVsLaunchPadFactory);
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

	HRESULT Start(Operation op, IVsOutputWindowPane pIVsOutputWindowPane)
	{
		logCall("%s.Start(op=%s, pIVsOutputWindowPane=%s)", this, op, cast(void**) pIVsOutputWindowPane);
		//mixin(LogCallMix2);

		m_op = op;

		m_pIVsOutputWindowPane = release(m_pIVsOutputWindowPane);
		m_pIVsOutputWindowPane = addref(pIVsOutputWindowPane);

		// Note that the QueryService for SID_SVsStatusbar will fail during command line build
		if(!m_pIVsStatusbar)
			m_pIVsStatusbar = queryService!(IVsStatusbar);

		mSuccess = true;

		if(op == Operation.eCheckUpToDate)
			ThreadMain(); // synchronous handling needed
		else
		{
version(taskedBuild)
{
			auto task = task((CBuilderThread t) { t.ThreadMain(); }, this);
			taskPool.put(task);
}
else version(threadedBuild)
{
			mThread = new Thread(&ThreadMain);
			mThread.start();
}
else
			ThreadMain();
		}

		//return super::Start(pCMyProjBuildableCfg);
		return mSuccess ? S_OK : S_FALSE;
	}

	void Stop(BOOL fSync)
	{
		mixin(LogCallMix2);

		m_fStopBuild = TRUE;
	}

	void QueryStatus(BOOL *pfDone)
	{
		if(pfDone)
			*pfDone = (m_op == Operation.eIdle);
	}

	void ThreadMain()
	{
		mixin(LogCallMix2);

		BOOL fContinue = TRUE;
		BOOL fSuccessfulBuild = FALSE; // set up for Fire_BuildEnd() later on.

		scope(exit)
		{
			version(threadedBuild)
				mThread = null;
			m_op = Operation.eIdle;
		}
		m_fStopBuild = false;
		Fire_BuildBegin(fContinue);

		switch (m_op)
		{
		default:
			assert(_false);
			break;

		case Operation.eBuild:
			fSuccessfulBuild = DoBuild(false);
			if(!fSuccessfulBuild)
				StopSolutionBuild();
			break;

		case Operation.eRebuild:
			fSuccessfulBuild = DoClean();
			if(fSuccessfulBuild)
				fSuccessfulBuild = DoBuild(true);
			if(!fSuccessfulBuild)
				StopSolutionBuild();
			break;

		case Operation.eCheckUpToDate:
			fSuccessfulBuild = DoCheckIsUpToDate();
			break;

		case Operation.eClean:
			fSuccessfulBuild = DoClean();
			break;
		}

		Fire_BuildEnd(fSuccessfulBuild);
		mSuccess = fSuccessfulBuild != 0;
	}

	bool isStopped() const { return m_fStopBuild != 0; }

	bool needsOutputParser() { return true; }

	string GetBuildDir()
	{
		return mConfig.GetProjectDir();
	}

	//////////////////////////////////////////////////////////////////////
	static struct FileDep
	{
		CFileNode file;
		string outfile;
		string[] dependencies;
	}

	// sorts inplace
	static void sortDependencies(FileDep[] filedeps)
	{
		for(int i = 0, j, k; i < filedeps.length; i++)
		{
			// sort i-th file before the first file that depends on it
			for(j = 0; j < i; j++)
			{
				if(countUntil(filedeps[j].dependencies, filedeps[i].outfile) >= 0)
					break;
			}
			// check whether the i-th file depends on any later file
			for(k = j; k < i; k++)
			{
				if(countUntil(filedeps[i].dependencies, filedeps[k].outfile) >= 0)
					throw new Exception("circular dependency on " ~ filedeps[i].outfile);
			}
			if(j < i)
			{
				FileDep dep = filedeps[i];
				for(k = i; k > j; k--)
					filedeps[k] = filedeps[k-1];
				filedeps[j] = dep;
			}
		}
	}

	CFileNode[] BuildDependencyList()
	{
		string workdir = mConfig.GetProjectDir();
		Config config = mConfig; // closure does not work with both local variables and this pointer?
		FileDep[] filedeps;
		CHierNode node = searchNode(mConfig.GetProjectNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
				{
					string tool = config.GetCompileTool(file);
					if(tool == "Custom" || tool == kToolResourceCompiler || tool == kToolCpp)
					{
						FileDep dep;
						dep.outfile = config.GetOutputFile(file);
						dep.outfile = canonicalPath(makeFilenameAbsolute(dep.outfile, workdir));
						dep.dependencies = config.GetDependencies(file);
						foreach(ref d; dep.dependencies)
							d = canonicalPath(d);
						dep.file = file;
						filedeps ~= dep;
					}
				}
				return false;
			});

		sortDependencies(filedeps);
		CFileNode[] files;
		foreach(fdep; filedeps)
			files ~= fdep.file;

		return files;
	}

	unittest
	{
		FileDep[] deps = [
			{ null, "file1", [ "file2", "file3" ] },
			{ null, "file2", [ "file4", "file5" ] },
			{ null, "file3", [ "file2", "file6" ] },
		];
		sortDependencies(deps);
		assert(deps[0].outfile == "file2");
		assert(deps[1].outfile == "file3");
		assert(deps[2].outfile == "file1");

		deps[0].dependencies ~= "file1";
		try
		{
			sortDependencies(deps);
			assert(false);
		}
		catch(Exception e)
		{
			assert(std.string.indexOf(e.msg, "circular") >= 0);
		}
	}

	//////////////////////////////////////////////////////////////////////
	bool buildCustomFile(CFileNode file, ref bool built)
	{
		string reason;
		if(!mConfig.isUptodate(file, &reason))
		{
			string cmdline = mConfig.GetCompileCommand(file);
			if(cmdline.length)
			{
				string workdir = mConfig.GetProjectDir();
				string outfile = mConfig.GetOutputFile(file);
				string cmdfile = mConfig.getCustomCommandFile(outfile);
				showUptodateFailure(reason, outfile);
				removeCachedFileTime(makeFilenameAbsolute(outfile, workdir));
				HRESULT hr = RunCustomBuildBatchFile(outfile, cmdfile, cmdline, m_pIVsOutputWindowPane, this);
				if (hr != S_OK)
					return false; // stop compiling
			}
			built = true;
		}
		return true;
	}

	//////////////////////////////////////////////////////////////////////
	bool buildPhobos(ref bool built)
	{
		string reason;
		if(!mConfig.isPhobosUptodate(&reason))
		{
			string cmdline = mConfig.GetPhobosCommandLine();
			if(cmdline.length)
			{
				string workdir = mConfig.GetProjectDir();
				string outfile = mConfig.GetPhobosPath();
				string cmdfile = mConfig.getCustomCommandFile(outfile);
				showUptodateFailure(reason, outfile);
				removeCachedFileTime(makeFilenameAbsolute(outfile, workdir));
				HRESULT hr = RunCustomBuildBatchFile(outfile, cmdfile, cmdline, m_pIVsOutputWindowPane, this);
				if (hr != S_OK)
					return false; // stop compiling
			}
			built = true;
		}
		return true;
	}

	/** build non-D files */
	bool doCustomBuilds(out bool hasCustomBuilds, out int numCustomBuilds)
	{
		mixin(LogCallMix2);

		bool built;
		if(mConfig.GetProjectOptions().privatePhobos)
		{
			if (!buildPhobos(built))
				return false;
			if(built)
				numCustomBuilds++;
		}

		// first build custom files with dependency graph
		CFileNode[] files = BuildDependencyList();
		foreach(file; files)
		{
			if(isStopped())
				return false;
			if(!buildCustomFile(file, built))
				return false;
			hasCustomBuilds = true;
			if(built)
				numCustomBuilds++;
		}

		// now build files not in the dependency graph (d files in single compilation modes)
		CHierNode node = searchNode(mConfig.GetProjectNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
				{
					if(files.contains(file))
						return false;
					if(isStopped())
						return true;
					if(!buildCustomFile(file, built))
						return true;

					hasCustomBuilds = true;
					if(built)
						numCustomBuilds++;
				}
				return false;
			});

		return node is null;
	}

	bool DoBuild(bool rebuild)
	{
		mixin(LogCallMix2);

		beginLog();
		HRESULT hr = S_FALSE;

		try
		{
			string target = mConfig.GetTargetPath();
			string msg = "Building " ~ target ~ "...\n";
			if(m_pIVsOutputWindowPane)
			{
				ScopedBSTR bstrMsg = ScopedBSTR(msg);
				m_pIVsOutputWindowPane.OutputString(bstrMsg);
			}

			string workdir = mConfig.GetProjectDir();
			string outdir = makeFilenameAbsolute(mConfig.GetOutDir(), workdir);
			if(!exists(outdir))
				mkdirRecurse(outdir);
			string intermediatedir = makeFilenameAbsolute(mConfig.GetIntermediateDir(), workdir);
			if(!exists(intermediatedir))
				mkdirRecurse(intermediatedir);

			auto opts = mConfig.GetProjectOptions();
			string modules_ddoc;
			if(mConfig.getModulesDDocCommandLine([], modules_ddoc).length)
			{
				modules_ddoc = unquoteArgument(modules_ddoc);
				modules_ddoc = opts.replaceEnvironment(modules_ddoc, mConfig);
				string modpath = dirName(modules_ddoc);
				modpath = makeFilenameAbsolute(modpath, workdir);
				if(!exists(modpath))
					mkdirRecurse(modpath);
			}

			bool hasCustomBuilds;
			int numCustomBuilds;
			if(!doCustomBuilds(hasCustomBuilds, numCustomBuilds))
				return false;

			if(hasCustomBuilds)
				if(targetIsUpToDate(false, false, rebuild)) // only recheck target if custom builds exist
					return true; // no need to rebuild target if custom builds did not change target dependencies

			if(!mLastUptodateFailure.empty)
				showUptodateFailure(mLastUptodateFailure);

			bool combined = opts.isCombinedBuild();
			if (combined || !targetIsUpToDate(true, false, rebuild))
			{
				string cmdline = mConfig.getCommandLine(true, combined, rebuild);
				string cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(false), workdir);
				hr = RunCustomBuildBatchFile(target, cmdfile, cmdline, m_pIVsOutputWindowPane, this);
			}
			else
				hr = S_OK;
			if (hr == S_OK && !combined)
			{
				string cmdline = mConfig.getCommandLine(false, true, rebuild);
				string cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(true), workdir);
				hr = RunCustomBuildBatchFile(target, cmdfile, cmdline, m_pIVsOutputWindowPane, this);

				if(hr == S_OK && opts.compilationModel == ProjectOptions.kSingleFileCompilation)
					mConfig.writeLinkDependencyFile();
			}
			return (hr == S_OK);
		}
		catch(Exception e)
		{
			OutputText("Error setting up build: " ~ e.msg);
			return false;
		}
		finally
		{
			endLog(hr == S_OK);
		}
	}

	bool customFilesUpToDate()
	{
		if(mConfig.GetProjectOptions().privatePhobos)
			if (!mConfig.isPhobosUptodate(null))
				return false;

		CHierNode node = searchNode(mConfig.GetProjectNode(),
			delegate (CHierNode n)
			{
				if(isStopped())
					return true;
				if(CFileNode file = cast(CFileNode) n)
				{
					if(!mConfig.isUptodate(file, null))
						return true;
				}
				return false;
			});

		return node is null;
	}

	bool getTargetDependencies(ref string[] files, bool compileOnly)
	{
		string workdir = mConfig.GetProjectDir();

		string deppath = makeFilenameAbsolute(mConfig.GetDependenciesPath(), workdir);
		if(!std.file.exists(deppath))
			return showUptodateFailure("dependency file " ~ deppath ~ " does not exist");

		if(!getFilenamesFromDepFile(deppath, files))
			return showUptodateFailure("dependency file " ~ deppath ~ " cannot be read");

		if(!compileOnly && mConfig.hasLinkDependencies())
		{
			string lnkdeppath = makeFilenameAbsolute(mConfig.GetLinkDependenciesPath(), workdir);
			if(!std.file.exists(lnkdeppath))
				return showUptodateFailure("link dependency file " ~ lnkdeppath ~ " does not exist");

			getFilesFromTrackerFile(lnkdeppath, files);
		}
		return true;
	}

	bool DoCheckIsUpToDate()
	{
		mixin(LogCallMix2);

		clearCachedFileTimes();
		scope(exit) clearCachedFileTimes();

		mLastUptodateFailure = null;
		if(!customFilesUpToDate())
			return false;

		return targetIsUpToDate(false, true, false);
	}

	bool targetIsUpToDate(bool compileOnly, bool showFailure, bool rebuild)
	{
		auto projopts = mConfig.GetProjectOptions();
		string workdir = mConfig.GetProjectDir();
		bool combined = projopts.isCombinedBuild();
		string cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(false), workdir);

		string cmdline = mConfig.getCommandLine(true, combined, rebuild);
		if(!compareCommandFile(cmdfile, cmdline))
			return showFailure && showUptodateFailure("command line changed");

		string target = canonicalPath(makeFilenameCanonical(mConfig.GetTargetPath(), workdir));
		string[] targets;
		if(!combined && compileOnly)
		{
			string[] files = mConfig.getInputFileList();
			string[] lnkfiles = mConfig.getObjectFileList(files); // convert D files to object files, but leaves anything else untouched

			string[] objfiles;
			string ext = "." ~ projopts.objectFileExtension();
			foreach (file; lnkfiles)
				if (extension(file) == ext)
					targets ~= projopts.replaceEnvironment(file, mConfig);
			makeFilenamesCanonical(targets, workdir);
			foreach(ref string t; targets)
				t = canonicalPath(t);
		}
		else
		{
			targets = [ target ];
		}
		if (!combined && !compileOnly)
		{
			cmdfile = makeFilenameAbsolute(mConfig.GetCommandLinePath(true), workdir);
			cmdline = mConfig.getCommandLine(false, true, rebuild);
			if(!compareCommandFile(cmdfile, cmdline))
				return showFailure && showUptodateFailure("linker command line changed");
		}

		string oldestFile;
		long targettm = getOldestFileTime(targets, oldestFile);
		if(targettm == long.min)
			return showFailure && showUptodateFailure(oldestFile ~ " does not exist");

		string[] files;
		if(!getTargetDependencies(files, compileOnly))
			return false;

		if (!compileOnly)
		{
			string[] libs = mConfig.getLibsFromDependentProjects();
			files ~= libs;
		}
		makeFilenamesCanonical(files, workdir);
		foreach(ref string f; files)
			f = canonicalPath(f);
		// remove targets from source files, dmd 2.098 reads lib files to update them only if modified
		size_t g = 0;
		for (size_t f = 0; f < files.length; f++)
			if (!targets.contains(files[f]))
				files[g++] = files[f];
		files.length = g;

		string newestFile;
		long sourcetm = getNewestFileTime(files, newestFile);

		bool allowSameTime = (projopts.compilationModel == ProjectOptions.kCompileThroughDub) && icmp(oldestFile, target) == 0;
		if(allowSameTime && targettm < sourcetm ||
		   !allowSameTime && targettm <= sourcetm)
			return showFailure && showUptodateFailure(oldestFile ~ " older than " ~ newestFile);
		return true;
	}

	bool DoClean()
	{
		mixin(LogCallMix2);

		string[] files = mConfig.GetBuildFiles();
		foreach(string file; files)
		{
			try
			{
				if(std.string.indexOf(file,'*') >= 0 || std.string.indexOf(file,'?') >= 0)
				{
					string dir = dirName(file);
					string pattern = baseName(file);
					if(isExistingDir(dir))
						foreach(string f; dirEntries(dir, SpanMode.depth))
							if(globMatch(f, pattern))
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
		rfContinue = mConfig.FFireTick() && !m_fStopBuild;
	}

	void Fire_BuildBegin(ref BOOL rfContinue)
	{
		mixin(LogCallMix2);

		mConfig.FFireBuildBegin(rfContinue);
	}

	void Fire_BuildEnd(BOOL fSuccess)
	{
		mixin(LogCallMix2);

		mConfig.FFireBuildEnd(fSuccess);
	}

	void StopSolutionBuild()
	{
		if(!Package.GetGlobalOptions().stopSolutionBuild)
			return;

		if(auto solutionBuildManager = queryService!(IVsSolutionBuildManager)())
		{
			OutputText("Solution build stopped.");
			scope(exit) release(solutionBuildManager);
			solutionBuildManager.CancelUpdateSolutionConfiguration();
		}
	}

	bool showUptodateFailure(string msg, string target = null)
	{
		if(!m_pIVsOutputWindowPane)
			mLastUptodateFailure = msg;
		else if(Package.GetGlobalOptions().showUptodateFailure)
		{
			if(target.empty)
				target = mConfig.GetTargetPath();
			msg = target ~ " not up to date: " ~ msg;
			OutputText(msg); // writeToBuildOutputPane
		}
		return false;
	}

	void beginLog()
	{
		mStartBuildTime = time(null);

		mBuildLog = `<html><head><meta http-equiv="Content-Type" content="text/html" charset="utf-8">
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

		mBuildLog ~= xml.encode(output) ~ "\n";
	}

	void endLog(bool success)
	{
		if(!mCreateLog)
			return;

		mBuildLog ~= "</body></html>";

		string workdir = mConfig.GetProjectDir();
		string intdir = makeFilenameAbsolute(mConfig.GetIntermediateDir(), workdir);
		string logfile = mConfig.GetBuildLogFile();
		try
		{
			std.file.write(logfile, mBuildLog);
			if(!success)
				OutputText("Details saved as \"file://" ~ replace(logfile, " ", "%20") ~ "\"");
		}
		catch(FileException e)
		{
			OutputText("cannot write " ~ logfile ~ ":" ~ e.msg);
		}

		if(Package.GetGlobalOptions().timeBuilds)
		{
			time_t now = time(null);
			double duration = difftime(now, mStartBuildTime);
			if(duration >= 60)
			{
				int min = cast(int) floor(duration / 60);
				int sec = cast(int) floor(duration - 60 * min);
				string tm = format("%d:%02d", min, sec);
				OutputText("Build time: " ~ to!string(min) ~ ":" ~ to!string(sec) ~ " min");
			}
			else
				OutputText("Build time: " ~ to!string(duration) ~ " s");
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

	time_t mStartBuildTime;

	version(threadedBuild)
		Thread mThread; // keep a reference to the thread to avoid it from being collected
	bool mSuccess = false;
	bool mCreateLog = true;
	string mBuildLog;
	string mLastUptodateFailure;
};

class CLaunchPadEvents : DComObject, IVsLaunchPadEvents
{
	this(CBuilderThread builder)
	{
		m_pBuilder = builder;
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
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

string demangleText(string ln)
{
	string txt;
	static if(__traits(compiles, (){size_t p; decodeDmdString("", p);}))
		size_t i;
	else
		int i; // until dmd 2.056
	for (i = 0; i < ln.length; )
	{
		char ch = ln[i]; // compressed symbols are NOT utf8!
		if(isAlphaNum(ch) || ch == '_')
		{
			string s = decodeDmdString(ln, i);
			if(s.length > 3 && s[0] == '_' && s[1] == 'D' && isDigit(s[2]))
			{
				auto d = core.demangle.demangle(s);
				txt ~= d;
			}
			else if(s.length > 4 && s[0] == '_' && s[1] == '_' && s[2] == 'D' && isDigit(s[3]))
			{
				// __moddtor/__modctor have duplicate '__'
				auto d = core.demangle.demangle(s[1..$]);
				if(d == s[1..$])
					txt ~= s;
				else
					txt ~= d;
			}
			else
				txt ~= s;
		}
		else
		{
			txt ~= ch;
			i++;
		}
	}
	return txt;
}

class CLaunchPadOutputParser : DComObject, IVsLaunchPadOutputParser
{
	this(CBuilderThread builder)
	{
		mConfig = builder.mConfig;
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsLaunchPadOutputParser) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT ParseOutputStringForInfo(
		const LPCOLESTR pszOutputString,   // one line of output text
		/+[out, optional]+/ BSTR *pbstrFilename,        // fully-qualified file name for task list item (may be NULL)
		/+[out, optional]+/ ULONG *pnLineNum,           // file line number for task list item (may be NULL)
		/+[out, optional]+/ ULONG *pnPriority,          // priority for task list item (may be NULL)
		/+[out, optional]+/ BSTR *pbstrTaskItemText,    // description text for task list item (may be NULL)
		/+[out, optional]+/ BSTR *pbstrHelpKeyword)
	{
		mixin(LogCallMix2);

		string line = to_string(pszOutputString);
		uint nPriority, nLineNum;
		string filename, taskItemText;

		if(!parseOutputStringForTaskItem(line, nPriority, filename, nLineNum, taskItemText, mConfig))
			return S_FALSE;

		//if(Package.GetGlobalOptions().demangleError)
		//	taskItemText = demangleText(taskItemText);

		filename = makeFilenameCanonical(filename, mConfig.GetProjectDir());
		if(pnPriority)
			*pnPriority = nPriority;
		if(pnLineNum)
			*pnLineNum = nLineNum - 1;
		if(pbstrFilename)
			*pbstrFilename = allocBSTR(filename);
		if(pbstrTaskItemText)
			*pbstrTaskItemText = allocBSTR(taskItemText);
		return S_OK;
	}

	Config mConfig;
}


// Runs the build commands, writing cmdfile if successful
HRESULT RunCustomBuildBatchFile(string              target,
                                string              buildfile,
                                string              cmdline,
                                IVsOutputWindowPane pIVsOutputWindowPane,
                                CBuilderThread      pBuilder)
{
	logCall("RunCustomBuildBatchFile(target=\"%s\", buildfile=\"%s\")", target, buildfile);

	if (cmdline.length == 0)
		return S_OK;
	HRESULT hr = S_OK;

	// get the project root directory.
	string strBuildDir = pBuilder.GetBuildDir();
	string batchFileText = insertCr(cmdline);
	string output;

	Package.GetGlobalOptions().addBuildPath(strBuildDir);

	string cmdfile = buildfile ~ ".cmd";

	assert(pBuilder.m_srpIVsLaunchPadFactory);
	ComPtr!(IVsLaunchPad) srpIVsLaunchPad;
	hr = pBuilder.m_srpIVsLaunchPadFactory.CreateLaunchPad(&srpIVsLaunchPad.ptr);
	scope(exit) pBuilder.addCommandLog(target, cmdline, output);

	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPadFactory.CreateLaunchPad failed with rc=%x", hr);
		return hr;
	}
	assert(srpIVsLaunchPad.ptr);

	CLaunchPadEvents pLaunchPadEvents = newCom!CLaunchPadEvents(pBuilder);

	BSTR bstrOutput;
version(none)
{
	hr = srpIVsLaunchPad.ExecBatchScript(
		/* [in] LPCOLESTR pszBatchFileContents         */ _toUTF16z(batchFileText),
		/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(strBuildDir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
		/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow,
		/* [in] IVsOutputWindowPane *pOutputWindowPane */ pIVsOutputWindowPane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
		/* [in] ULONG nTaskItemCategory                */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
		/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // if LPF_PipeStdoutToTaskList is specified
		/* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ pLaunchPadEvents,
		/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPad.ptr.ExecBatchScript failed with rc=%x", hr);
		return hr;
	}
} else {
	try
	{
		int cp = GetKBCodePage();
		const(char)*p = toMBSz(batchFileText, cp);
		const plen = strlen(p);
		string dir = dirName(cmdfile);
		if(!std.file.exists(dir))
			mkdirRecurse(dir);
		std.file.write(cmdfile, p[0..plen]);
	}
	catch(FileException e)
	{
		output = format("internal error: cannot write file " ~ cmdfile);
		hr = S_FALSE;
	}

	string quiet = Package.GetGlobalOptions().echoCommands ? "" : "/Q ";
	DWORD result;
	IVsLaunchPad2 pad2 = qi_cast!IVsLaunchPad2(srpIVsLaunchPad);
	if(pad2 && pBuilder.needsOutputParser())
	{
		CLaunchPadOutputParser pLaunchPadOutputParser = newCom!CLaunchPadOutputParser(pBuilder);
		hr = pad2.ExecCommandEx(
			/* [in] LPCOLESTR pszApplicationName           */ _toUTF16z(getCmdPath()),
			/* [in] LPCOLESTR pszCommandLine               */ _toUTF16z(quiet ~ "/C " ~ quoteFilenameForCmd(cmdfile)),
			/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(strBuildDir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
			/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow | LPF_PipeStdoutToTaskList,
			/* [in] IVsOutputWindowPane *pOutputWindowPane */ pIVsOutputWindowPane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
			/* [in] ULONG nTaskItemCategory                */ CAT_BUILDCOMPILE, // if LPF_PipeStdoutToTaskList is specified
			/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
			/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // "Build"w.ptr, // if LPF_PipeStdoutToTaskList is specified
			/* [in] IVsLaunchPadEvents pVsLaunchPadEvents  */ pLaunchPadEvents,
			/* [in] IVsLaunchPadOutputParser pOutputParser */ pLaunchPadOutputParser,
			/* [out] DWORD *pdwProcessExitCode             */ &result,
			/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)
		release(pad2);
	}
	else
		hr = srpIVsLaunchPad.ExecCommand(
			/* [in] LPCOLESTR pszApplicationName           */ _toUTF16z(getCmdPath()),
			/* [in] LPCOLESTR pszCommandLine               */ _toUTF16z(quiet ~ "/C " ~ quoteFilenameForCmd(cmdfile)),
			/* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(strBuildDir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
			/* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow | LPF_PipeStdoutToTaskList,
			/* [in] IVsOutputWindowPane *pOutputWindowPane */ pIVsOutputWindowPane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
			/* [in] ULONG nTaskItemCategory                */ CAT_BUILDCOMPILE, // if LPF_PipeStdoutToTaskList is specified
			/* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
			/* [in] LPCOLESTR pszTaskListSubcategory       */ null, // "Build"w.ptr, // if LPF_PipeStdoutToTaskList is specified
			/* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ pLaunchPadEvents,
			/* [out] DWORD *pdwProcessExitCode             */ &result,
			/* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

	if(FAILED(hr))
	{
		output = format("internal error: IVsLaunchPad.ptr.ExecCommand failed with rc=%x", hr);
		return hr;
	}
	if(result != 0)
		hr = S_FALSE;
}
	// don't know how to get at the exit code, so check output string
	output = strip(detachBSTR(bstrOutput));
	if(hr == S_OK && _endsWith(output, "failed!"))
		hr = S_FALSE;

	// outputToErrorList(srpIVsLaunchPad, pBuilder, pIVsOutputWindowPane, output);

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
	return hr;
}

HRESULT outputToErrorList(IVsLaunchPad pad, CBuilderThread pBuilder,
                          IVsOutputWindowPane outPane, string output)
{
	logCall("outputToErrorList(output=\"%s\")", output);

	HRESULT hr;

	auto prj = _toUTF16z(pBuilder.mConfig.GetProjectPath());
	string[] lines = std.string.split(output, "\n");
	foreach(line; lines)
	{
		uint nPriority, nLineNum;
		string strFilename, strTaskItemText;

		if(parseOutputStringForTaskItem(line, nPriority, strFilename, nLineNum, strTaskItemText, pBuilder.mConfig))
		{
			IVsOutputWindowPane2 pane2 = qi_cast!IVsOutputWindowPane2(outPane);
			if(pane2)
				hr = pane2.OutputTaskItemStringEx2(
							"."w.ptr,              // The text to write to the output window.
							nPriority,             // The priority: use TP_HIGH for errors.
							CAT_BUILDCOMPILE,      // Not used internally; pass NULL unless you want to use it for your own purposes.
							null,                  // Not used internally; pass NULL unless you want to use it for your own purposes.
							0,                     // Not used internally.
							_toUTF16z(strFilename),          // The file name for the Error List entry; may be NULL if no file is associated with the error.
							nLineNum,              // Zero-based line number in pszFilename.
							nLineNum,                     // Zero-based column in pszFilename.
							prj,                   // The unique name of the project for the Error List entry; may be NULL if no project is associated with the error.
							_toUTF16z(strTaskItemText),      // The text of the Error List entry.
							""w.ptr);              // in LPCOLESTR pszLookupKwd
			else // no project or column +/
				hr = outPane.OutputTaskItemStringEx(
							" "w.ptr,               // The text to write to the output window.
							nPriority,             // The priority: use TP_HIGH for errors.
							CAT_BUILDCOMPILE,      // Not used internally; pass NULL unless you want to use it for your own purposes.
							null,                  // Not used internally; pass NULL unless you want to use it for your own purposes.
							0,                     // Not used internally.
							_toUTF16z(strFilename),          // The file name for the Error List entry; may be NULL if no file is associated with the error.
							nLineNum,              // Zero-based line number in pszFilename.
							_toUTF16z(strTaskItemText),      // The text of the Error List entry.
							""w.ptr);              // in LPCOLESTR pszLookupKwd
			release(pane2);
		}
	}
	return hr;
}

bool isInitializedRE(T)(ref T re)
{
	static if(__traits(compiles,re.ir))
		return re.ir !is null; // stdext.fred
	else
		return !re.empty; // std.regex
}

bool parseOutputStringForTaskItem(string outputLine, out uint nPriority,
                                  out string filename, out uint nLineNum,
                                  out string itemText, Config config)
{
	outputLine = strip(outputLine);

	void setPriority()
	{
		auto opts = config ? config.GetProjectOptions() : null;
		if(itemText.startsWith("Warning:"))
			nPriority = opts && opts.infowarnings ? TP_NORMAL : TP_HIGH;
		else if(itemText.startsWith("Deprecation:"))
			nPriority = opts && opts.errDeprecated ? TP_HIGH : TP_NORMAL;
		else
			nPriority = TP_HIGH;
	}

	// DMD compile error
	__gshared static Regex!char re1dmd, re1gdc, remixin, re2, re3, re4, re5, re6;

	if(!isInitializedRE(remixin))
		remixin = regex(r"^(.*?)-mixin-([0-9]+)\(([0-9]+)\):(.*)$");

	auto rematch = match(outputLine, remixin);
	if(!rematch.empty())
	{
		auto captures = rematch.captures();
		filename = replace(captures[1], "\\\\", "\\");
		string lineno = captures[2];
		string lineno2 = captures[3];
		nLineNum = to!uint(lineno);
		uint nMixinLine = to!uint(lineno2) - nLineNum + 1;
		itemText = "mixin(" ~ to!string(nMixinLine) ~ ") " ~ strip(captures[4]);
		setPriority();
		return true;
	}

	// exception/error when running
	if(!isInitializedRE(re5))
		re5 = regex(r"^[^ @]*@(.*?)\(([0-9]+)\):(.*)$");

	rematch = match(outputLine, re5);
	if(!rematch.empty())
	{
		auto captures = rematch.captures();
		nPriority = TP_HIGH;
		filename = replace(captures[1], "\\\\", "\\");
		string lineno = captures[2];
		nLineNum = to!uint(lineno);
		itemText = strip(captures[3]);
		return true;
	}

	if(!isInitializedRE(re1dmd))
		re1dmd = regex(r"^(.*?)\(([0-9]+)\):(.*)$"); // replace . with [\x00-\x7f] for std.regex
	if(!isInitializedRE(re1gdc))
		re1gdc = regex(r"^(.*?):([0-9]+):(.*)$");

	rematch = match(outputLine, config && config.GetProjectOptions().compiler == Compiler.GDC ? re1gdc : re1dmd);
	if(!rematch.empty())
	{
		auto captures = rematch.captures();
		filename = replace(captures[1], "\\\\", "\\");
		string lineno = captures[2];
		nLineNum = to!uint(lineno);
		itemText = strip(captures[3]);
		setPriority();
		return true;
	}

	// link error
	if(!isInitializedRE(re2))
		re2 = regex(r"^ *(Error *[0-9]+:.*)$");

	rematch = match(outputLine, re2);
	if(!rematch.empty())
	{
		nPriority = TP_HIGH;
		filename = "";
		nLineNum = 0;
		itemText = strip(rematch.captures[1]);
		return true;
	}

	// link error with file name
	if(!isInitializedRE(re3))
		re3 = regex(r"^(.*?)\(([0-9]+)\) *: *(Error *[0-9]+:.*)$");

	rematch = match(outputLine, re3);
	if(!rematch.empty())
	{
		auto captures = rematch.captures();
		nPriority = TP_HIGH;
		filename = replace(captures[1], "\\\\", "\\");
		string lineno = captures[2];
		nLineNum = to!uint(lineno);
		itemText = strip(captures[3]);
		return true;
	}

	// link warning
	if(!isInitializedRE(re4))
		re4 = regex(r"^ *(Warning *[0-9]+:.*)$");

	rematch = match(outputLine, re4);
	if(!rematch.empty())
	{
		nPriority = TP_NORMAL;
		filename = "";
		nLineNum = 0;
		itemText = strip(rematch.captures[1]);
		return true;
	}

	// entry in exception call stack
	if(!isInitializedRE(re6))
		re6 = regex(r"^0x[0-9a-fA-F]* in .* at (.*?)\(([0-9]+)\)(.*)$");

	rematch = match(outputLine, re6);
	if(!rematch.empty())
	{
		auto captures = rematch.captures();
		nPriority = TP_LOW;
		filename = replace(captures[1], "\\\\", "\\");
		string lineno = captures[2];
		nLineNum = to!uint(lineno);
		itemText = strip(captures[3]);
		return true;
	}

	return false;
}

unittest
{
	uint nPriority, nLineNum;
	string strFilename, strTaskItemText;
	bool rc = parseOutputStringForTaskItem("file.d(37): huhu", nPriority, strFilename, nLineNum, strTaskItemText, null);
	assert(rc);
	assert(strFilename == "file.d");
	assert(nLineNum == 37);
	assert(strTaskItemText == "huhu");

	rc = parseOutputStringForTaskItem("main.d(10): Error: undefined identifier A, did you mean B?",
									  nPriority, strFilename, nLineNum, strTaskItemText, null);
	assert(rc);
	assert(strFilename == "main.d");
	assert(nLineNum == 10);
	assert(strTaskItemText == "Error: undefined identifier A, did you mean B?");

	rc = parseOutputStringForTaskItem(r"object.Exception@C:\tmp\d\forever.d(28): what?",
									  nPriority, strFilename, nLineNum, strTaskItemText, null);
	assert(rc);
	assert(strFilename == r"C:\tmp\d\forever.d");
	assert(nLineNum == 28);
	assert(strTaskItemText == "what?");

	rc = parseOutputStringForTaskItem(r"0x004020C8 in void test.__modtest() at C:\tmp\d\forever.d(34)",
									  nPriority, strFilename, nLineNum, strTaskItemText, null);
	assert(rc);
	assert(strFilename == r"C:\tmp\d\forever.d");
	assert(nLineNum == 34);
	assert(strTaskItemText == "");

	rc = parseOutputStringForTaskItem(r"D:\LuaD\luad\conversions\structs.d-mixin-36(36): Error: cast(MFVector)(*_this).x is not an lvalue",
									  nPriority, strFilename, nLineNum, strTaskItemText, null);
	assert(rc);
	assert(strFilename == r"D:\LuaD\luad\conversions\structs.d");
	assert(nLineNum == 36);
	assert(strTaskItemText == "mixin(1) Error: cast(MFVector)(*_this).x is not an lvalue");
}

string unEscapeFilename(string file)
{
	auto pos = std.string.indexOf(file, '\\');
	if(pos < 0)
		return file;

	char[] p;
	size_t start = 0;
	while(pos < file.length)
	{
		if(file[pos+1] == '(' || file[pos+1] == ')' || file[pos+1] == '\\')
		{
			p ~= file[start .. pos];
			start = pos + 1;
		}
		auto nextpos = std.string.indexOf(file[pos + 1 .. $], '\\');
		if(nextpos < 0)
			break;
		pos += nextpos + 1;
	}
	p ~= file[start..$];
	return assumeUnique(p);
}

string re_match_dep = r"^[A-Za-z0-9_\.]+ *\((.*)\) : p[a-z]* : [A-Za-z0-9_\.]+ \((.*)\)$";

bool getFilenamesFromDepFile(string depfile, ref string[] files)
{
static if (usePipedmdForDeps)
	return getFilesFromTrackerFile(depfile, files);
else {
	// converted int[string] to byte[string] due to bug #2500
	byte[string] aafiles;

	int cntValid = 0;
	try
	{
		string txt = cast(string)std.file.read(depfile);

version(slow)
{
		RegExp re = new RegExp(re_match_dep);
		string[] lines = splitLines(txt);
		foreach(line; lines)
		{
			string[] match = re.exec(line);
			if(match.length == 3)
			{
				string file1 = replace(match[1], "\\\\", "\\");
				string file2 = replace(match[2], "\\\\", "\\");
				aafiles[file1] = 1;
				aafiles[file2] = 1;
				cntValid++;
			}
		}
}
else
{
		uint pos = 0;
		uint openpos = 0;
		bool skipNext = false;
		bool stringImport = false;
		while(pos < txt.length)
		{
			dchar ch = decode(txt, pos);
			if(skipNext)
			{
				skipNext = false;
				continue;
			}
			if(ch == '\\')
				skipNext = true;
			if(ch == '(')
				openpos = pos;
			else if(ch == ')' && openpos > 0)
			{
				// only check lines that import "object", these are written once per file
				const string kCheck1 = " : public : object ";
				const string kCheck2 = " : private : object "; // added after 2.060
				const string kCheck3 = " : string : "; // string imports added after 2.064
				if((pos + kCheck1.length <= txt.length && txt[pos .. pos + kCheck1.length] == kCheck1) ||
				   (pos + kCheck2.length <= txt.length && txt[pos .. pos + kCheck2.length] == kCheck2) ||
				   stringImport)
				{
					string file = txt[openpos .. pos-1];
					file = unEscapeFilename(file);
					aafiles[file] = 1;
					openpos = 0;
					stringImport = false;
					cntValid++;
				}
				else if(pos + kCheck3.length <= txt.length && txt[pos .. pos + kCheck3.length] == kCheck3)
				{
					// wait for the next file name in () on the same line
					openpos = 0;
					stringImport = true;
				}
			}
			else if(ch == '\n')
			{
				openpos = 0;
				stringImport = false;
			}
		}
}
	}
	catch(Exception e)
	{
		cntValid = 0;
		// file read error
	}

	string[] keys = aafiles.keys; // workaround for bad codegen with files ~= aafiles.keys
	files ~= keys;
	sort(files); // for faster file access?
	return cntValid > 0;
} // static if
}

version(slow)
unittest
{
	string line = r"std.file (c:\\dmd\\phobos\\std\\file.d) : public : std.utf (c:\\dmd\\phobos\\std\\utf.d)";

	RegExp re = new RegExp(re_match_dep);
	string[] match = re.exec(line);

	assert(match.length == 3);
	assert(match[0] == line);
	assert(match[1] == r"c:\\dmd\\phobos\\std\\file.d");
	assert(match[2] == r"c:\\dmd\\phobos\\std\\utf.d");

	line = r"std.file (c:\\dmd\\phobos\\std\\file.d) : public : std.utf (c:\\dmd\\phobos\\std\\utf.d):abc,def";
	match = re.exec(line);

	assert(match.length == 3);
	assert(match[0] == line);
	assert(match[1] == r"c:\\dmd\\phobos\\std\\file.d");
	assert(match[2] == r"c:\\dmd\\phobos\\std\\utf.d");
}

bool getFilesFromTrackerFile(string lnkdeppath, ref string[] files)
{
	try
	{
		string lnkdeps;
		auto lnkdepData = cast(ubyte[])std.file.read(lnkdeppath);
		if(lnkdepData.length > 1 && lnkdepData[0] == 0xFF && lnkdepData[1] == 0xFE)
		{
			wstring lnkdepw = cast(wstring)lnkdepData[2..$];
			lnkdeps = to!string(lnkdepw);
		}
		else
		{
			// tracker file already converted to UTF8 by pipedmd
			lnkdeps = cast(string)lnkdepData;
		}

		string[] exclpaths = Package.GetGlobalOptions().getDepsExcludePaths();
		bool isExcluded(string file)
		{
			foreach(ex; exclpaths)
			{
				if (file.length >= ex.length && icmp(file[0..ex.length], ex) == 0)
				{
					if (ex[$-1] == '\\' || file.length == ex.length || file[ex.length] == '\\')
						return true;
				}
				else if (ex.indexOf('\\') < 0 && globMatch(baseName(file).toLower, ex.toLower))
					return true;
			}
			return false;
		}

		string[] lnkfiles = splitLines(lnkdeps);
		foreach(lnkfile; lnkfiles)
		{
			if(!lnkfile.startsWith("#Command:") && !isExcluded(lnkfile))
				files ~= lnkfile; // makeFilenameAbsolute(lnkfile, workdir);
		}
		return true;
	}
	catch(Exception)
	{
		return false;
	}
}

bool launchBatchProcess(string workdir, string cmdfile, string cmdline, IVsOutputWindowPane pane)
{
	/////////////
	auto srpIVsLaunchPadFactory = queryService!(IVsLaunchPadFactory);
	if (!srpIVsLaunchPadFactory)
		return false;
	scope(exit) release(srpIVsLaunchPadFactory);

	ComPtr!(IVsLaunchPad) srpIVsLaunchPad;
	HRESULT hr = srpIVsLaunchPadFactory.CreateLaunchPad(&srpIVsLaunchPad.ptr);
	if(FAILED(hr) || !srpIVsLaunchPad.ptr)
		return OutputErrorString(format("internal error: IVsLaunchPadFactory.CreateLaunchPad failed with rc=%x", hr));

	try
	{
		std.file.write(cmdfile, cmdline);
	}
	catch(FileException e)
	{
		return OutputErrorString(format("internal error: cannot write file " ~ cmdfile ~ "\n"));
	}
	//		scope(exit) std.file.remove(cmdfile);

	string quiet = Package.GetGlobalOptions().echoCommands ? "" : "/Q ";
	BSTR bstrOutput;
	DWORD result;
	hr = srpIVsLaunchPad.ExecCommand(/* [in] LPCOLESTR pszApplicationName           */ _toUTF16z(getCmdPath()),
									 /* [in] LPCOLESTR pszCommandLine               */ _toUTF16z(quiet ~ "/C " ~ quoteFilenameForCmd(cmdfile)),
									 /* [in] LPCOLESTR pszWorkingDir                */ _toUTF16z(workdir),      // may be NULL, passed on to CreateProcess (wee Win32 API for details)
									 /* [in] LAUNCHPAD_FLAGS lpf                    */ LPF_PipeStdoutToOutputWindow,
									 /* [in] IVsOutputWindowPane *pOutputWindowPane */ pane, // if LPF_PipeStdoutToOutputWindow, which pane in the output window should the output be piped to
									 /* [in] ULONG nTaskItemCategory                */ 0, // if LPF_PipeStdoutToTaskList is specified
									 /* [in] ULONG nTaskItemBitmap                  */ 0, // if LPF_PipeStdoutToTaskList is specified
									 /* [in] LPCOLESTR pszTaskListSubcategory       */ null, // "Build"w.ptr, // if LPF_PipeStdoutToTaskList is specified
									 /* [in] IVsLaunchPadEvents *pVsLaunchPadEvents */ null, //pLaunchPadEvents,
									 /* [out] DWORD *pdwProcessExitCode             */ &result,
									 /* [out] BSTR *pbstrOutput                     */ &bstrOutput); // all output generated (may be NULL)

	return hr == S_OK && result == 0;
}

bool launchDubCommand(Config cfg, string command)
{
	IVsOutputWindowPane pane = getVisualDOutputPane();
	if(!pane)
		return false;
	scope(exit) release(pane);

	string workdir = normalizeDir(cfg.GetProjectDir());
	string precmd = cfg.getEnvironmentChanges();
	string cmd = precmd ~ cfg.getDubCommandLine(command, false) ~ "\n";
	cmd = cmd ~ "\nif %errorlevel% neq 0 echo dub " ~ command ~ " failed!\n";
	cmd = cmd ~ "\nif %errorlevel% == 0 echo dub " ~ command ~ " done.\n";

	string cmdfile = makeFilenameAbsolute(stripExtension(cfg.GetCommandLinePath(false)) ~ "." ~ command ~ ".cmd", workdir);
	mkdirRecurse(dirName(cmdfile));

	cmd = cfg.GetProjectOptions().replaceEnvironment(cmd, cfg);

	pane.Activate();
	return launchBatchProcess(workdir, cmdfile, cmd, pane);
}

bool refreshDubProject(Project prj)
{
	Config cfg = GetActiveConfig(prj);
	if (!cfg)
		return false;

	return launchDubCommand(cfg, "generate");
}
